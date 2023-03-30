# forgejo-release

<!-- action-docs-description -->
## Description

Upload or download the assets of a release to a Forgejo instance.
<!-- action-docs-description -->
<!-- action-docs-inputs -->
## Inputs

| parameter | description | required | default |
| --- | --- | --- | --- |
| url | URL of the Forgejo instance | `false` |  |
| repo | owner/project relative to the URL | `false` |  |
| tag | Tag of the release | `false` |  |
| sha | SHA of the release | `false` |  |
| doer | Forgejo user authoring the upload | `false` |  |
| token | Forgejo application token | `true` |  |
| release-dir | Directory in whichs release assets are uploaded or downloaded | `true` |  |
| release-notes | Release notes | `false` |  |
| direction | Can either be download or upload | `true` |  |
| verbose | Increase the verbosity level | `false` | false |
<!-- action-docs-inputs -->

## Example

```
on: [tag]
jobs:
  upload-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/forgejo-release@v1
        with:
	  direction: upload
	  url: https://code.forgejo.org
          release-dir: dist/release
          release-notes: "MY RELEASE NOTES"
```
