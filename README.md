# auto-tag

Automated SemVer tagging and GitHub Release generation based on Conventional Commits and PR labels.

## Overview

`auto-tag` is a GitHub Action designed to automatically compute and push SemVer tags and generate GitHub Releases when commits are pushed or merged to `main`. It natively aligns with Conventional Commits specifications and supports configurable tag formats (including custom zero-padded patterns like `v1.02.0`).

## Usage

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  tag:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Auto Tag Release
        uses: ajxcodes/auto-tag@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          default-bump: patch
          create-release: true
```

## Inputs

| Input | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `github-token` | GitHub token for creating tags and releases | **Yes** | N/A |
| `default-bump` | Default version bump if no conventional commit type matches (`patch`, `minor`, `none`) | No | `patch` |
| `tag-prefix` | Prefix to prepend to tag | No | `v` |
| `version-format` | Format pattern for version string (e.g., standard SemVer or zero-padded) | No | `standard` |
| `create-release` | Whether to automatically create a GitHub Release with generated release notes | No | `true` |

## License

[MIT](LICENSE) © Alvin Jorrel Pascual
