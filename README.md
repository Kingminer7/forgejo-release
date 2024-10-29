# forgejo-release

<!-- action-docs-description source="action.yml" -->
## Description

Upload or download the assets of a release to a Forgejo instance.
<!-- action-docs-description source="action.yml" -->
<!-- action-docs-inputs source="action.yml" -->
## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `url` | <p>URL of the Forgejo instance</p> | `false` | `""` |
| `repo` | <p>owner/project relative to the URL</p> | `false` | `""` |
| `tag` | <p>Tag of the release</p> | `false` | `""` |
| `title` | <p>Title of the release</p> | `false` | `""` |
| `sha` | <p>SHA of the release</p> | `false` | `""` |
| `token` | <p>Forgejo application token</p> | `true` | `""` |
| `release-dir` | <p>Directory in whichs release assets are uploaded or downloaded</p> | `true` | `""` |
| `release-notes` | <p>Release notes</p> | `false` | `""` |
| `direction` | <p>Can either be download or upload</p> | `true` | `""` |
| `gpg-private-key` | <p>GPG Private Key to sign the release artifacts</p> | `false` | `""` |
| `gpg-passphrase` | <p>Passphrase of the GPG Private Key</p> | `false` | `""` |
| `download-retry` | <p>Number of times to retry if the release is not ready (default 1)</p> | `false` | `""` |
| `download-latest` | <p>Download the latest release</p> | `false` | `false` |
| `verbose` | <p>Increase the verbosity level</p> | `false` | `false` |
| `override` | <p>Override an existing release by the same {tag}</p> | `false` | `false` |
| `prerelease` | <p>Mark Release as Pre-Release</p> | `false` | `false` |
<!-- action-docs-inputs source="action.yml" -->

## Examples

### Upload

Upload the release located in `release-dir` to the release section of a repository (`url` and `repo`):

```yaml
on: [tag]
jobs:
  upload-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/forgejo-release@v2
        with:
          direction: upload
          url: https://code.forgejo.org
          release-dir: dist/release
          release-notes: "MY RELEASE NOTES"
```

### Download

Example downloading the forgejo release v1.21.4-0 into the working directory:

```yaml
on: [tag]
jobs:
  download-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/forgejo-release@v2
        with:
          direction: download
          url: https://code.forgejo.org
          repo: forgejo/forgejo
          tag: v1.21.4-0
          release-dir: ./  # by default, files are downloaded into dist/release
```

### Real world example

This action is used to [publish](https://code.forgejo.org/forgejo/release-notes-assistant/src/branch/main/.forgejo/workflows/release.yml) the release notes assistant assets.

## Update the `input` section of the README

Using [action-docs](https://github.com/npalm/action-docs):

```shell
# Edit the action.yml file and run:
action-docs --update-readme
```
