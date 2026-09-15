#!/usr/bin/env bash
# test-tag-engine.sh — Bash unit tests for auto-tag engine logic.
# Tests run without git or gh CLI dependencies (pure-function coverage only).
set -euo pipefail

PASS=0; FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "✅ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "❌ FAIL: $desc (expected=$expected, actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

# Source core functions from tag-engine.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../src/tag-engine.sh"

echo "── format_version: standard ──"
assert_eq "standard 1.2.3" "1.2.3" "$(format_version 1 2 3 standard)"
assert_eq "standard 0.0.1" "0.0.1" "$(format_version 0 0 1 standard)"
assert_eq "standard 2.0.0" "2.0.0" "$(format_version 2 0 0 standard)"

echo ""
echo "── format_version: zero-padded ──"
assert_eq "zero-padded 1.02.0" "1.02.0" "$(format_version 1 2 0 zero-padded)"
assert_eq "zero-padded 1.00.1" "1.00.1" "$(format_version 1 0 1 zero-padded)"
assert_eq "zero-padded 2.10.3" "2.10.3" "$(format_version 2 10 3 zero-padded)"

echo ""
echo "── is_valid_semver ──"
assert_eq "valid 1.0.0" "0" "$(is_valid_semver '1.0.0' && echo 0 || echo 1)"
assert_eq "valid 0.1.0" "0" "$(is_valid_semver '0.1.0' && echo 0 || echo 1)"
assert_eq "valid 2.1.3-beta.1" "0" "$(is_valid_semver '2.1.3-beta.1' && echo 0 || echo 1)"
assert_eq "invalid empty" "1" "$(is_valid_semver '' && echo 0 || echo 1)"
assert_eq "invalid non-semver" "1" "$(is_valid_semver 'abc' && echo 0 || echo 1)"
assert_eq "invalid incomplete" "1" "$(is_valid_semver '1.2' && echo 0 || echo 1)"

echo ""
echo "── version_gt ──"
assert_eq "1.0.1 > 1.0.0" "0" "$(version_gt '1.0.1' '1.0.0' && echo 0 || echo 1)"
assert_eq "1.1.0 > 1.0.9" "0" "$(version_gt '1.1.0' '1.0.9' && echo 0 || echo 1)"
assert_eq "2.0.0 > 1.9.9" "0" "$(version_gt '2.0.0' '1.9.9' && echo 0 || echo 1)"
assert_eq "1.0.0 > 1.0.0 (equal)" "1" "$(version_gt '1.0.0' '1.0.0' && echo 0 || echo 1)"
assert_eq "0.9.0 > 1.0.0 (less)" "1" "$(version_gt '0.9.0' '1.0.0' && echo 0 || echo 1)"
assert_eq "1.2.3 > 1.02.0 (zero-padded comparison)" "0" "$(version_gt '1.2.3' '1.02.0' && echo 0 || echo 1)"
assert_eq "1.0.0 > 0.0.0 (no prior tags)" "0" "$(version_gt '1.0.0' '0.0.0' && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# bump_from_commits helper (used for conventional commit signal verification)
# ---------------------------------------------------------------------------
bump_from_commits() {
  local commits="$1" default_bump="${2:-patch}"
  local bump="$default_bump"
  if echo "$commits" | grep -qE '(feat!:|BREAKING CHANGE:)'; then
    bump="major"
  elif echo "$commits" | grep -qE '^feat:'; then
    [ "$bump" != "major" ] && bump="minor"
  elif echo "$commits" | grep -qE '^fix:'; then
    [ "$bump" = "none" ] && bump="patch"
  fi
  echo "$bump"
}

echo ""
echo "── bump_from_commits: conventional commit signals ──"
assert_eq "feat! -> major"           "major" "$(bump_from_commits 'feat!: break everything')"
assert_eq "BREAKING CHANGE -> major" "major" "$(bump_from_commits $'feat: add thing\nBREAKING CHANGE: removed API')"
assert_eq "feat: -> minor"           "minor" "$(bump_from_commits 'feat: add new feature')"
assert_eq "fix: -> patch"            "patch" "$(bump_from_commits 'fix: correct bug')"

echo ""
echo "── bump_from_commits: default-bump interaction ──"
assert_eq "chore: with default=patch" "patch" "$(bump_from_commits 'chore: cleanup' patch)"
assert_eq "chore: with default=none"  "none"  "$(bump_from_commits 'chore: cleanup' none)"
assert_eq "fix: with default=none"    "patch" "$(bump_from_commits 'fix: correct bug' none)"

echo ""
echo "── No prior tags: initial version arithmetic ──"
# Simulate no-prior-tag path: MAJOR=0, MINOR=0, PATCH=0 + patch bump = 0.0.1
MAJOR=0; MINOR=0; PATCH=0
PATCH=$((PATCH + 1))
assert_eq "initial patch bump 0.0.1" "0.0.1" "$(format_version $MAJOR $MINOR $PATCH standard)"

# Simulate no-prior-tag path: MAJOR=0, MINOR=0, PATCH=0 + minor bump = 0.1.0
MAJOR=0; MINOR=0; PATCH=0
MINOR=$((MINOR + 1)); PATCH=0
assert_eq "initial minor bump 0.1.0" "0.1.0" "$(format_version $MAJOR $MINOR $PATCH standard)"

echo ""
echo "── default-bump=none, no conventional commits → no bump ──"
BUMP=$(bump_from_commits 'chore: update README' none)
assert_eq "none bump stays none" "none" "$BUMP"

echo ""
echo "── check_package_version: package.json detection ──"
TMP_TEST_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_TEST_DIR"
}
trap cleanup EXIT

