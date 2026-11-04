#!/bin/bash
# Offline regression tests for release-note generation in
# scripts/orchestrate-release.sh: a failed GitHub Models request must fall back
# to the release notes template instead of failing the release workflow, while
# the placeholder and checksum gates stay fatal.
#
# Nothing here touches the network or a remote: curl, gh and git are replaced by
# stubs, and any call they do not expect fails the test. Each case sources the
# production script in a throwaway sandbox and runs its functions as ordinary
# commands under `bash -e`, followed by a sentinel that proves the next step ran.
#
# Usage: bash scripts/tests/release-notes-test.sh
# RELEASE_NOTES_SCRIPT=<path> runs the cases against another copy of the script.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT_UNDER_TEST="${RELEASE_NOTES_SCRIPT:-$REPO_ROOT/scripts/orchestrate-release.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SENTINEL="NEXT_STEP_REACHED"
MODELS_URL="https://models.github.ai/inference/chat/completions"
FALLBACK_WARNING="Release notes not generated"
PASSED=0
FAILED=0

# Fixture release inputs. The checksums are fixtures, not release data.
FIXTURE_TAG="v99.1.0"
FIXTURE_VERSION="v99"
FIXTURE_PREVIOUS="v98.0.0"
FIXTURE_HEIGHT="12345000"
FIXTURE_NETWORK="xion-mainnet-1"
SHA_DARWIN_AMD64=$(printf 'a%.0s' {1..64})
SHA_DARWIN_ARM64=$(printf 'b%.0s' {1..64})
SHA_LINUX_AMD64=$(printf 'c%.0s' {1..64})
SHA_LINUX_ARM64=$(printf 'd%.0s' {1..64})

# ---------------------------------------------------------------------------
# Stubs and driver, sourced inside each case's bash -e process.
# ---------------------------------------------------------------------------
cat > "$WORK/stubs.sh" <<'STUBS'
curl() {
  printf 'curl %s\n' "$*" >> "$STUB_LOG"
  local out="" fmt="" url="" data=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) out="$2"; shift 2 ;;
      -w) fmt="$2"; shift 2 ;;
      --data) data="$2"; shift 2 ;;
      -X | -H | --connect-timeout | --max-time) shift 2 ;;
      http*) url="$1"; shift ;;
      *) shift ;;
    esac
  done
  if [ "$url" != "$MODELS_URL" ]; then
    echo "UNEXPECTED_CALL curl $url" >> "$STUB_LOG"
    echo "stub: unexpected curl to $url" >&2
    return 99
  fi
  if [ -z "$data" ] || ! jq empty "${data#@}" 2>/dev/null; then
    echo "BAD_REQUEST" >> "$STUB_LOG"
    echo "stub: request body is not valid JSON" >&2
    return 98
  fi
  if [ "${FIXTURE_CURL_EXIT:-0}" -ne 0 ]; then
    echo "curl: (${FIXTURE_CURL_EXIT}) simulated transport failure" >&2
    if [ -n "$fmt" ]; then printf '000'; fi
    return "$FIXTURE_CURL_EXIT"
  fi
  if [ -n "$out" ]; then cat "$FIXTURE_BODY" > "$out"; else cat "$FIXTURE_BODY"; fi
  if [ -n "$fmt" ]; then printf '%s' "${FIXTURE_HTTP_CODE:-200}"; fi
  return 0
}

gh() {
  echo "UNEXPECTED_CALL gh $*" >> "$STUB_LOG"
  echo "stub: unexpected gh call" >&2
  return 97
}

git() {
  # create_release_files resets the template with `git restore`; nothing else is expected.
  if [ "${1:-}" = "restore" ]; then return 0; fi
  echo "UNEXPECTED_CALL git $*" >> "$STUB_LOG"
  echo "stub: unexpected git call" >&2
  return 97
}

inject_placeholder() {
  echo '{{INJECTED_PLACEHOLDER}}' >> "$RELEASE_NOTES_FILE"
}
STUBS

cat > "$WORK/driver.sh" <<'DRIVER'
set -e
source "$SCRIPT_UNDER_TEST"
source "$STUBS"
for step in "$@"; do
  "$step"
done
echo "$SENTINEL"
DRIVER

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() {
  FAILED=$((FAILED + 1))
  echo "not ok - $1: $2"
  if [ -n "${CASE_OUT:-}" ] && [ -f "$CASE_OUT" ]; then sed 's/^/    | /' "$CASE_OUT"; fi
}

