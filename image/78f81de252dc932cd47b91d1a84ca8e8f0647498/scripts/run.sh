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

# Clustering variables - include into ejabberdctl container image later
pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_endpoint_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
pod_namespace="${POD_NAMESPACE:-default}"
headless_svc="$(hostname -d)" # e.g. servicename.namespace.default.svc.cluster.local
svc_pod_names="$(nslookup -q=srv "$headless_svc" | grep "$headless_svc" | awk '{print $NF}')"
cluster_pod_names="$(echo $svc_pod_names | sed -e "s|$pod_name.$headless_svc||g")"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"
ready_file="$HOME/.ejabberd_ready"
election_name="${ELECTION_NAME:-ejabberd}"
election_url="${ELECTION_URL:-127.0.0.1:4040}"
election_ttl="${ELECTION_TTL:-10s}"

if [ -e "$ready_file" ]
then
    rm "$ready_file"
fi

if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
then
    sleep "$election_ttl"
    elector -election "$election_name" \
            -namespace "$pod_namespace" \
            -http "$election_url" \
            -ttl "$election_ttl" &
    export pid_elector=$!
    info "==> Wait for elector sidecar to be available on $election_url ..."
    while ! nc -z "$election_url"; do sleep 1; done
    info "==> elector sidecar is available on $election_url ..."
    export election='elector'
else
    export election='standalone'
fi

info "==> This is ejabberd node $sts_name@$pod_endpoint_name ..."

# inspired by https://github.com/Lykos153/ejabberd-cluster-k8s
_leader_pod() {
    leader="$(wget -cq "$election_url" -O - | jq -r .leader)"
    leader_fqdn="${leader}.${headless_svc}"
    printf "${sts_name}@${leader_fqdn}"
}

_join_cluster_elector() {
    while true
    do
        if [ "$(wget -cq "$election_url" -O - | jq .is_leader)" == "true" ]
        then
            info "==> $sts_name@$pod_endpoint_name is elected as leader ..."

            if [ ! -z "$cluster_pod_names" ] && [ ! "$cluster_pod_names" = 'NXDOMAIN' ]
            then
                export join_pod_name="$(echo $cluster_pod_names | awk 'END{ print $1 }')"
                info "==> Found other healthy pods, joining $join_pod_name ..."
                ejabberdctl join_cluster "${join_pod_name}" && return 0
                sleep 5
            else
                info "==> Getting ready and waiting for others to join ..."
                return 0
            fi
        else
            leader_pod="$(_leader_pod)"
            info "Trying to join ${leader_pod}..."
            ejabberdctl join_cluster "${leader_pod}" && return 0
            sleep 5
        fi
    done
}

_join_cluster_standalone() {
    if [ -z "$cluster_pod_names" ] || [ "$cluster_pod_names" = 'NXDOMAIN' ]
    then
        info 'No ejabberd cluster detected, continuing ...'
    else
        info 'ejabberd cluster detected ...'
        export join_pod_name="$(echo $cluster_pod_names | awk 'END{ print $1 }')"
        info "Will join ejabberd pod $sts_name@$join_pod_name at startup ..."
        if [ -z "${CTL_ON_START-}" ]
        then export CTL_ON_START="join_cluster $sts_name@$join_pod_name"
        else export CTL_ON_START="join_cluster $sts_name@$join_pod_name ; $CTL_ON_START"
        fi
    fi
    return 0
}

## Termination
pid_ejabberd=0

# trap for graceful shutdown, disconnection from cluster happens automatically
_shutdown() {
    kill -s TERM "$pid_elector"
    if [ "$pid_ejabberd" -ne 0 ]
    then
        info "==> Gracefully shut down ejabberd pod $sts_name@$pod_endpoint_name ..."
        NO_WARNINGS=true ejabberdctl leave_cluster "$sts_name@$pod_endpoint_name"
        ejabberdctl stop > /dev/null
        ejabberdctl stopped > /dev/null
        kill -s TERM "$pid_ejabberd"
        exit $1
    fi
}

# trap SIGTERM
trap '_shutdown' SIGTERM

info '==> Start ejabberd main process ...'
ejabberdctl foreground &
pid_ejabberd=$!
ejabberdctl started
if [ "${K8S_CLUSTERING:-false}" = 'true' ]
then
    _join_cluster_"$election" && touch "$ready_file" || _shutdown $?
fi
wait ${pid_ejabberd-} ${pid_elector-}