# Test 1: package.json version > latest tag -> returns package.json version
echo '{"name": "test-pkg", "version": "1.5.0"}' > "$TMP_TEST_DIR/package.json"
PKG_VER_RES=$(check_package_version "$TMP_TEST_DIR/package.json" "1.4.0" || echo "")
assert_eq "package.json > latest tag: returns package.json version" "1.5.0" "$PKG_VER_RES"

# Test 2: package.json version with leading 'v' > latest tag
echo '{"name": "test-pkg", "version": "v2.0.0"}' > "$TMP_TEST_DIR/package.json"
PKG_VER_RES=$(check_package_version "$TMP_TEST_DIR/package.json" "1.9.0" || echo "")
assert_eq "package.json with v-prefix stripped" "2.0.0" "$PKG_VER_RES"

# Test 3: package.json version == latest tag -> falls back (returns 1)
echo '{"name": "test-pkg", "version": "1.4.0"}' > "$TMP_TEST_DIR/package.json"
PKG_VER_STATUS=$(check_package_version "$TMP_TEST_DIR/package.json" "1.4.0" >/dev/null && echo "0" || echo "1")
assert_eq "package.json == latest tag: falls back" "1" "$PKG_VER_STATUS"

# Test 4: package.json version < latest tag -> falls back (returns 1)
echo '{"name": "test-pkg", "version": "1.3.0"}' > "$TMP_TEST_DIR/package.json"
PKG_VER_STATUS=$(check_package_version "$TMP_TEST_DIR/package.json" "1.4.0" >/dev/null && echo "0" || echo "1")
assert_eq "package.json < latest tag: falls back" "1" "$PKG_VER_STATUS"

# Test 5: package-json: false -> ignores package.json even if version > latest tag
PKG_VER_STATUS=$(check_package_version "false" "1.0.0" >/dev/null && echo "0" || echo "1")
assert_eq "package-json: false ignores manifest" "1" "$PKG_VER_STATUS"

# Test 6: Custom manifest path string
mkdir -p "$TMP_TEST_DIR/sub"
echo '{"name": "sub-pkg", "version": "3.1.0"}' > "$TMP_TEST_DIR/sub/custom.json"
PKG_VER_RES=$(check_package_version "$TMP_TEST_DIR/sub/custom.json" "3.0.0" || echo "")
assert_eq "custom package manifest path detected" "3.1.0" "$PKG_VER_RES"

# Test 7: Invalid semver in package.json -> falls back (returns 1)
echo '{"name": "test-pkg", "version": "invalid-version"}' > "$TMP_TEST_DIR/package.json"
PKG_VER_STATUS=$(check_package_version "$TMP_TEST_DIR/package.json" "1.0.0" >/dev/null && echo "0" || echo "1")
assert_eq "invalid semver in package.json falls back" "1" "$PKG_VER_STATUS"

# Test 8: Missing file -> falls back (returns 1)
PKG_VER_STATUS=$(check_package_version "$TMP_TEST_DIR/nonexistent.json" "1.0.0" >/dev/null && echo "0" || echo "1")
assert_eq "missing manifest file falls back" "1" "$PKG_VER_STATUS"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
