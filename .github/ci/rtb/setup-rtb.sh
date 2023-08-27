#!/bin/sh

set -e
set -u

echo '> Source: https://github.com/processone/rtb'

echo '>> Build RTB docker container image'
docker build -t localhost/rtb:latest \
    --build-arg UID=${RUNNER_UID:-1001} \
    -f .github/ci/rtb/rtb.Dockerfile .

echo '>> Create RTB configuration file'
cat > rtb.yml <<-EOF
scenario: xmpp
interval: 10
capacity: ${CAPACITY:-1000}
certfile: cert.pem

jid: user%@${XMPP_DOMAIN:-example.com}
password: pass%

servers:
- tcp://${LB_IP:-172.18.255.200}:5222
#- tls://${LB_IP:-172.18.255.200}:5223

stats_dir: /rtb/stats
www_dir: /rtb/www
# www_port: 8080
debug: false

message_interval: 120
muc_message_interval: 120
presence_interval: 120
disconnect_interval: 120
proxy65_interval: false
http_upload_interval: 120
starttls: false
EOF

echo '>> Print RTB configuration file'
cat rtb.yml

echo '>> Create test users for RTB'
i=1
while [ "$i" -le "${CAPACITY:-1000}" ]
do
    kubectl exec sts/ejabberd -c ejabberd -- wget -q 127.0.0.1:5281/api/register -O - \
    --post-data "{\"user\":\"user$i\",\"host\":\"${XMPP_DOMAIN:-example.com}\",\"password\": \"pass$i\"}"
    i=$((i + 1))
    echo ''
done

echo '>> Create an everybody roster group for RTB'
kubectl exec sts/ejabberd -c ejabberd -- wget -q 127.0.0.1:5281/api/push_alltoall -O - \
    --post-data "{\"host\":\"${XMPP_DOMAIN:-example.com}\",\"group\": \"Everypody\"}"

# echo '>> Start RTB container'
# docker run -d --name rtb --net=host \
#     -v $PWD/rtb.yml:/rtb/rtb.yml \
#     -v $PWD/server.pem:/rtb/server.pem \
#     -v /tmp/rtb/www:/rtb/www:rw \
#     -v /tmp/rtb/stats:/rtb/stats:rw \
#     localhost/rtb:latest
#
# echo '>> Wait shortly and print docker container logs'
# sleep 10s
# docker logs rtb