# A sandbox with what generate_claude_notes reads.
new_notes_sandbox() {
  local dir
  dir="$WORK/sandbox-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$dir/.github/workflows/prompts"
  cp "$REPO_ROOT/.github/workflows/prompts/claude-api-prompt.md" "$dir/.github/workflows/prompts/"
  echo '{"total_commits": 3, "files": [], "commits": []}' > "$dir/comparison_data.json"
  echo "$dir"
}

# A sandbox shaped like the repository, for the file generator and validators.
new_repo_sandbox() {
  local dir
  dir=$(new_notes_sandbox "$1")
  mkdir -p "$dir/scripts"
  cp "$REPO_ROOT/scripts/create-release-pr.sh" "$dir/scripts/"
  cp -R "$REPO_ROOT/.github/workflows/templates" "$dir/.github/workflows/"
  cp -R "$REPO_ROOT/proposals" "$REPO_ROOT/releases" "$REPO_ROOT/release_notes" "$dir/"
  echo "$dir"
}

# run_steps <sandbox> <step>...: runs the steps under bash -e with the current
# FIXTURE_* settings. Sets CASE_STATUS, CASE_OUT and STUB_LOG.
run_steps() {
  local dir="$1"
  shift
  CASE_OUT="$dir/.case-output"
  STUB_LOG="$dir/.stub-log"
  : > "$STUB_LOG"
  CASE_STATUS=0
  (
    cd "$dir"
    export SCRIPT_UNDER_TEST STUBS="$WORK/stubs.sh" STUB_LOG SENTINEL MODELS_URL
    export FIXTURE_BODY="${FIXTURE_BODY:-}" FIXTURE_HTTP_CODE="${FIXTURE_HTTP_CODE:-200}" FIXTURE_CURL_EXIT="${FIXTURE_CURL_EXIT:-0}"
    export RELEASE_TAG="$FIXTURE_TAG" VERSION="$FIXTURE_VERSION" PREVIOUS_VERSION="$FIXTURE_PREVIOUS"
    export CALCULATED_HEIGHT="$FIXTURE_HEIGHT" NETWORK_NAME="$FIXTURE_NETWORK" MINTSCAN_CHAIN_ID="$FIXTURE_NETWORK"
    export DEPOSIT="1000000000uxion" EXPEDITED="false"
    export GITHUB_TOKEN="fixture-token-not-a-secret"
    bash "$WORK/driver.sh" "$@"
  ) > "$CASE_OUT" 2>&1 || CASE_STATUS=$?
  # Move bookkeeping out of the sandbox so leftover checks only see script output.
  mv "$CASE_OUT" "$WORK/.last-output"
  mv "$STUB_LOG" "$WORK/.last-stub-log"
  CASE_OUT="$WORK/.last-output"
  STUB_LOG="$WORK/.last-stub-log"
}

body() {
  local file
  file=$(mktemp "$WORK/body.XXXXXX")
  printf '%s' "$1" > "$file"
  echo "$file"
}

leftovers() {
  local dir="$1" f found=""
  for f in generated_release_notes.md copilot_request.json copilot_response.json; do
    if [ -e "$dir/$f" ]; then found="$found $f"; fi
  done
  echo "${found# }"
}

check_stub_log() {
  if grep -qE 'UNEXPECTED_CALL|BAD_REQUEST' "$STUB_LOG"; then
    grep -E 'UNEXPECTED_CALL|BAD_REQUEST' "$STUB_LOG"
    return 1
  fi
  if ! grep -q -- '--connect-timeout 10' "$STUB_LOG" || ! grep -q -- '--max-time 60' "$STUB_LOG"; then
    echo "request was sent without --connect-timeout 10 --max-time 60"
    return 1
  fi
}

# expect_fallback <name>: the notes step failed softly and the next step ran.
expect_fallback() {
  local name="$1" dir left problem
  dir=$(new_notes_sandbox "$name")
  run_steps "$dir" generate_claude_notes
  left=$(leftovers "$dir")
  if [ "$CASE_STATUS" -ne 0 ]; then
    fail "$name" "exit $CASE_STATUS before the next step"
  elif ! grep -q "$SENTINEL" "$CASE_OUT"; then
    fail "$name" "next step not reached"
  elif ! grep -q "$FALLBACK_WARNING" "$CASE_OUT"; then
    fail "$name" "no fallback warning"
  elif [ -n "$left" ]; then
    fail "$name" "left files behind: $left"
  elif ! problem=$(check_stub_log); then
    fail "$name" "$problem"
  else
    pass "$name"
  fi
}

