#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ask-ai-lua-run-test.XXXXXX")"
TEST_AI_DIR="$TMP_DIR/.adds/ai"
TEST_CERT_DIR="$TMP_DIR/.adds/certs"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$TEST_AI_DIR" "$TEST_CERT_DIR" "$TEST_AI_DIR/output" "$TEST_AI_DIR/tmp" "$TEST_AI_DIR/logs"

cp "$ROOT_DIR/.adds/ai/prompt_template.tmpl" "$TEST_AI_DIR/"
cp "$ROOT_DIR/.adds/ai/page_styles.css" "$TEST_AI_DIR/"
cp "$ROOT_DIR/.adds/ai/loading_page.html.tmpl" "$TEST_AI_DIR/"
cp "$ROOT_DIR/.adds/ai/request_page.html.tmpl" "$TEST_AI_DIR/"

cat >"$TEST_AI_DIR/config.env" <<'EOF'
ASK_AI_BACKEND="lua"
DEFAULT_PROVIDER="mock"
DEFAULT_REQUEST_TYPE="explain_selection"
OPENAI_MODEL="gpt-4.1-mini"
PROMPT_TEMPLATE=""
EOF

PROMPT_PATH="$TEST_AI_DIR/prompt_template.tmpl"
CONFIG_PATH="$TEST_AI_DIR/config.env"
TMP_CONFIG="$(mktemp "${TMPDIR:-/tmp}/ask-ai-config.XXXXXX")"
sed "s|PROMPT_TEMPLATE=\"\"|PROMPT_TEMPLATE=\"$PROMPT_PATH\"|" "$CONFIG_PATH" >"$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG_PATH"

LUA_PATH_VALUE="$ROOT_DIR/.adds/ai/lua/?.lua;$ROOT_DIR/.adds/ai/lua/?/init.lua;;"
SELECTION_TEXT="Family labor and social roles."
MOCK_RESPONSE="This is the final rendered answer."

run_lua() {
  ASK_AI_BASE_DIR="$TEST_AI_DIR" \
  ASK_AI_CERT_DIR="$TEST_CERT_DIR" \
  ASK_AI_SQLITE3_BIN="$(command -v sqlite3)" \
  ASK_AI_CURL_BIN="$(command -v curl)" \
  ASK_AI_MOCK_RESPONSE="$MOCK_RESPONSE" \
  LUA_PATH="$LUA_PATH_VALUE" \
  lua "$ROOT_DIR/.adds/ai/lua/main.lua" "$@"
}

FIRST_OUTPUT="$(run_lua run "$SELECTION_TEXT")"
printf '%s\n' "$FIRST_OUTPUT" | grep -q '^request_id=1$'
printf '%s\n' "$FIRST_OUTPUT" | grep -q '^request_state=complete$'
printf '%s\n' "$FIRST_OUTPUT" | grep -q '^cache_hit=0$'

LATEST_FILE="$TEST_AI_DIR/output/latest_ai_answer.html"
[ -f "$LATEST_FILE" ]
grep -q 'Request #1 | complete | Your explanation is ready.' "$LATEST_FILE"
grep -q 'This is the final rendered answer\.' "$LATEST_FILE"
grep -q 'Family labor and social roles\.' "$LATEST_FILE"

SECOND_OUTPUT="$(run_lua run "$SELECTION_TEXT")"
printf '%s\n' "$SECOND_OUTPUT" | grep -q '^request_id=1$'
printf '%s\n' "$SECOND_OUTPUT" | grep -q '^request_state=complete$'
printf '%s\n' "$SECOND_OUTPUT" | grep -q '^cache_hit=1$'

grep -q 'Request #1 | cached | Served from cache.' "$LATEST_FILE"

REQUEST_COUNT="$(sqlite3 "$TEST_AI_DIR/requests.db" "SELECT COUNT(*) FROM requests WHERE state = 'complete';")"
[ "$REQUEST_COUNT" = "1" ]

BODY_HAS_SELECTION="$(sqlite3 "$TEST_AI_DIR/requests.db" "SELECT instr(body, 'Family labor and social roles.') FROM requests WHERE id = 1;")"
[ "$BODY_HAS_SELECTION" != "0" ]

echo "test_lua_run_flow: ok"
