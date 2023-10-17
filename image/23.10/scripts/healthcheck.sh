#!/bin/sh

myself=${0##*/}

info()
{
    echo "$myself: $*"
}

error()
{
    echo >&2 "$myself: $*"
}

pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_endpoint_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
headless_svc="$(hostname -d)" # e.g. servicename.namespace.default.svc.cluster.local
svc_pod_names="$(nslookup -q=srv "$headless_svc" | grep "$headless_svc" | awk '{print $NF}')"
cluster_pod_names="$(echo $svc_pod_names | sed -e "s|$pod_name.$headless_svc||g")"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"
api_url="127.0.0.1:5281"
pod_status="$(wget -O - --post-data '{}' $api_url/api/status || echo 'unhealthy')"
election_url="${ELECTION_URL:-127.0.0.1:4040}"

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
        touch $HOME/.ejabberd_ready && return 0
    elif echo "$(_cluster_member)" | grep -q "$join_pod_name"
    then
        info "==> $pod_name is clustered w/ pod w/ lowest ordinal $join_pod_name ..."
        touch $HOME/.ejabberd_ready && return 0
    else
        info "==> Leaving former cluster ..."
        NO_WARNINGS=true ejabberdctl leave_cluster "$sts_name@$pod_name.${headless_svc}"
        while ! nc -z "$join_pod_name:${ERL_DIST_PORT:-5210}"; do sleep 1; done
        info "==> Will (re-)join ejabberd pod $sts_name@$join_pod_name ..."
        ejabberdctl join_cluster "$sts_name@$join_pod_name" && sleep 5s
        if echo "$(_cluster_member)" | grep -q "$join_pod_name"
        then
            touch $HOME/.ejabberd_ready && return 0
        else
            return 3
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
    while ! nc -z "$leader.${headless_svc}:${ERL_DIST_PORT:-5210}"; do sleep 1; done
    info "==> Will (re-)join leader "$sts_name@$leader.${headless_svc}" ..."
    ejabberdctl join_cluster "$sts_name@$leader.${headless_svc}" && sleep 5s
    if echo "$(_cluster_member)" | grep -q "$leader"
    then
        touch $HOME/.ejabberd_ready && return 0
    else
        return 3
    fi
}

if [ ! "$pod_status" = 'unhealthy' ] && ([ -e $HOME/.ejabberd_ready ] || [ "${STARTUP:-false}" = 'true' ] )
then
    if [ "${K8S_CLUSTERING:-false}" = 'false' ]
    then
        [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
        return 0
    elif [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then
        export leader="$(wget -cq $election_url -O - | jq -r .leader)"
        ## leader is always right!
        if [ "$leader" = "$pod_name" ]
        then
            info "==> $pod_name is elected leader and healthy ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
            return 0
        ## if leader is not part of fellow's cluster list, re-join leader.
        elif echo "$(_cluster_member)" | grep -q "$leader"
        then
            info "==> $pod_name is fellow, healthy and connected to leader $leader ..."
            [ ! -e "$HOME/.ejabberd_ready" ] && touch $HOME/.ejabberd_ready
            return 0
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
        return 0
    fi
else
    return 3
fi
