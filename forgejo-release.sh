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
: ${BIN_DIR:=$TMP_DIR}
: ${TEA_VERSION:=0.9.0}
: ${OVERRIDE:=false}
: ${HIDE_ARCHIVE_LINK:=false}
: ${RETRY:=1}
: ${DELAY:=10}

export GNUPGHOME

setup_tea() {
    if ! test -f "$BIN_DIR"/tea ; then
    ARCH=$(dpkg --print-architecture)
    curl -sL https://dl.gitea.io/tea/$TEA_VERSION/tea-$TEA_VERSION-linux-"$ARCH" > "$BIN_DIR"/tea
    chmod +x "$BIN_DIR"/tea
    fi
}

ensure_tag() {
    if api GET repos/$REPO/tags/"$TAG" > "$TMP_DIR"/tag.json ; then
    local sha=$(jq --raw-output .commit.sha < "$TMP_DIR"/tag.json)
    if test "$sha" != "$SHA" ; then
        cat "$TMP_DIR"/tag.json
        echo "the tag SHA in the $REPO repository does not match the tag SHA that triggered the build: $SHA"
        false
    fi
    else
    api POST repos/$REPO/tags --data-raw '{"tag_name": "'"$TAG"'", "target": "'"$SHA"'"}'
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
    if $PRERELEASE || echo "${TAG}" | grep -qi '\-rc' ; then
        releaseType="--prerelease"
        echo "Uploading as Pre-Release"
    else
        echo "Uploading as Stable"
    fi
    ensure_tag
    if ! "$BIN_DIR"/tea release create "${assets[@]}" --repo $REPO --note "$RELEASENOTES" --tag "$TAG" --title "$TITLE" --draft ${releaseType} >& "$TMP_DIR"/tea.log ; then
        if grep --quiet 'Unknown API Error: 500' "$TMP_DIR"/tea.log && grep --quiet services/release/release.go:194 "$TMP_DIR"/tea.log ; then
            echo "workaround v1.20 race condition https://codeberg.org/forgejo/forgejo/issues/1370"
            sleep 10
            "$BIN_DIR"/tea release create "${assets[@]}" --repo $REPO --note "$RELEASENOTES" --tag "$TAG" --title "$TITLE" --draft ${releaseType}
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

    local id=$(api GET repos/$REPO/releases/tags/"$TAG" | jq --raw-output .id)

    api PATCH repos/$REPO/releases/"$id" --data-raw '{"draft": '"$state"', "hide_archive_links": '$HIDE_ARCHIVE_LINK'}'
}

maybe_use_release_note_assistant() {
    if "$RELEASE_NOTES_ASSISTANT"; then
        curl --fail -s -S -o rna https://code.forgejo.org/forgejo/release-notes-assistant/releases/download/v1.2.3/release-notes-assistant
        chmod +x ./rna
        ./rna --storage release --storage-location "$TAG" --forgejo-url "$SCHEME"://placeholder:"$TOKEN"@"$HOST" --repository $REPO --token "$TOKEN" release "$TAG"
    fi
}

sign_release() {
    local passphrase
    if test -s "$GPG_PASSPHRASE"; then
    passphrase="--passphrase-file $GPG_PASSPHRASE"
    fi
    gpg --import --no-tty --pinentry-mode loopback $passphrase "$GPG_PRIVATE_KEY"
    for asset in "$RELEASE_DIR"/* ; do
    if [[ $asset =~ .sha256$ ]] ; then
        continue
    fi
    gpg --armor --detach-sign --no-tty --pinentry-mode loopback $passphrase < "$asset" > "$asset".asc
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
    api DELETE repos/$REPO/releases/tags/"$TAG" >& /dev/null || true
    api DELETE repos/$REPO/tags/"$TAG" >& /dev/null || true
}

upload() {
    setup_api
    setup_tea
    rm -f ~/.config/tea/config.yml
    GITEA_SERVER_TOKEN=$TOKEN "$BIN_DIR"/tea login add --url $FORGEJO
    maybe_sign_release
    maybe_override
    upload_release
}

setup_api() {
    if ! which jq curl ; then
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
    if api GET repos/$REPO/releases/tags/"$TAG" | jq --raw-output .draft > "$TMP_DIR"/draft; then
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
    if ! $ready ; then
    echo "no release for $TAG"
    return 1
    fi
}

download() {
    setup_api
    (
    mkdir -p $RELEASE_DIR
    cd $RELEASE_DIR
    if [[ ${DOWNLOAD_LATEST} == "true" ]] ; then
        echo "Downloading the latest release"
        api GET repos/$REPO/releases/latest > "$TMP_DIR"/assets.json
    elif [[ ${DOWNLOAD_LATEST} == "false" ]] ; then
        wait_release
        echo "Downloading tagged release ${TAG}"
        api GET repos/$REPO/releases/tags/"$TAG" > "$TMP_DIR"/assets.json
    fi
     jq --raw-output '.assets[] | "\(.browser_download_url) \(.name)"' < "$TMP_DIR"/assets.json | while read url name  ; do  # `name` may contain whitespace, therefore, it must be last
       curl --fail -H "Authorization: token $TOKEN" -o "$name" -L "$url"
     done
    )
}

missing() {
    echo need upload or download argument got nothing
    exit 1
}

${@:-missing}
