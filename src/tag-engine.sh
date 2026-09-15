#!/usr/bin/env bash
# tag-engine.sh — Core SemVer tagging engine for ajxcodes/auto-tag action.
# Reads inputs from environment variables set by action.yml.
set -euo pipefail

# ---------------------------------------------------------------------------
# Read inputs from environment
# ---------------------------------------------------------------------------
GITHUB_TOKEN="${INPUT_GITHUB_TOKEN}"
DEFAULT_BUMP="${INPUT_DEFAULT_BUMP:-patch}"
TAG_PREFIX="${INPUT_TAG_PREFIX:-v}"
VERSION_FORMAT="${INPUT_VERSION_FORMAT:-standard}"
CREATE_RELEASE="${INPUT_CREATE_RELEASE:-true}"

# Authenticate gh CLI
export GH_TOKEN="$GITHUB_TOKEN"

# ---------------------------------------------------------------------------
# Get latest tag matching prefix
# ---------------------------------------------------------------------------
LATEST_TAG=$(git describe --tags --abbrev=0 --match "${TAG_PREFIX}*" 2>/dev/null || echo "")

if [ -z "$LATEST_TAG" ]; then
  # No prior tags — start from 0.0.0
  MAJOR=0; MINOR=0; PATCH=0
else
  # Strip prefix and parse semver
  VERSION="${LATEST_TAG#$TAG_PREFIX}"
  # Handle zero-padded: strip leading zeros for arithmetic
  MAJOR=$(echo "$VERSION" | cut -d. -f1 | sed 's/^0*//' | sed 's/^$/0/')
  MINOR=$(echo "$VERSION" | cut -d. -f2 | sed 's/^0*//' | sed 's/^$/0/')
  PATCH=$(echo "$VERSION" | cut -d. -f3 | sed 's/^0*//' | sed 's/^$/0/')
fi

# ---------------------------------------------------------------------------
# Determine bump level from commits
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Also check PR labels via gh CLI (best-effort, won't fail if not in PR context)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Compute new version numbers
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Format version string
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

NEW_VERSION=$(format_version "$MAJOR" "$MINOR" "$PATCH" "$VERSION_FORMAT")
NEW_TAG="${TAG_PREFIX}${NEW_VERSION}"

echo "New tag: $NEW_TAG (bump: $BUMP)"

# ---------------------------------------------------------------------------
# Generate changelog from commits
# ---------------------------------------------------------------------------
if [ -n "$LATEST_TAG" ]; then
  CHANGELOG=$(git log "${LATEST_TAG}..HEAD" --pretty=format:"- %s" 2>/dev/null || echo "- Initial release")
else
  CHANGELOG=$(git log --pretty=format:"- %s" 2>/dev/null || echo "- Initial release")
fi

# ---------------------------------------------------------------------------
# Push tag
# ---------------------------------------------------------------------------
git tag "$NEW_TAG"
git push origin "$NEW_TAG"

# ---------------------------------------------------------------------------
# Create GitHub Release if requested
# ---------------------------------------------------------------------------
RELEASE_URL=""
if [ "$CREATE_RELEASE" = "true" ]; then
  RELEASE_URL=$(gh release create "$NEW_TAG" \
    --title "Release $NEW_TAG" \
    --notes "$CHANGELOG" \
    --json url --jq '.url' 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------
echo "new-tag=${NEW_TAG}" >> "$GITHUB_OUTPUT"
echo "release-url=${RELEASE_URL}" >> "$GITHUB_OUTPUT"
echo "bumped=true" >> "$GITHUB_OUTPUT"

echo "✅ Tagged and released: $NEW_TAG"
