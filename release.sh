#!/bin/sh

set -e
set -u

chart_dir='charts/ejabberd'
gh_user='sando38'
gh_repo='helm-ejabberd'

git checkout main

if ! [ -f 'token' ] || ! [ -d "$chart_dir" ]
then
    echo "Error: call this script with the GH token being available"
    exit 1
fi

helm package "$chart_dir" --destination .deploy
cr upload \
    -o "$gh_user" \
    -r "$gh_repo" \
    -p .deploy \
    --token "$(cat token)" \
    --skip-existing

git checkout gh-pages

cr index -i ./index.yaml -p .deploy --owner "$gh_user" --git-repo "$gh_repo"

git add index.yaml