# ---------------------------------------------------------------------------
# Failure responses fall back to the template
# ---------------------------------------------------------------------------
echo "# Script under test: $SCRIPT_UNDER_TEST"

# The body GitHub Models returned in the failed v31 runs: HTTP 200, "OK".
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'OK') expect_fallback "non-JSON HTTP 200 body"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '<!DOCTYPE html><html><body>oops</body></html>') expect_fallback "HTML HTTP 200 body"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '') expect_fallback "empty HTTP 200 body"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices": [') expect_fallback "truncated JSON body"
FIXTURE_HTTP_CODE=401 FIXTURE_BODY=$(body '{"error":{"code":"unauthorized","message":"Bad credentials"}}') expect_fallback "HTTP 401"
FIXTURE_HTTP_CODE=429 FIXTURE_BODY=$(body 'Too many requests') expect_fallback "HTTP 429"
FIXTURE_HTTP_CODE=500 FIXTURE_BODY=$(body '<html>Internal Server Error</html>') expect_fallback "HTTP 500"
FIXTURE_CURL_EXIT=28 FIXTURE_BODY=$(body '') expect_fallback "curl timeout (exit 28)"
FIXTURE_CURL_EXIT=6 FIXTURE_BODY=$(body '') expect_fallback "curl cannot resolve host (exit 6)"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"error":{"message":"Rate limit exceeded"}}') expect_fallback "API error JSON with HTTP 200"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"error":"plain string error"}') expect_fallback "API error as a string"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"error":{"code":"x"}}') expect_fallback "API error without a message"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '[]') expect_fallback "response is a JSON array"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '"just a string"') expect_fallback "response is a JSON string"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'null') expect_fallback "response is JSON null"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":{}}') expect_fallback "choices is an object"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":"text"}') expect_fallback "choices is a string"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[]}') expect_fallback "choices is empty"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":"text"}]}') expect_fallback "message is a string"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":{}}]}') expect_fallback "content missing"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":{"content":null}}]}') expect_fallback "content null"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":{"content":""}}]}') expect_fallback "content empty"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":{"content":"  \n\t \n"}}]}') expect_fallback "content whitespace only"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{"choices":[{"message":{"content":42}}]}') expect_fallback "content is a number"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body '{}') expect_fallback "empty JSON object"

# ---------------------------------------------------------------------------
# Valid notes are kept unchanged
# ---------------------------------------------------------------------------
VALID_NOTES=$'# Xion v99.1.0 Release Notes\n\n## Overview\n\n- First change, with enough text to clear the 50-byte threshold.\n- Second change: `quoted` "double" and $dollar.'
VALID_BODY=$(body "$(jq -n --arg c "$VALID_NOTES" '{choices: [{message: {content: $c}}]}')")

name="valid multiline notes are written unchanged"
dir=$(new_notes_sandbox valid)
FIXTURE_HTTP_CODE=200 FIXTURE_BODY="$VALID_BODY" run_steps "$dir" generate_claude_notes
if [ "$CASE_STATUS" -ne 0 ] || ! grep -q "$SENTINEL" "$CASE_OUT"; then
  fail "$name" "exit $CASE_STATUS"
elif [ ! -f "$dir/generated_release_notes.md" ]; then
  fail "$name" "generated_release_notes.md not written"
elif [ "$(cat "$dir/generated_release_notes.md")" != "$VALID_NOTES" ]; then
  fail "$name" "content changed: $(diff <(printf '%s\n' "$VALID_NOTES") "$dir/generated_release_notes.md" || true)"
elif [ "$(wc -c < "$dir/generated_release_notes.md")" -le 50 ]; then
  fail "$name" "notes not above the consumer's 50-byte threshold"
elif grep -q "$FALLBACK_WARNING" "$CASE_OUT"; then
  fail "$name" "fallback warning on a valid response"
elif [ -e "$dir/copilot_request.json" ] || [ -e "$dir/copilot_response.json" ]; then
  fail "$name" "request/response files left behind"
elif ! problem=$(check_stub_log); then
  fail "$name" "$problem"
else
  pass "$name"
fi

name="a failed request after a successful one does not reuse stale notes"
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'OK') run_steps "$dir" generate_claude_notes
left=$(leftovers "$dir")
if [ "$CASE_STATUS" -ne 0 ] || ! grep -q "$SENTINEL" "$CASE_OUT"; then
  fail "$name" "exit $CASE_STATUS"
elif [ -n "$left" ]; then
  fail "$name" "left files behind: $left"
else
  pass "$name"
fi

