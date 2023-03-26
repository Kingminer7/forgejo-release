#!/bin/sh

set -ex

DIR=$(mktemp -d)

#trap "rm -fr $DIR" EXIT

test_teardown() {
    setup_api
    api DELETE repos/$PUSH_USER/$REPO/releases/tags/$TAG || true
    api DELETE repos/$PUSH_USER/$REPO/tags/$TAG || true
    rm -fr dist/release
    setup_tea
    $BIN_DIR/tea login delete $RELEASETEAMUSER || true
}

test_reset_repo() {
    api DELETE repos/$PUSH_USER/$REPO || true
    api POST user/repos --data-raw '{"name":"'$REPO'", "auto_init":true}'
    git clone $FORGEJO/$PUSH_USER/$REPO $DIR/repo
    CI_COMMIT_SHA=$(git -C $DIR/repo rev-parse HEAD)
}

test_setup() {
    test_reset_repo
    mkdir -p $RELEASE_DIR
    touch $RELEASE_DIR/file-one.txt
    touch $RELEASE_DIR/file-two.txt
}

test_ensure_tag() {
    api DELETE repos/$PUSH_USER/$REPO/tags/$TAG || true
    #
    # idempotent
    #
    ensure_tag
    api GET repos/$PUSH_USER/$REPO/tags/$TAG > $DIR/tag1.json
    ensure_tag
    api GET repos/$PUSH_USER/$REPO/tags/$TAG > $DIR/tag2.json
    diff -u $DIR/tag[12].json
    #
    # sanity check on the SHA of an existing tag
    #
    (
	CI_COMMIT_SHA=12345
	! ensure_tag
    )
    api DELETE repos/$PUSH_USER/$REPO/tags/$TAG
}

test_run() {
    test_teardown
    to_push=$DIR/binaries-releases-to-push
    pulled=$DIR/binaries-releases-pulled
    RELEASE_DIR=$to_push
    test_setup
    test_ensure_tag
    echo "================================ TEST BEGIN"
    push
    RELEASE_DIR=$pulled
    pull
    diff -r $to_push $pulled
    echo "================================ TEST END"
}

: ${RELEASETEAMUSER:=root}
: ${REPO:=testrepo}
: ${CI_REPO_OWNER:=root}
: ${PULL_USER=$CI_REPO_OWNER}
: ${PUSH_USER=$CI_REPO_OWNER}
: ${CI_COMMIT_TAG:=v17.8.20-1}

. $(dirname $0)/../forgejo-release.sh
