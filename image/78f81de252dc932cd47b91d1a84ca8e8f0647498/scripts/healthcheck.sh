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
election_leader="$(wget -cq ${ELECTION_URL:-127.0.0.1:4040} -O - | jq -r .leader)"

# In some cases it needs to be called twice.
_cluster_member_count() {
    count="$(wget -q -O - --post-data '{}' $api_url/api/list_cluster | egrep -o '[^][]+' | tr ',' '\n' | wc -l)"
    printf "$count"
}

if [ ! "$pod_status" = 'unhealthy' ] && [ -e $HOME/.ejabberd_ready ]
then
    if [ "${ELECTOR_ENABLED:-false}" = 'true' ]
    then
        if [ "$election_leader" = "$pod_name" ]
        then
            ## TODO: Consider 'set_master self' here to counter brain-splits.
            # ejabberdctl set_master self && return 0
            return 0
        elif [ "$(_cluster_member_count)" = "1" ]
        then
            rm $HOME/.ejabberd_ready
            ## try re-joining ejabberd cluster
            join_pod_name="$election_leader.${headless_svc}"
            info "==> Will re-join via ejabberd pod $sts_name@$join_pod_name ..."
            ejabberdctl join_cluster "$sts_name@$join_pod_name" && sleep 5
            if [ "$(_cluster_member_count)" = "1" ]
            then
                return 3
            else
                touch $HOME/.ejabberd_ready && return 0
            fi
        elif [ ! "$election_leader" = "$pod_name" ] && [ "$(_cluster_member_count)" -gt "1" ]
        then
            return 0
        fi
    elif [ ! "$(_cluster_member_count)" = "$(echo $svc_pod_names | wc -l)" ]
    then
        rm $HOME/.ejabberd_ready
        ## try re-joining ejabberd cluster
        join_pod_name="$(echo $cluster_pod_names | awk 'END{ print $1 }')"
        info "==> Will re-join ejabberd pod $sts_name@$join_pod_name ..."
        ejabberdctl join_cluster "$sts_name@$join_pod_name" && sleep 5
        if [ ! "$(_cluster_member_count)" = "$(echo $svc_pod_names | wc -l)" ]
        then
            return 3
        else
            touch $HOME/.ejabberd_ready && return 0
        fi
    else
        return 0
    fi
else
    return 3
fi