# ---------------------------------------------------------------------------
# The fallback renders the template and the validation gates stay fatal
# ---------------------------------------------------------------------------
PIPELINE=(generate_claude_notes create_release_files determine_file_paths substitute_release_notes validate_no_placeholders)
export DARWIN_AMD64_CHECKSUM="$SHA_DARWIN_AMD64" DARWIN_ARM64_CHECKSUM="$SHA_DARWIN_ARM64"
export LINUX_AMD64_CHECKSUM="$SHA_LINUX_AMD64" LINUX_ARM64_CHECKSUM="$SHA_LINUX_ARM64"

name="failed notes request renders the template and passes validation"
dir=$(new_repo_sandbox pipeline)
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'OK') run_steps "$dir" "${PIPELINE[@]}"
proposal=$(cd "$dir" && ls proposals/*-upgrade-"$FIXTURE_VERSION".json 2>/dev/null | head -1 || true)
proposal_number=$(basename "${proposal:-none}" | cut -d- -f1)
notes="$dir/release_notes/$FIXTURE_VERSION.md"
expected="$WORK/expected-notes.md"
sed -e "s|{{NETWORK_NAME}}|$FIXTURE_NETWORK|g" \
  -e "s|{{MINTSCAN_CHAIN_ID}}|$FIXTURE_NETWORK|g" \
  -e "s|{{CALCULATED_HEIGHT}}|$FIXTURE_HEIGHT|g" \
  -e "s|{{CALCULATED_PROPOSAL_NUMBER}}|$proposal_number|g" \
  -e "s|{{PREVIOUS_VERSION}}|$FIXTURE_PREVIOUS|g" \
  -e "s|{{RELEASE_TAG}}|$FIXTURE_TAG|g" \
  -e "s|{{VERSION}}|$FIXTURE_VERSION|g" \
  "$REPO_ROOT/.github/workflows/templates/release_notes_template.md" > "$expected"
if [ "$CASE_STATUS" -ne 0 ] || ! grep -q "$SENTINEL" "$CASE_OUT"; then
  fail "$name" "exit $CASE_STATUS"
elif ! grep -q "$FALLBACK_WARNING" "$CASE_OUT"; then
  fail "$name" "no fallback warning"
elif [ -z "$proposal" ]; then
  fail "$name" "no proposal file generated"
elif [ ! -f "$notes" ]; then
  fail "$name" "release notes not written"
elif ! cmp -s "$expected" "$notes"; then
  fail "$name" "release notes differ from the rendered template: $(diff "$expected" "$notes" | head -20 || true)"
elif ! grep -q "releases/tag/$FIXTURE_TAG" "$notes" || ! grep -q "compare/$FIXTURE_PREVIOUS...$FIXTURE_TAG" "$notes"; then
  fail "$name" "release or compare link missing"
elif grep -qE '\{\{[A-Z_]+\}\}' "$notes"; then
  fail "$name" "unsubstituted variables remain"
elif [ "$(grep -oE 'checksum=sha256:[0-9a-f]{64}' "$dir/releases/$FIXTURE_VERSION.json" | wc -l | tr -d ' ')" -ne 4 ]; then
  fail "$name" "release file lacks the four fixture checksums"
elif ! problem=$(check_stub_log); then
  fail "$name" "$problem"
else
  pass "$name"
fi

name="an injected placeholder still fails validation"
dir=$(new_repo_sandbox placeholder)
FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'OK') run_steps "$dir" generate_claude_notes create_release_files \
  determine_file_paths substitute_release_notes inject_placeholder validate_no_placeholders
if [ "$CASE_STATUS" -eq 0 ] || grep -q "$SENTINEL" "$CASE_OUT"; then
  fail "$name" "validation passed with a placeholder"
elif ! grep -q "still contains placeholders" "$CASE_OUT"; then
  fail "$name" "failed for another reason (exit $CASE_STATUS)"
else
  pass "$name"
fi

name="an invalid checksum still fails validation"
dir=$(new_repo_sandbox checksum)
LINUX_ARM64_CHECKSUM="not-a-sha256" FIXTURE_HTTP_CODE=200 FIXTURE_BODY=$(body 'OK') run_steps "$dir" "${PIPELINE[@]}"
if [ "$CASE_STATUS" -eq 0 ] || grep -q "$SENTINEL" "$CASE_OUT"; then
  fail "$name" "validation passed with an invalid checksum"
elif ! grep -q "valid sha256 checksums, expected 4" "$CASE_OUT"; then
  fail "$name" "failed for another reason (exit $CASE_STATUS)"
else
  pass "$name"
fi

echo ""
echo "# $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
