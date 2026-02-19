# forgejo-release

<!-- action-docs-description source="action.yml" -->
## Description

Upload or download the assets of a release to a Forgejo instance.
<!-- action-docs-description source="action.yml" -->
<!-- action-docs-inputs source="action.yml" -->
## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `url` | <p>URL of the Forgejo instance</p> | `false` | `${{ env.FORGEJO_SERVER_URL }}` |
| `repo` | <p>owner/project relative to the URL</p> | `false` | `${{ forge.repository }}` |
| `tag` | <p>Tag of the release</p> | `false` | `${{ forge.ref_name }}` |
| `title` | <p>Title of the release (defaults to tag)</p> | `false` | `""` |
| `sha` | <p>SHA of the release</p> | `false` | `${{ forge.sha }}` |
| `token` | <p>Forgejo application token (must have <code>write:repository</code>)</p> | `false` | `${{ forge.token }}` |
| `release-dir` | <p>Directory in which release assets are uploaded or downloaded</p> | `false` | `dist/release` |
| `release-notes` | <p>Release notes</p> | `false` | `""` |
| `release-notes-file` | <p>Path to a file containing your release notes (takes priority over <code>release-notes</code>)</p> | `false` | `""` |
| `direction` | <p>Can either be <code>download</code> or <code>upload</code></p> | `true` | `""` |
| `gpg-private-key` | <p>GPG Private Key to sign the release artifacts</p> | `false` | `""` |
| `gpg-passphrase` | <p>Passphrase of the GPG Private Key</p> | `false` | `""` |
| `download-retry` | <p>Number of times to retry if the release is not ready (default 1)</p> | `false` | `""` |
| `download-latest` | <p>Download the latest release</p> | `false` | `false` |
| `verbose` | <p>Increase the verbosity level</p> | `false` | `false` |
| `override` | <p>Override an existing release by the same <code>{tag}</code></p> | `false` | `false` |
| `prerelease` | <p>Mark Release as Pre-Release</p> | `false` | `false` |
| `release-notes-assistant` | <p>Generate release notes with Release Notes Assistant</p> | `false` | `false` |
| `hide-archive-link` | <p>Hide the archive links</p> | `false` | `false` |
| `skip-assets` | <p>Skip uploading release assets</p> | `false` | `false` |
<!-- action-docs-inputs source="action.yml" -->

## Examples

### Upload

Upload the release located in `release-dir` to the release section of a repository (`url` and `repo`):

```yaml
jobs:
  upload-release:
    runs-on: docker
    steps:
      - uses: actions/checkout@v4
      - uses: actions/forgejo-release@v2.11.0
        with:
          direction: upload
          url: https://my-forgejo-instance.net
          repo: myuser/myrepo
          token: ${{ secrets.WRITE_TOKEN_TO_MYREPO }}
          tag: v1.0.0
          release-dir: dist/release
          release-notes: "MY RELEASE NOTES"
```

Upload a release with custom release notes located in a file:

```yaml
jobs:
  upload-release:
    runs-on: docker
    steps:
      - uses: actions/checkout@v4
      - name: Generate Changelog
        run: ./generate-changelog.sh > dist/changelog.md
      - uses: actions/forgejo-release@v2.11.0
        with:
          direction: upload
          url: https://my-forgejo-instance.net
          repo: myuser/myrepo
          token: ${{ secrets.WRITE_TOKEN_TO_MYREPO }}
          tag: v13.0.2
          release-dir: dist/release
          release-notes-file: dist/changelog.md
```

### Download

Example downloading the forgejo release v1.21.4-0 into the working directory:

```yaml
jobs:
  download-release:
    runs-on: docker
    steps:
      - uses: actions/checkout@v4
      - uses: actions/forgejo-release@v2.11.0
        with:
          direction: download
          url: https://my-forgejo-instance.net
          repo: myuser/myrepo
          token: ${{ secrets.READ_TOKEN_TO_MYREPO }}
          tag: v1.0.0
          release-dir: ./  # by default, files are downloaded into dist/release
```

### Real world example

This action is used to [publish](https://code.forgejo.org/forgejo/release-notes-assistant/src/commit/09f2c22d80d5ee655783cfeb2c1d4bab4afec3e4/.forgejo/workflows/release.yml) the release notes assistant assets.

## Update the `input` section of the README

Using [action-docs](https://github.com/npalm/action-docs):

```shell
# Edit the action.yml file and run:
npx action-docs --update-readme
```
