#!/bin/bash

set -ex

: ${FORGEJO_RUNNER_LOGS:=../setup-forgejo/forgejo-runner.log}
DATA=$(dirname $0)
DIR=$(mktemp -d)

trap "rm -fr $DIR" EXIT

function check_status() {
    local forgejo="$1"
    local repo="$2"
    local sha="$3"

    if ! which jq > /dev/null ; then
	apt-get install -y -qq jq
    fi
    local state=$(curl --fail -sS "$forgejo/api/v1/repos/$repo/commits/$sha/status" | jq --raw-output .state)
    echo $state
    test "$state" != "" -a "$state" != "pending" -a "$state" != "running" -a "$state" != "null"
}

function wait_success() {
    local forgejo="$1"
    local repo="$2"
    local sha="$3"

    for i in $(seq 40); do
	if check_status "$forgejo" "$repo" "$sha"; then
	    break
	fi
	sleep 5
    done
    if ! test "$(check_status "$forgejo" "$repo" "$sha")" = "success" ; then
	cat $FORGEJO_RUNNER_LOGS
	return 1
    fi
}

function push() {
    local forgejo="$1"
    local owner="$2"
    local workflow="$3"

    local dir="$DIR/$workflow"
    mkdir -p $dir/.forgejo/workflows
    sed -e "s|SELF|$forgejo/$owner|" \
	< $DATA/$workflow.yml > $dir/.forgejo/workflows/$workflow.yml
    (
	cd $dir
	git init
	git checkout -b main
	git config user.email root@example.com
	git config user.name username
	git add .
	git commit -m 'initial commit'
	git remote add origin $forgejo/$owner/$workflow
	git push --force -u origin main
	git rev-parse HEAD > SHA
    )
}

function workflow() {
    local forgejo="${1}"
    local owner="${2}"
    local workflow="${3}"

    push "$forgejo" "$owner" "$workflow"
    wait_success "$forgejo" "$owner/$workflow" $(cat $DIR/$workflow/SHA)
}

function push_self() {
    local forgejo="$1"
    local owner="$2"
    local self="$3"

    local dir="$DIR/self"
    git clone . $dir
    (
	cd $dir
	rm -fr .forgejo .git
	git init
	git checkout -b main
	git remote add origin $forgejo/$owner/$self
	git config user.email root@example.com
	git config user.name username
	git add .
	git commit -m 'initial commit'
	git push --force origin main
	git tag --force vTest HEAD
	git push --force origin vTest
    )
}

"$@"
