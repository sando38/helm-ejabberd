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

info 'Start init script for ejabberd k8s container ...'
info 'Helm chart source code can be found on github:'
info '  https://github.com/sando38/helm-ejabberd'
info 'Official ejabberd documentation on https://docs.ejabberd.im ...'
info 'Source code on https://github.com/processone/ejabberd ...'

info 'NOTE:'
info '  If you run this image in a single app environment, e.g. with Docker,'
info '  then set the environment variable:'
info '      ERLANG_NODE_ARG=ejabberd@localhost'
info '  for improved compatibility. More info can be found here:'
info '  https://github.com/processone/docker-ejabberd/tree/master/ecs#change-mnesia-node-name'
info ''
info 'Thanks to all who made this work possible. Special thanks to Holger Weiß'
info '@weiss for open ears and brainstorming!'
info ''

# Clustering variables - include into ejabberdctl container image later
pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_svc_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
headless_svc="${pod_svc_name/$pod_name./}" # e.g. servicename.namespace.default.svc.cluster.local
svc_pod_names="$(nslookup -q=srv "$headless_svc" | grep "$headless_svc" | awk '{print $NF}')"
cluster_pod_names="$(echo $svc_pod_names | sed -e "s|$pod_name.$headless_svc||g")"
sts_name="$(echo $pod_name | sed 's|-[0-9]\+||g')"

info "This ejabberd pod's name is $sts_name@$pod_svc_name ..."

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

info 'Finished init script, wait shortly ...'
sleep "${WAIT_PERIOD:-0}"

# trap for graceful shutdown, disconnection from cluster happens automatically
_cleanup() {
    info "==> Gracefully shut down ejabberd pod $sts_name@$pod_svc_name ..."
    ejabberdctl stop
    ejabberdctl stopped
}

# trap SIGTERM
trap '_cleanup' SIGTERM

info 'Start ejabberd main process ...'
exec ejabberdctl foreground &
pid=$!
wait $pid
