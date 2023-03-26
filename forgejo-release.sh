#!/bin/bash

set -ex

: ${PULL_USER:=forgejo-integration}
: ${PUSH_USER:=forgejo}
: ${TAG:=${CI_COMMIT_TAG}}
: ${FORGEJO:=https://codeberg.org}
: ${REPO:=forgejo}
: ${RELEASE_DIR:=dist/release}
: ${BIN_DIR:=/tmp}
: ${TEA_VERSION:=0.9.0}


setup_tea() {
    if ! test -f $BIN_DIR/tea ; then
	curl -sL https://dl.gitea.io/tea/$TEA_VERSION/tea-$TEA_VERSION-linux-amd64 > $BIN_DIR/tea
	chmod +x $BIN_DIR/tea
    fi
}

ensure_tag() {
    if api GET repos/$PUSH_USER/$REPO/tags/$TAG > /tmp/tag.json ; then
	local sha=$(jq --raw-output .commit.sha < /tmp/tag.json)
	if test "$sha" != "$CI_COMMIT_SHA" ; then
	    cat /tmp/tag.json
	    echo "the tag SHA in the $PUSH_USER repository does not match the tag SHA that triggered the build: $CI_COMMIT_SHA"
	    false
	fi
    else
	api POST repos/$PUSH_USER/$REPO/tags --data-raw '{"tag_name": "'$CI_COMMIT_TAG'", "target": "'$CI_COMMIT_SHA'"}'
    fi
}

upload() {
    ASSETS=$(ls $RELEASE_DIR/* | sed -e 's/^/-a /')
    echo "${CI_COMMIT_TAG}" | grep -qi '\-rc' && export RELEASETYPE="--prerelease" && echo "Uploading as Pre-Release"
    echo "${CI_COMMIT_TAG}" | grep -qi '\-test' && export RELEASETYPE="--draft" && echo "Uploading as Draft"
    test ${RELEASETYPE+false} || echo "Uploading as Stable"
    ensure_tag
    anchor=$(echo $CI_COMMIT_TAG | sed -e 's/^v//' -e 's/[^a-zA-Z0-9]/-/g')
    $BIN_DIR/tea release create $ASSETS --repo $PUSH_USER/$REPO --note "$RELEASENOTES" --tag $CI_COMMIT_TAG --title $CI_COMMIT_TAG ${RELEASETYPE}
}

push() {
    setup_api
    setup_tea
    GITEA_SERVER_TOKEN=$RELEASETEAMTOKEN $BIN_DIR/tea login add --name $RELEASETEAMUSER --url $FORGEJO
    upload
}

setup_api() {
    if ! which jq curl ; then
	apt-get install -y -qq jq curl
    fi
}

api() {
    method=$1
    shift
    path=$1
    shift

    curl --fail -X $method -sS -H "Content-Type: application/json" -H "Authorization: token $RELEASETEAMTOKEN" "$@" $FORGEJO/api/v1/$path
}

pull() {
    setup_api
    (
	mkdir -p $RELEASE_DIR
	cd $RELEASE_DIR
	api GET repos/$PULL_USER/$REPO/releases/tags/$TAG > /tmp/assets.json
	jq --raw-output '.assets[] | "\(.name) \(.browser_download_url)"' < /tmp/assets.json | while read name url ; do
	    wget --quiet -O $name $url
	done
    )
}


missing() {
    echo need pull or push argument got nothing
    exit 1
}

${@:-missing}
