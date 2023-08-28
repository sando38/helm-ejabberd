#!/bin/sh

pod_name="${POD_NAME:-$(hostname -s)}" # e.g. pod-0
pod_endpoint_name="$(hostname -f)" # e.g. pod-0.servicename.namespace.svc.cluster.local
headless_svc="$(hostname -d)" # e.g. servicename.namespace.default.svc.cluster.local
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
    fi
else
    return 3
fi
