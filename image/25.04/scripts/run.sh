#!/bin/sh

set -e
set -u

myself=${0##*/}

info()
{
    echo "$myself: $*"
}

error()
{
    echo >&2 "$myself: $*"
}

info '=> Start init script for ejabberd k8s container ...'
info '==> Helm chart source code can be found on github:'
info '    https://github.com/sando38/helm-ejabberd'
info '==> Official ejabberd documentation on https://docs.ejabberd.im ...'
info '==> Source code on https://github.com/processone/ejabberd ...'
info ''
info '=> NOTE:'
info '   If you run this image in a single app environment, e.g. with Docker,'
info '   then set the environment variable:'
info '       ERLANG_NODE_ARG=ejabberd@localhost'
info '   for improved compatibility. More info can be found here:'
info '   https://github.com/processone/docker-ejabberd/tree/master/ecs#change-mnesia-node-name'
info ''
info '=> Thanks to all who made this work possible. Special thanks to Holger'
info '   @weiss for open ears and brainstorming!'
info ''
info "=> Pod started on $(date)."
info ''

# Common variables
pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_endpoint_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
headless_svc="$(hostname -d)" # e.g. servicename.namespace.default.svc.cluster.local
pod_namespace="${POD_NAMESPACE:-default}"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"
election_name="${ELECTION_NAME:-ejabberd}"
election_url="${ELECTION_URL:-127.0.0.1:4040}"
election_ttl="${ELECTION_TTL:-5s}"
svc_pod_names="$(nslookup -q=srv "$headless_svc" | grep "$headless_svc" | awk '{print $NF}')"
cluster_pod_names="$(echo $svc_pod_names | sed -e "s|$pod_name.$headless_svc||g")"
api_url="${HTTP_API_URL:-127.0.0.1:5281}"
ready_file="$HOME/.ejabberd_ready"

[ -e "$ready_file" ] && rm "$ready_file"

info "==> This is ejabberd node $sts_name@$pod_endpoint_name ..."

## Inspired by https://github.com/Lykos153/ejabberd-cluster-k8s
## TODO: Write an ejabberd module for https://github.com/vapor-ware/k8s-elector
##       or check: https://github.com/bitwalker/libcluster
##                 https://github.com/pedro-gutierrez/cluster
_start_elector() {
    info "==> Start elector sidecar service on $election_url ..."
    elector -v 2 \
            -election "$election_name" \
            -namespace "$pod_namespace" \
            -http "$election_url" \
            -ttl "$election_ttl" &
    export pid_elector=$!

    info "==> Wait for elector sidecar to be available on $election_url ..."
    while ! nc -z $(echo $election_url | sed -e 's/:/ /'); do sleep 1; done
    info "==> elector sidecar is available on $election_url ..."
}

# trap for graceful shutdown
_shutdown() {
    rm -f $HOME/.ejabberd_terminate_false
    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then kill -s TERM "$pid_elector"
    fi
    ## disconnection from cluster happens automatically
    info "==> Gracefully shut down ejabberd pod $sts_name@$pod_endpoint_name ..."
    ejabberdctl stop
    ejabberdctl stopped
}

# List cluster members
_cluster_member() {
    members="$(wget -q -O - --post-data '{}' $api_url/api/list_cluster | egrep -o '[^][]+' | tr ',' '\n')"
    printf "$members"
}

# (Re-)join cluster - DNSSRV derived
_join_cluster_dns() {
    [ -e "$HOME/.ejabberd_ready" ] && rm $HOME/.ejabberd_ready
    join_pod_name="$(echo $cluster_pod_names | sort -n | awk 'NR==1{print $1}')"
    if [ "$pod_name" = "$sts_name-0" ]
    then
        info "==> $pod_name has ordinal zero ..."
        touch $HOME/.ejabberd_ready
    elif echo "$(_cluster_member)" | grep -q "$join_pod_name"
    then
        info "==> $pod_name is clustered w/ pod w/ lowest ordinal $join_pod_name ..."
        touch $HOME/.ejabberd_ready
    else
        info "==> Leaving former cluster ..."
        NO_WARNINGS=true ejabberdctl leave_cluster "$sts_name@$pod_name.${headless_svc}"
        while ! nc -z $join_pod_name ${ERL_DIST_PORT:-5210}; do sleep 1; done
        info "==> Will (re-)join ejabberd pod $sts_name@$join_pod_name ..."
        ejabberdctl join_cluster "$sts_name@$join_pod_name" && sleep 5s
        if echo "$(_cluster_member)" | grep -q "$join_pod_name"
        then touch $HOME/.ejabberd_ready
        fi
    fi
}

# (Re-)join cluster - election derived
_join_cluster_elector() {
    [ -e "$HOME/.ejabberd_ready" ] && rm $HOME/.ejabberd_ready
    if [ "$(echo $(_cluster_member) | wc -l)" -gt "1" ]
    then
        info "==> Leaving non-leader cluster ..."
        NO_WARNINGS=true ejabberdctl leave_cluster "$sts_name@$pod_name.${headless_svc}"
    fi
    while ! nc -z $leader.${headless_svc} ${ERL_DIST_PORT:-5210}; do sleep 1; done
    info "==> Will (re-)join leader "$sts_name@$leader.${headless_svc}" ..."
    ejabberdctl join_cluster "$sts_name@$leader.${headless_svc}" && sleep 5s
    if echo "$(_cluster_member)" | grep -q "$leader"
    then touch $HOME/.ejabberd_ready
    fi
}

# trap SIGTERM
trap '_shutdown' SIGTERM
touch $HOME/.ejabberd_terminate_false

# check first if sidecar has rendered the configmaps/secrets already
while [ ! -e $HOME/conf/ejabberd.yml ]
do
    info "===> $HOME/conf/ejabberd.yml not yet rendered, waiting ..." && sleep 3
done
sleep 3

info '==> Start ejabberd main process ...'
ejabberdctl start
tail -n+1 -F logs/ejabberd.log &
    pid_ejabberd_log=$!
tail -n+1 -F logs/error.log &
    pid_error_log=$!
tail -n+1 -F logs/crash.log &
    pid_crash_log=$!
tail -n+1 -F logs/erlang.log &
    pid_erlang_log=$!
ejabberdctl started

## Start elector, if enabled
[ "${ELECTOR_ENABLED:-false}" = 'true' ] && _start_elector

while true; do

pod_status="$(wget -q -O - --post-data '{}' $api_url/api/status || echo 'unhealthy')"
if [ ! "$pod_status" = 'unhealthy' ] && [ -e $HOME/.ejabberd_ready ]
then
    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then
        export leader="$(wget -cq $election_url -O - | jq -r .leader)"
        ## leader is always right!
        if [ "$leader" = "$pod_name" ]
        then
            info "==> $pod_name is elected leader and healthy ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
        ## if leader is not part of fellow's cluster list, re-join leader.
        elif echo "$(_cluster_member)" | grep -q "$leader"
        then
            info "==> $pod_name is fellow, healthy and connected to leader $leader ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
        else
            info "==> $pod_name is fellow, but not connected to leader $leader ..."
            _join_cluster_elector
        fi
    elif [ ! -z "$cluster_pod_names" ] && [ ! "$cluster_pod_names" = 'NXDOMAIN' ]
    then
        info "==> Other healthy pods detected ..."
        _join_cluster_dns
    else
        info "==> No other healthy pods detected ..."
        [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
    fi
elif [ ! "$pod_status" = 'unhealthy' ] && [ ! -e $HOME/.ejabberd_ready ]
then
    if [ "${K8S_CLUSTERING:-false}" = 'false' ]
    then
        [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
    elif [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then
        export leader="$(wget -cq $election_url -O - | jq -r .leader)"
        ## leader is always right!
        if [ "$leader" = "$pod_name" ]
        then
            info "==> $pod_name is elected leader and healthy ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
        ## if leader is not part of fellow's cluster list, re-join leader.
        elif echo "$(_cluster_member)" | grep -q "$leader"
        then
            info "==> $pod_name is fellow, healthy and connected to leader $leader ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
        else
            info "==> $pod_name is fellow, but not connected to leader $leader ..."
            _join_cluster_elector
        fi
    fi
    if [ ! -e $HOME/.ejabberd_ready ]
    then
        vhosts="$(ejabberdctl registered_vhosts)"
        for vhost in $vhosts
        do
            info "==> $pod_name is healthy, but not ready, delete mnesia for $vhost ..."
            ejabberdctl delete_mnesia "$vhost"
        done
        if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
        then
            export leader="$(wget -cq $election_url -O - | jq -r .leader)"
            #ejabberdctl set_master "$sts_name@$leader.${headless_svc}"
            _join_cluster_elector
        else _join_cluster_dns
        fi
    fi
    if [ ! -e $HOME/.ejabberd_ready ]
    then
        info "==> $pod_name is still not ready, restart ejabberd while removing mnesia folder ..."
        ejabberdctl stop
        ejabberdctl stopped
        rm -rf $HOME/database/*
        ejabberdctl start
        ejabberdctl started
        if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
        then
            export leader="$(wget -cq $election_url -O - | jq -r .leader)"
            #ejabberdctl set_master "$sts_name@$leader.${headless_svc}"
            _join_cluster_elector
        else _join_cluster_dns
        fi
    fi
else
    info "==> $pod_name unhealthy ..."
    [ -e "$HOME/.ejabberd_ready" ] && rm $HOME/.ejabberd_ready
    [ ! $(ejabberdctl started) ] && ejabberdctl start && ejabberdctl started || _shutdown
fi

info "==> check again in 15s ..."
sleep 15s

if [ ! -e $HOME/.ejabberd_terminate_false ]
then break
fi
done

wait ${pid_elector-}
