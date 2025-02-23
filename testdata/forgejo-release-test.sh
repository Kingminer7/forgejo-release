#!/bin/bash
# SPDX-License-Identifier: MIT

set -ex
PS4='${BASH_SOURCE[0]}:$LINENO: ${FUNCNAME[0]}:  '

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
    git clone $FORGEJO/$REPO $TMP_DIR/repo
    SHA=$(git -C $TMP_DIR/repo rev-parse HEAD)
}

test_setup() {
    local project="$1"
    test_reset_repo $project
    mkdir -p $RELEASE_DIR
    touch $RELEASE_DIR/file-one.txt
    touch $RELEASE_DIR/file-two.txt
}

test_wait_release_fail() {
    ! wait_release
}

test_wait_release() {
    wait_release
    release_draft true
    ! wait_release
}

test_ensure_tag() {
    api DELETE repos/$REPO/tags/$TAG || true
    #
    # idempotent
    #
    ensure_tag
    mv $TAG_FILE $TMP_DIR/tag1.json

    ensure_tag
    mv $TAG_FILE $TMP_DIR/tag2.json

    diff -u $TMP_DIR/tag[12].json
    #
    # sanity check on the SHA of an existing tag
    #
    (
        SHA=12345
        ! matched_tag
        ! ensure_tag
    )
    api DELETE repos/$REPO/tags/$TAG
}

test_maybe_sign_release_no_gpg() {
    test_maybe_sign_release_setup no_gpg

    GPG_PRIVATE_KEY=
    maybe_sign_release

    ! test -f $RELEASE_DIR/file-one.txt.asc
}

test_maybe_sign_release_gpg_no_passphrase() {
    test_maybe_sign_release_setup gpg_no_passphrase

    GPG_PRIVATE_KEY=testdata/gpg-private-no-passphrase.asc
    maybe_sign_release

    test_maybe_sign_release_skipped
    test_maybe_sign_release_verify
}

test_maybe_sign_release_gpg() {
    test_maybe_sign_release_setup gpg

    GPG_PRIVATE_KEY=testdata/gpg-private.asc
    GPG_PASSPHRASE=testdata/gpg-private.passphrase
    maybe_sign_release

    test_maybe_sign_release_skipped
    test_maybe_sign_release_verify
}

test_maybe_sign_release_skipped() {
    ! test -f $RELEASE_DIR/file-one.txt.sha256.asc
    ! test -f $RELEASE_DIR/file-two.txt.sha256.asc
}

test_maybe_sign_release_verify() {
    for file in $RELEASE_DIR/file-one.txt $RELEASE_DIR/file-two.txt; do
        gpg --verify $file.asc $file
    done
}

test_maybe_sign_release_setup() {
    local name="$1"

    echo "========= maybe_sign_release $name ========="
    RELEASE_DIR=$TMP_DIR/$name
    mkdir -p $RELEASE_DIR
    GNUPGHOME=$TMP_DIR/$name/.gnupg
    mkdir -p $GNUPGHOME
    touch $RELEASE_DIR/file-one.txt
    touch $RELEASE_DIR/file-one.txt.sha256
    touch $RELEASE_DIR/file-two.txt
    touch $RELEASE_DIR/file-two.txt.sha256
}

test_maybe_sign_release() {
    test_maybe_sign_release_no_gpg
    test_maybe_sign_release_gpg_no_passphrase
    test_maybe_sign_release_gpg
}

test_run() {
    local user="$1"
    local project="$2"
    test_teardown
    to_push=$TMP_DIR/binaries-releases-to-push
    pulled=$TMP_DIR/binaries-releases-pulled
    RELEASE_DIR=$to_push
    REPO=$user/$project
    test_setup $project
    test_ensure_tag
    DELAY=0
    test_wait_release_fail
    echo "================================ TEST BEGIN"
    upload
    RELEASE_DIR=$pulled
    download
    diff -r $to_push $pulled
    echo "================================ TEST END"
    test_wait_release
}

TMP_DIR=$(mktemp -d)

trap "rm -fr $TMP_DIR" EXIT

: ${TAG:=v17.8.20-1}

. $(dirname $0)/../forgejo-release.sh
