#!/usr/bin/env bash
# tag-engine.sh — Core SemVer tagging engine for ajxcodes/auto-tag action.
# Reads inputs from environment variables set by action.yml.
set -euo pipefail

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
format_version() {
  local major=$1 minor=$2 patch=$3 fmt=$4
  if [ "$fmt" = "standard" ]; then
    echo "${major}.${minor}.${patch}"
  else
    # Zero-padded: pad minor and patch to 2 digits
    printf "%d.%02d.%d" "$major" "$minor" "$patch"
  fi
}

is_valid_semver() {
  local ver="$1"
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

parse_semver() {
  local raw_version="$1"
  local raw_major raw_minor raw_patch
  IFS='.' read -r raw_major raw_minor raw_patch <<< "$raw_version"
  local major minor patch
  major=$(echo "${raw_major:-0}" | sed 's/^0*//' | sed 's/^$/0/')
  minor=$(echo "${raw_minor:-0}" | sed 's/^0*//' | sed 's/^$/0/')
  patch=$(echo "${raw_patch:-0}" | cut -d- -f1 | cut -d+ -f1 | sed 's/^0*//' | sed 's/^$/0/')
  echo "$major $minor $patch"
}

resolve_latest_tag() {
  local tag_prefix="${1:-v}"
  local latest
  # Prefer full SemVer tags (vX.Y.Z) sorted descending by version to ignore floating tags (e.g. v1)
  latest=$(git tag -l "${tag_prefix}[0-9]*.[0-9]*.[0-9]*" --sort=-v:refname 2>/dev/null | head -n 1 || echo "")
  if [ -z "$latest" ]; then
    latest=$(git describe --tags --abbrev=0 --match "${tag_prefix}*" 2>/dev/null || echo "")
  fi
  echo "$latest"
}

version_gt() {
  local v1="$1"
  local v2="$2"

  local v1_major v1_minor v1_patch
  read -r v1_major v1_minor v1_patch <<< "$(parse_semver "$v1")"

  local v2_major v2_minor v2_patch
  read -r v2_major v2_minor v2_patch <<< "$(parse_semver "$v2")"

  if [ "$v1_major" -gt "$v2_major" ]; then
    return 0
  elif [ "$v1_major" -lt "$v2_major" ]; then
    return 1
  fi

  if [ "$v1_minor" -gt "$v2_minor" ]; then
    return 0
  elif [ "$v1_minor" -lt "$v2_minor" ]; then
    return 1
  fi

  if [ "$v1_patch" -gt "$v2_patch" ]; then
    return 0
  fi

  return 1
}

check_package_version() {
  local pkg_input="${1:-true}"
  local current_version="${2:-0.0.0}"

  if [ "$pkg_input" = "false" ]; then
    return 1
  fi

  local pkg_file="package.json"
  if [ "$pkg_input" != "true" ] && [ -n "$pkg_input" ]; then
    pkg_file="$pkg_input"
  fi

  if [ ! -f "$pkg_file" ]; then
    return 1
  fi

  local pkg_version
  pkg_version=$(jq -r '.version // empty' "$pkg_file" 2>/dev/null || true)
  pkg_version="${pkg_version#v}"

  if is_valid_semver "$pkg_version" && version_gt "$pkg_version" "$current_version"; then
    echo "$pkg_version"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Main execution flow
# ---------------------------------------------------------------------------
main() {
  # Read inputs from environment
  GITHUB_TOKEN="${INPUT_GITHUB_TOKEN:-}"
  DEFAULT_BUMP="${INPUT_DEFAULT_BUMP:-patch}"
  TAG_PREFIX="${INPUT_TAG_PREFIX:-v}"
  VERSION_FORMAT="${INPUT_VERSION_FORMAT:-standard}"
  CREATE_RELEASE="${INPUT_CREATE_RELEASE:-true}"
  PACKAGE_JSON="${INPUT_PACKAGE_JSON:-true}"
  GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

  # Authenticate gh CLI if token provided
  if [ -n "$GITHUB_TOKEN" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
  fi

  # -------------------------------------------------------------------------
  # Get latest tag matching prefix
  # -------------------------------------------------------------------------
  LATEST_TAG=$(resolve_latest_tag "$TAG_PREFIX")

  if [ -z "$LATEST_TAG" ]; then
    # No prior tags — start from 0.0.0
    MAJOR=0; MINOR=0; PATCH=0
    CURRENT_VERSION="0.0.0"
  else
    # Strip prefix and parse semver safely
    CURRENT_VERSION="${LATEST_TAG#$TAG_PREFIX}"
    read -r MAJOR MINOR PATCH <<< "$(parse_semver "$CURRENT_VERSION")"
  fi

  # -------------------------------------------------------------------------
  # Check package.json for manual version declarations
  # -------------------------------------------------------------------------
  PKG_TARGET_VERSION=""
  if PKG_TARGET_VERSION=$(check_package_version "$PACKAGE_JSON" "$CURRENT_VERSION"); then
    echo "Detected package version bump in manifest: $PKG_TARGET_VERSION (current tag: ${LATEST_TAG:-none})"
    BUMP="package.json"
    if [ "$VERSION_FORMAT" = "standard" ]; then
      NEW_VERSION="$PKG_TARGET_VERSION"
    else
      read -r PKG_MAJOR PKG_MINOR PKG_PATCH <<< "$(parse_semver "$PKG_TARGET_VERSION")"
      NEW_VERSION=$(format_version "$PKG_MAJOR" "$PKG_MINOR" "$PKG_PATCH" "$VERSION_FORMAT")
    fi
    NEW_TAG="${TAG_PREFIX}${NEW_VERSION}"
  else
    # -----------------------------------------------------------------------
    # Determine bump level from commits
    # -----------------------------------------------------------------------
    BUMP="$DEFAULT_BUMP"
    if [ -n "$LATEST_TAG" ]; then
      COMMITS=$(git log "${LATEST_TAG}..HEAD" --pretty=format:"%s%n%b" 2>/dev/null || git log --pretty=format:"%s%n%b")
    else
      COMMITS=$(git log --pretty=format:"%s%n%b")
    fi

    if echo "$COMMITS" | grep -qE '(feat!:|BREAKING CHANGE:)'; then
      BUMP="major"
    elif echo "$COMMITS" | grep -qE '^feat:'; then
      [ "$BUMP" != "major" ] && BUMP="minor"
    elif echo "$COMMITS" | grep -qE '^fix:'; then
      [ "$BUMP" = "none" ] && BUMP="patch"
    fi

    # -----------------------------------------------------------------------
    # Also check PR labels via gh CLI (best-effort, won't fail if not in PR context)
    # -----------------------------------------------------------------------
    PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")
    if [ -n "$PR_NUMBER" ]; then
      LABELS=$(gh pr view "$PR_NUMBER" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
      if echo "$LABELS" | grep -q 'release:major'; then
        BUMP="major"
      elif echo "$LABELS" | grep -q 'release:minor'; then
        [ "$BUMP" != "major" ] && BUMP="minor"
      elif echo "$LABELS" | grep -q 'release:patch'; then
        [ "$BUMP" = "none" ] && BUMP="patch"
      fi
    fi

    # -----------------------------------------------------------------------
    # Compute new version numbers
    # -----------------------------------------------------------------------
    if [ "$BUMP" = "none" ]; then
      echo "No bump required. Exiting."
      echo "bumped=false" >> "$GITHUB_OUTPUT"
      echo "new-tag=${LATEST_TAG}" >> "$GITHUB_OUTPUT"
      echo "release-url=" >> "$GITHUB_OUTPUT"
      exit 0
    elif [ "$BUMP" = "major" ]; then
      MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0
    elif [ "$BUMP" = "minor" ]; then
      MINOR=$((MINOR + 1)); PATCH=0
    else
      PATCH=$((PATCH + 1))
    fi

    NEW_VERSION=$(format_version "$MAJOR" "$MINOR" "$PATCH" "$VERSION_FORMAT")
    NEW_TAG="${TAG_PREFIX}${NEW_VERSION}"
  fi

  echo "New tag: $NEW_TAG (bump: $BUMP)"

  # -------------------------------------------------------------------------
  # Generate changelog from commits
  # -------------------------------------------------------------------------
  if [ -n "$LATEST_TAG" ]; then
    CHANGELOG=$(git log "${LATEST_TAG}..HEAD" --pretty=format:"- %s" 2>/dev/null || echo "- Initial release")
  else
    CHANGELOG=$(git log --pretty=format:"- %s" 2>/dev/null || echo "- Initial release")
  fi

  # -------------------------------------------------------------------------
  # Push tag
  # -------------------------------------------------------------------------
  if [ -z "$(git config user.name 2>/dev/null || echo '')" ]; then
    git config user.name "github-actions[bot]"
  fi
  if [ -z "$(git config user.email 2>/dev/null || echo '')" ]; then
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  fi

  git tag "$NEW_TAG"
  git push origin "$NEW_TAG"

  # -------------------------------------------------------------------------
  # Create GitHub Release if requested
  # -------------------------------------------------------------------------
  RELEASE_URL=""
  if [ "$CREATE_RELEASE" = "true" ]; then
    RELEASE_URL=$(gh release create "$NEW_TAG" \
      --title "Release $NEW_TAG" \
      --notes "$CHANGELOG" \
      --json url --jq '.url' 2>/dev/null || echo "")
  fi

  # -------------------------------------------------------------------------
  # Write outputs
  # -------------------------------------------------------------------------
  echo "new-tag=${NEW_TAG}" >> "$GITHUB_OUTPUT"
  echo "release-url=${RELEASE_URL}" >> "$GITHUB_OUTPUT"
  echo "bumped=true" >> "$GITHUB_OUTPUT"

  echo "✅ Tagged and released: $NEW_TAG"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
