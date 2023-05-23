#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

if ${VERBOSE:-false}; then set -x; fi

: ${FORGEJO:=https://codeberg.org}
: ${REPO:=forgejo-integration/forgejo}
: ${RELEASE_DIR:=dist/release}
: ${BIN_DIR:=$(mktemp -d)}
: ${TEA_VERSION:=0.9.0}
: ${RETRY:=1}
: ${DELAY:=10}

setup_tea() {
    if ! test -f $BIN_DIR/tea ; then
	curl -sL https://dl.gitea.io/tea/$TEA_VERSION/tea-$TEA_VERSION-linux-amd64 > $BIN_DIR/tea
	chmod +x $BIN_DIR/tea
    fi
}

ensure_tag() {
    if api GET repos/$REPO/tags/$TAG > /tmp/tag.json ; then
	local sha=$(jq --raw-output .commit.sha < /tmp/tag.json)
	if test "$sha" != "$SHA" ; then
	    cat /tmp/tag.json
	    echo "the tag SHA in the $REPO repository does not match the tag SHA that triggered the build: $SHA"
	    false
	fi
    else
	api POST repos/$REPO/tags --data-raw '{"tag_name": "'$TAG'", "target": "'$SHA'"}'
    fi
}

upload_release() {
    local assets=$(ls $RELEASE_DIR/* | sed -e 's/^/-a /')
    local releasetype
    echo "${TAG}" | grep -qi '\-rc' && export releasetype="--prerelease" && echo "Uploading as Pre-Release"
    test ${releasetype+false} || echo "Uploading as Stable"
    ensure_tag
    anchor=$(echo $TAG | sed -e 's/^v//' -e 's/[^a-zA-Z0-9]/-/g')
    $BIN_DIR/tea release create $assets --repo $REPO --note "$RELEASENOTES" --tag $TAG --title $TAG --draft ${releasetype}
    release_draft false
}

release_draft() {
    local state="$1"

    local id=$(api GET repos/$REPO/releases/tags/$TAG | jq --raw-output .id)
    api PATCH repos/$REPO/releases/$id --data-raw '{"draft": '$state'}'
}

upload() {
    setup_api
    setup_tea
    GITEA_SERVER_TOKEN=$TOKEN $BIN_DIR/tea login add --url $FORGEJO
    upload_release
}

setup_api() {
    if ! which jq curl ; then
	apt-get -qq update
	apt-get install -y -qq jq curl wget
    fi
}

api() {
    method=$1
    shift
    path=$1
    shift

    curl --fail -X $method -sS -H "Content-Type: application/json" -H "Authorization: token $TOKEN" "$@" $FORGEJO/api/v1/$path
}

wait_release() {
    local ready=false
    for i in $(seq $RETRY); do
	if api GET repos/$REPO/releases/tags/$TAG | jq --raw-output .draft > /tmp/draft; then
	    if test "$(cat /tmp/draft)" = "false"; then
		ready=true
		break
	    fi
	    echo "release $TAG is still a draft"
	else
	    echo "release $TAG does not exist yet"
	fi
	echo "waiting $DELAY seconds"
	sleep $DELAY
    done
    if ! $ready ; then
	echo "no release for $TAG"
	return 1
    fi
}

download() {
    setup_api
    wait_release
    (
	mkdir -p $RELEASE_DIR
	cd $RELEASE_DIR
	api GET repos/$REPO/releases/tags/$TAG > /tmp/assets.json
	jq --raw-output '.assets[] | "\(.name) \(.browser_download_url)"' < /tmp/assets.json | while read name url ; do
	    wget --quiet -O $name $url
	done
    )
}


missing() {
    echo need upload or download argument got nothing
    exit 1
}

${@:-missing}
