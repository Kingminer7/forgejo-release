#!/bin/sh
# SPDX-License-Identifier: MIT

set -ex

DIR=$(mktemp -d)

trap "rm -fr $DIR" EXIT

test_teardown() {
    setup_api
    api DELETE repos/$REPO/releases/tags/$TAG || true
    api DELETE repos/$REPO/tags/$TAG || true
    rm -fr dist/release
    setup_tea
    $BIN_DIR/tea login delete $DOER || true
}

test_reset_repo() {
    local project="$1"
    api DELETE repos/$REPO || true
    api POST user/repos --data-raw '{"name":"'$project'", "auto_init":true}'
    git clone $FORGEJO/$REPO $DIR/repo
    SHA=$(git -C $DIR/repo rev-parse HEAD)
}

test_setup() {
    local project="$1"
    test_reset_repo $project
    mkdir -p $RELEASE_DIR
    touch $RELEASE_DIR/file-one.txt
    touch $RELEASE_DIR/file-two.txt
}

test_ensure_tag() {
    api DELETE repos/$REPO/tags/$TAG || true
    #
    # idempotent
    #
    ensure_tag
    api GET repos/$REPO/tags/$TAG > $DIR/tag1.json
    ensure_tag
    api GET repos/$REPO/tags/$TAG > $DIR/tag2.json
    diff -u $DIR/tag[12].json
    #
    # sanity check on the SHA of an existing tag
    #
    (
	SHA=12345
	! ensure_tag
    )
    api DELETE repos/$REPO/tags/$TAG
}

test_run() {
    local user="$1"
    local project="$2"
    test_teardown
    to_push=$DIR/binaries-releases-to-push
    pulled=$DIR/binaries-releases-pulled
    RELEASE_DIR=$to_push
    REPO=$user/$project
    test_setup $project
    test_ensure_tag
    echo "================================ TEST BEGIN"
    upload
    RELEASE_DIR=$pulled
    download
    diff -r $to_push $pulled
    echo "================================ TEST END"
}

: ${TAG:=v17.8.20-1}

. $(dirname $0)/../forgejo-release.sh
