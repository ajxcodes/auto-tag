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

# ---------------------------------------------------------------------------
# Source: format_version function (inline, identical to engine)
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

echo "── format_version: standard ──"
assert_eq "standard 1.2.3" "1.2.3" "$(format_version 1 2 3 standard)"
assert_eq "standard 0.0.1" "0.0.1" "$(format_version 0 0 1 standard)"
assert_eq "standard 2.0.0" "2.0.0" "$(format_version 2 0 0 standard)"

echo ""
echo "── format_version: zero-padded ──"
assert_eq "zero-padded 1.02.0" "1.02.0" "$(format_version 1 2 0 zero-padded)"
assert_eq "zero-padded 1.00.1" "1.00.1" "$(format_version 1 0 1 zero-padded)"
assert_eq "zero-padded 2.10.3" "2.10.3" "$(format_version 2 10 3 zero-padded)"

# ---------------------------------------------------------------------------
# Source: bump_from_commits function (inline, identical to engine logic)
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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
