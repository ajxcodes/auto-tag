# ajxcodes/auto-tag

A GitHub composite action that automatically computes and applies SemVer tags based on [Conventional Commits](https://www.conventionalcommits.org/) and PR labels, then optionally creates a GitHub Release.

---

## Usage

```yaml
- uses: ajxcodes/auto-tag@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    default-bump: patch          # major | minor | patch | none
    tag-prefix: v                # default: "v"
    version-format: standard     # standard (X.Y.Z) | any other value = zero-padded minor (X.0Y.Z)
    create-release: "true"       # "true" | "false"
```

---

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `github-token` | ✅ | — | GitHub token for authentication and `gh` CLI access |
| `default-bump` | ❌ | `patch` | Bump level used when no conventional commit signal is detected |
| `tag-prefix` | ❌ | `v` | Prefix prepended to the version number |
| `version-format` | ❌ | `standard` | `standard` → `X.Y.Z`; anything else → zero-padded minor (`X.0Y.Z`) |
| `create-release` | ❌ | `true` | Whether to create a GitHub Release after tagging |

---

## Outputs

| Output | Description |
|---|---|
| `new-tag` | The newly created tag (e.g. `v1.3.0`), or the latest existing tag if no bump was needed |
| `release-url` | URL of the GitHub Release, or empty string if none was created |
| `bumped` | `"true"` if a new tag was created, `"false"` otherwise |

---

## Bump Logic

Bump level is determined in priority order:

1. **PR labels** (highest priority, evaluated via `gh` CLI):
   - `release:major` → major
   - `release:minor` → minor
   - `release:patch` → patch
2. **Conventional Commit prefixes** in commit messages since the last tag:
   - `feat!:` or `BREAKING CHANGE:` → major
   - `feat:` → minor
   - `fix:` → patch
3. **`default-bump`** input as fallback (use `none` to skip tagging if no signal is found)

---

## Local Testing

You can run the CI workflow locally using [`act`](https://github.com/nektos/act).

### Install act

```bash
# Via the official install script
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Run the unit test job locally

#### Docker (standard)

```bash
act push --job test -s GITHUB_TOKEN=your_token
```

#### Podman (rootless)

This machine uses Podman instead of Docker. Start the Podman socket first, then point `act` at it:

```bash
# Start the rootless Podman socket (one-time per session)
systemctl --user start podman.socket

# Run act using the Podman socket
DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock act push --job test -s GITHUB_TOKEN=your_token
```

> **Tip:** Add `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` to your shell profile so `act` always finds Podman automatically.

### Run only the bash unit tests (no container required)

```bash
bash tests/test-tag-engine.sh
```

---

## Development

```
.
├── action.yml                    # Composite action manifest
├── src/
│   └── tag-engine.sh             # Core SemVer tagging engine
├── tests/
│   └── test-tag-engine.sh        # Bash unit test suite
└── .github/
    └── workflows/
        └── test.yml              # CI: lint + unit tests
```
