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
}

# _join_cluster() {
#     if [ "$is_leader" = 'true' ] && ( [ -z "$cluster_pod_names" ] || [ "$cluster_pod_names" = 'NXDOMAIN' ] )
#     then
#         info '==> No healthy pods detected, continuing ...'
#         touch "$ready_file" || _shutdown
#     elif [ "$is_leader" = 'false' ] || ( [ ! -z "$cluster_pod_names" ] && [ ! "$cluster_pod_names" = 'NXDOMAIN' ] )
#     then
#         info '==> Found other healthy pods ...'
#         if [ "${ELECTOR_ENABLED:-false}" = 'true' ] && [ "$is_leader" = 'false' ]
#         then export join_pod_name="$(wget -cq "$election_url" -O - | jq -r .leader).${headless_svc}"
#         else export join_pod_name="$(echo $cluster_pod_names | sort -n | awk 'NR==1{print $1}')"
#         fi
#         while ! nc -z "$join_pod_name:${ERL_DIST_PORT:-5210}"; do sleep 1; done
#         info "==> Will join ejabberd pod $sts_name@$join_pod_name at startup ..."
#         ejabberdctl join_cluster $sts_name@$join_pod_name && sleep 5s
#     fi
# }

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
        ejabberdctl stop
        ejabberdctl stopped
    fi
}

# trap SIGTERM
trap '_shutdown' SIGTERM

info '==> Start ejabberd main process ...'
ejabberdctl foreground &
pid_ejabberd=$!

## Start elector, if enabled
export is_leader='false'
[ "${ELECTOR_ENABLED:-false}" = 'true' ] && _start_elector

ejabberdctl started
# [ "${K8S_CLUSTERING:-false}" = 'true' ] && _join_cluster
STARTUP='true' healthcheck.sh || _shutdown

wait ${pid_ejabberd-} ${pid_elector-}
