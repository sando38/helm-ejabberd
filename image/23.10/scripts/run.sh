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
pod_namespace="${POD_NAMESPACE:-default}"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"
election_name="${ELECTION_NAME:-ejabberd}"
election_url="${ELECTION_URL:-127.0.0.1:4040}"
election_ttl="${ELECTION_TTL:-10s}"
ready_file="$HOME/.ejabberd_ready"

[ -e "$ready_file" ] && rm "$ready_file"

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
}

# trap for graceful shutdown
_shutdown() {
    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then kill -s TERM "$pid_elector"
    fi
    ## disconnection from cluster happens automatically
    info "==> Gracefully shut down ejabberd pod $sts_name@$pod_endpoint_name ..."
    ejabberdctl stop
    ejabberdctl stopped
}

# trap SIGTERM
trap '_shutdown' SIGTERM

info '==> Start ejabberd main process ...'
ejabberdctl foreground &
pid_ejabberd=$!

## Start elector, if enabled
[ "${ELECTOR_ENABLED:-false}" = 'true' ] && _start_elector

ejabberdctl started
STARTUP='true' healthcheck.sh || _shutdown

wait ${pid_ejabberd-} ${pid_elector-}
