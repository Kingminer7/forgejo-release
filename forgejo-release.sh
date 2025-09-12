#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

if ${VERBOSE:-false}; then set -x; fi

: ${FORGEJO:=https://codeberg.org}
: ${REPO:=forgejo-integration/forgejo}
: ${TITLE:=$TAG}
: ${RELEASE_DIR:=dist/release}
: ${DOWNLOAD_LATEST:=false}
: ${TMP_DIR:=$(mktemp -d)}
: ${GNUPGHOME:=$TMP_DIR}
: ${TEA_BIN:=$TMP_DIR/tea}
: ${TEA_VERSION:=0.10.1}
: ${OVERRIDE:=false}
: ${HIDE_ARCHIVE_LINK:=false}
: ${RETRY:=1}
: ${DELAY:=10}

RELEASE_NOTES_ASSISTANT_VERSION=v1.4.1 # renovate: datasource=forgejo-releases depName=forgejo/release-notes-assistant registryUrl=https://code.forgejo.org

TAG_FILE="$TMP_DIR/tag$$.json"
TAG_URL=$(echo "$TAG" | sed 's/\//%2F/g')

export GNUPGHOME

setup_tea() {
    if which tea 2>/dev/null; then
        TEA_BIN=$(which tea)
    elif ! test -f $TEA_BIN; then
        ARCH=$(dpkg --print-architecture)
        curl -sL https://dl.gitea.io/tea/$TEA_VERSION/tea-$TEA_VERSION-linux-"$ARCH" >$TEA_BIN
        chmod +x $TEA_BIN
    fi
}

get_tag() {
    if ! test -f "$TAG_FILE"; then
        if api GET repos/$REPO/tags/"$TAG_URL" >"$TAG_FILE"; then
            echo "tag $TAG exists"
        else
            echo "tag $TAG does not exists"
        fi
    fi
    test -s "$TAG_FILE"
}

matched_tag() {
    if get_tag; then
        local sha=$(jq --raw-output .commit.sha <"$TAG_FILE")
        test "$sha" = "$SHA"
    else
        return 1
    fi
}

ensure_tag() {
    if get_tag; then
        if ! matched_tag; then
            cat "$TAG_FILE"
            echo "the tag SHA in the $REPO repository does not match the tag SHA that triggered the build: $SHA"
            return 1
        fi
    else
        create_tag
    fi
}

create_tag() {
    api POST repos/$REPO/tags --data-raw '{"tag_name": "'"$TAG"'", "target": "'"$SHA"'"}' >"$TAG_FILE"
}

delete_tag() {
    if get_tag; then
        api DELETE repos/$REPO/tags/"$TAG_URL"
        rm -f "$TAG_FILE"
    fi
}

upload_release() {
    # assets is defined as a list of arguments, where values may contain whitespace and need to be quoted like this -a "my file.txt" -a "file.txt".
    # It is expanded using "${assets[@]}" which preserves the separation of arguments and not split whitespace containing values.
    # For reference, see https://github.com/koalaman/shellcheck/wiki/SC2086#exceptions
    local assets=()
    for file in "$RELEASE_DIR"/*; do
        assets=("${assets[@]}" -a "$file")
    done
    if $PRERELEASE || echo "${TAG}" | grep -qi '\-rc'; then
        releaseType="--prerelease"
        echo "Uploading as Pre-Release"
    else
        echo "Uploading as Stable"
    fi
    ensure_tag
    if ! $TEA_BIN release create "${assets[@]}" --repo $REPO --note "$RELEASENOTES" --tag "$TAG" --title "$TITLE" --draft ${releaseType} >&"$TMP_DIR"/tea.log; then
        if grep --quiet 'Unknown API Error: 500' "$TMP_DIR"/tea.log && grep --quiet services/release/release.go:194 "$TMP_DIR"/tea.log; then
            echo "workaround v1.20 race condition https://codeberg.org/forgejo/forgejo/issues/1370"
            sleep 10
            $TEA_BIN release create "${assets[@]}" --repo $REPO --note "$RELEASENOTES" --tag "$TAG" --title "$TITLE" --draft ${releaseType}
        else
            cat "$TMP_DIR"/tea.log
            return 1
        fi
    fi
    maybe_use_release_note_assistant
    release_draft false
}

release_draft() {
    local state="$1"

    local id=$(api GET repos/$REPO/releases/tags/"$TAG_URL" | jq --raw-output .id)

    api PATCH repos/$REPO/releases/"$id" --data-raw '{"draft": '"$state"', "hide_archive_links": '$HIDE_ARCHIVE_LINK'}'
}

maybe_use_release_note_assistant() {
    if "$RELEASE_NOTES_ASSISTANT"; then
        curl --fail -s -S -o rna https://code.forgejo.org/forgejo/release-notes-assistant/releases/download/$RELEASE_NOTES_ASSISTANT_VERSION/release-notes-assistant
        chmod +x ./rna
        mkdir -p $RELEASE_NOTES_ASSISTANT_WORKDIR
        ./rna --workdir=$RELEASE_NOTES_ASSISTANT_WORKDIR --storage release --storage-location "$TAG" --token "$TOKEN" --forgejo-url "$SCHEME://$HOST" --repository $REPO --token "$TOKEN" release "$TAG"
    fi
}

sign_release() {
    local passphrase
    if test -s "$GPG_PASSPHRASE"; then
        passphrase="--passphrase-file $GPG_PASSPHRASE"
    fi
    gpg --import --no-tty --pinentry-mode loopback $passphrase "$GPG_PRIVATE_KEY"
    for asset in "$RELEASE_DIR"/*; do
        if [[ $asset =~ .sha256$ ]]; then
            continue
        fi
        gpg --armor --detach-sign --no-tty --pinentry-mode loopback $passphrase <"$asset" >"$asset".asc
    done
}

maybe_sign_release() {
    if test -s "$GPG_PRIVATE_KEY"; then
        sign_release
    fi
}

maybe_override() {
    if test "$OVERRIDE" = "false"; then
        return
    fi
    api DELETE repos/$REPO/releases/tags/"$TAG_URL" >&/dev/null || true
    if get_tag && ! matched_tag; then
        delete_tag
    fi
}

upload() {
    setup_api
    setup_tea
    rm -f ~/.config/tea/config.yml
    GITEA_SERVER_TOKEN=$TOKEN $TEA_BIN login add --url $FORGEJO
    maybe_sign_release
    maybe_override
    upload_release
}

setup_api() {
    if ! which jq curl; then
        apt-get -qq update
        apt-get install -y -qq jq curl
    fi
}

api() {
    method=$1
    shift
    path=$1
    shift

    curl --fail -X "$method" -sS -H "Content-Type: application/json" -H "Authorization: token $TOKEN" "$@" $FORGEJO/api/v1/"$path"
}

wait_release() {
    local ready=false
    for i in $(seq $RETRY); do
        if api GET repos/$REPO/releases/tags/"$TAG_URL" | jq --raw-output .draft >"$TMP_DIR"/draft; then
            if test "$(cat "$TMP_DIR"/draft)" = "false"; then
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
    if ! $ready; then
        echo "no release for $TAG"
        return 1
    fi
}

download() {
    setup_api
    (
        mkdir -p $RELEASE_DIR
        cd $RELEASE_DIR
        if [[ ${DOWNLOAD_LATEST} == "true" ]]; then
            echo "Downloading the latest release"
            api GET repos/$REPO/releases/latest >"$TMP_DIR"/assets.json
        elif [[ ${DOWNLOAD_LATEST} == "false" ]]; then
            wait_release
            echo "Downloading tagged release ${TAG}"
            api GET repos/$REPO/releases/tags/"$TAG_URL" >"$TMP_DIR"/assets.json
        fi
        jq --raw-output '.assets[] | "\(.browser_download_url) \(.name)"' <"$TMP_DIR"/assets.json | while read url name; do # `name` may contain whitespace, therefore, it must be last
            url=$(echo "$url" | sed "s#/download/${TAG}/#/download/${TAG_URL}/#")
            curl --fail -H "Authorization: token $TOKEN" -o "$name" -L "$url"
        done
    )
}

missing() {
    echo need upload or download argument got nothing
    exit 1
}

${@:-missing}
