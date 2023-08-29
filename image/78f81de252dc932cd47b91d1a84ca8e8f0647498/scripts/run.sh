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

# Clustering variables
pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_endpoint_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
pod_namespace="${POD_NAMESPACE:-default}"
headless_svc="$(hostname -d)" # e.g. servicename.namespace.default.svc.cluster.local
svc_pod_names="$(nslookup -q=srv "$headless_svc" | grep "$headless_svc" | awk '{print $NF}')"
cluster_pod_names="$(echo $svc_pod_names | sed -e "s|$pod_name.$headless_svc||g")"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"
election_name="${ELECTION_NAME:-ejabberd}"
election_url="${ELECTION_URL:-127.0.0.1:4040}"
election_ttl="${ELECTION_TTL:-10s}"
ready_file="$HOME/.ejabberd_ready"

if [ -e "$ready_file" ]
then rm "$ready_file"
fi

info "==> This is ejabberd node $sts_name@$pod_endpoint_name ..."

## Inspired by https://github.com/Lykos153/ejabberd-cluster-k8s
## TODO: Write an ejabberd module for https://github.com/vapor-ware/k8s-elector
##       or check: https://github.com/bitwalker/libcluster
##                 https://github.com/pedro-gutierrez/cluster
_start_elector() {
    export is_leader='false'

    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then
        info "==> Start elector sidecar service on $election_url ..."
        elector -election "$election_name" \
                -namespace "$pod_namespace" \
                -http "$election_url" \
                -ttl "$election_ttl" &
        export pid_elector=$!

        info "==> Wait for elector sidecar to be available on $election_url ..."
        while ! nc -z "$election_url"; do sleep 1; done
        info "==> elector sidecar is available on $election_url ..."

        if [ "$(wget -cq "$election_url" -O - | jq .is_leader)" == "true" ]
        then export is_leader='true'
        fi
    fi
}

_join_cluster() {
    if [ "$is_leader" = 'true' ] && ( [ -z "$cluster_pod_names" ] || [ "$cluster_pod_names" = 'NXDOMAIN' ] )
    then
        info '==> No healty pods detected, continuing ...'
    elif [ "$is_leader" = 'false' ] || ( [ ! -z "$cluster_pod_names" ] && [ ! "$cluster_pod_names" = 'NXDOMAIN' ] )
    then
        info '==> Found other healthy pods ...'
        if [ "${ELECTOR_ENABLED:-false}" = 'true' ] && [ "$is_leader" = 'false' ]
        then export join_pod_name="$(wget -cq "$election_url" -O - | jq -r .leader).${headless_svc}"
        else export join_pod_name="$(echo $cluster_pod_names | awk 'END{ print $1 }')"
        fi
        while ! nc -z "$join_pod_name:${ERL_DIST_PORT:-5210}"; do sleep 1; done
        info "==> Will join ejabberd pod $sts_name@$join_pod_name at startup ..."
        if [ -z "${CTL_ON_START-}" ]
        ## TODO: Consider prepending 'set_master $sts_name@$join_pod_name' here
        ##       to counter brain-splits, perhaps also optional via variables?
        then export CTL_ON_START="join_cluster $sts_name@$join_pod_name"
        else export CTL_ON_START="join_cluster $sts_name@$join_pod_name ; $CTL_ON_START"
        fi
    fi
}

if [ "${K8S_CLUSTERING:-false}" = 'true' ]
then
    _start_elector
    _join_cluster
fi

## Termination
pid_ejabberd=0

# trap for graceful shutdown
_shutdown() {
    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then kill -s TERM "$pid_elector"
    fi
    ## disconnection from cluster happens automatically
    if [ "$pid_ejabberd" -ne 0 ]
    then
        info "==> Gracefully shut down ejabberd pod $sts_name@$pod_endpoint_name ..."
        ejabberdctl stop > /dev/null
        ejabberdctl stopped > /dev/null
    fi
}

# trap SIGTERM
trap '_shutdown' SIGTERM

info '==> Start ejabberd main process ...'
ejabberdctl foreground &
pid_ejabberd=$!
# CTL_ON_START uses a 2s interval to check status, before applying the commands
ejabberdctl started && sleep 5s
ejabberdctl started && touch "$ready_file"
wait ${pid_ejabberd-} ${pid_elector-}
