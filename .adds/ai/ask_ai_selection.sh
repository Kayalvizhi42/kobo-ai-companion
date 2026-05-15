#!/bin/sh

# Ask OpenAI about the currently selected text in the Kobo reader.
# Reads config from: /mnt/onboard/.adds/ai/config.env
#
# Required config.env:
# OPENAI_API_KEY='sk-your-key-here'
# OPENAI_MODEL='gpt-4.1-mini'

CONFIG="/mnt/onboard/.adds/ai/config.env"
DEFAULT_PROMPT_TEMPLATE="/mnt/onboard/.adds/ai/prompt_template.txt"

OUT_DIR="/mnt/onboard/ai_answers"
WORK_DIR="/mnt/onboard/.adds/ai/tmp"
LOG_DIR="/mnt/onboard/.adds/ai/logs"

LOG="$LOG_DIR/ai_activity_log.txt"
PROMPT_FILE="$WORK_DIR/selection_prompt.txt"
JSON_FILE="$WORK_DIR/request.json"
RAW_FILE="$WORK_DIR/raw_response.json"
RESPONSE_TEXT_FILE="$WORK_DIR/response_text.txt"
STATUS_FILE="$WORK_DIR/current_status.txt"
ESCAPE_HTML_PY="$WORK_DIR/escape_html.py"
HTTP_CODE_FILE="$WORK_DIR/http_code.txt"
CURL_ERR_FILE="$WORK_DIR/curl_stderr.txt"
CURL_BIN=""
ANSWER_FILE="$OUT_DIR/latest_ai_answer.html"
SELECTION_TEXT="$1"
PROMPT_TEMPLATE_PATH="$2"
BUNDLED_BIN_DIR="/mnt/onboard/.adds/bin"
BUNDLED_CERT_DIR="/mnt/onboard/.adds/certs"
CACERT_FILE="$BUNDLED_CERT_DIR/cacert.pem"

mkdir -p "$OUT_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$BUNDLED_CERT_DIR"
mkdir -p "$LOG_DIR"

log_msg() {
  printf '%s\n' "$1" >>"$LOG"
  printf '%s\n' "$1"
}

log_err() {
  printf 'ERROR: %s\n' "$1" >>"$LOG"
  printf 'ERROR: %s\n' "$1"
}

extract_response_text_sh() {
  raw="$(tr -d '\r\n' <"$RAW_FILE" | sed 's/\\"/__ESCQUOTE__/g')"
  after="${raw#*\"content\":}"
  after="${after#*\"text\": \"}"
  text="${after%%\"*\"role\"*}"
  text="$(printf '%s' "$text" | sed 's/__ESCQUOTE__/\\"/g')"

  if [ -z "$text" ]; then
    return 1
  fi

  printf '%s' "$text" | \
    sed 's/\\"/"/g; s/\\\\/\\/g; s/\\n/\
/g; s/\\r//g; s/\\t/    /g; s/\\\//\//g' >"$RESPONSE_TEXT_FILE"
}

html_escape_sh() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

render_prompt_template() {
  awk -v selection="$SELECTION_TEXT" '{
    gsub(/\{\{SELECTED_TEXT\}\}/, selection)
    print
  }' "$PROMPT_TEMPLATE_PATH" >"$PROMPT_FILE"
}

write_loading_html() {
  if [ -f "$STATUS_FILE" ]; then
    STATUS_HTML="$(html_escape_sh <"$STATUS_FILE")"
  else
    STATUS_HTML="Starting..."
  fi

  if command -v python3 >/dev/null 2>&1; then
    SELECTION_PREVIEW_HTML="$(printf '%s' "$SELECTION_TEXT" | python3 "$ESCAPE_HTML_PY")"
  else
    SELECTION_PREVIEW_HTML="$(printf '%s' "$SELECTION_TEXT" | html_escape_sh)"
  fi

  {
    echo "<html><head><meta charset='utf-8'>"
    echo "<meta http-equiv='refresh' content='2'>"
    echo "<title>Kobo AI Answer</title>"
    echo "<style>"
    echo "html, body { margin: 0; min-height: 100%; background: #000; color: #fff; overflow-y: scroll; }"
    echo "body { font-family: Georgia, serif; line-height: 1.75; padding: 1.4em; font-size: 1.22em; }"
    echo ".card { background: #111; border: 1px solid #444; border-radius: 14px; padding: 1.1em; margin-bottom: 1em; }"
    echo "h1 { font-size: 1.9em; margin-bottom: 0.25em; color: #fff; }"
    echo "h2 { font-size: 1.1em; margin-bottom: 0.5em; text-transform: uppercase; letter-spacing: 0.05em; color: #d0d0d0; }"
    echo ".label { font-size: 1em; color: #c8c8c8; margin-bottom: 1em; }"
    echo "pre { white-space: pre-wrap; word-wrap: break-word; font-family: Georgia, serif; font-size: 1.02em; margin: 0; color: #fff; }"
    echo "::-webkit-scrollbar { width: 18px; }"
    echo "::-webkit-scrollbar-track { background: #111; }"
    echo "::-webkit-scrollbar-thumb { background: #666; border-radius: 10px; border: 3px solid #111; }"
    echo "</style></head><body>"
    echo "<h1>AI Answer</h1>"
    echo "<div class='label'>Preparing your explanation...</div>"
    echo "<div class='card'>"
    echo "<h2>Status</h2>"
    echo "<pre>$STATUS_HTML</pre>"
    echo "</div>"
    echo "<div class='card'>"
    echo "<h2>Selected Text</h2>"
    echo "<pre>$SELECTION_PREVIEW_HTML</pre>"
    echo "</div>"
    echo "</body></html>"
  } >"$ANSWER_FILE"
}

set_status() {
  printf '%s\n' "$1" >"$STATUS_FILE"
  log_msg "$1"
  write_loading_html
}

printf '\n===== %s =====\n' "$(date)" >>"$LOG"
log_msg "Starting Ask AI Selection"
log_msg "Log file: $LOG"
log_msg "PATH is: $PATH"
log_msg "PWD is: $(pwd)"
log_msg "USER is: $(id 2>/dev/null || echo unknown)"
log_msg "Args count: $#"
log_msg "Selected text bytes: $(printf '%s' "$SELECTION_TEXT" | wc -c | tr -d ' ')"
printf 'Starting AI explanation...\n' >"$STATUS_FILE"
write_loading_html

if [ ! -f "$CONFIG" ]; then
  log_err "config.env not found at $CONFIG"
  set_status "Error: config.env not found."
  exit 1
fi

. "$CONFIG"
log_msg "Loaded config from $CONFIG"

: "${OPENAI_MODEL:=gpt-4.1-mini}"
: "${PROMPT_TEMPLATE:=}"

if [ -z "$PROMPT_TEMPLATE_PATH" ]; then
  if [ -n "$PROMPT_TEMPLATE" ]; then
    PROMPT_TEMPLATE_PATH="$PROMPT_TEMPLATE"
  else
    PROMPT_TEMPLATE_PATH="$DEFAULT_PROMPT_TEMPLATE"
  fi
fi

if [ -z "$OPENAI_API_KEY" ]; then
  log_err "OPENAI_API_KEY is empty in config.env"
  set_status "Error: OPENAI_API_KEY is empty."
  exit 1
fi

if [ -z "$SELECTION_TEXT" ]; then
  log_err "No selected text was received from Kobo."
  set_status "Error: no selected text was received."
  exit 1
fi

if [ -x "$BUNDLED_BIN_DIR/curl" ]; then
  CURL_BIN="$BUNDLED_BIN_DIR/curl"
elif command -v curl >/dev/null 2>&1; then
  CURL_BIN="$(command -v curl)"
elif [ -x /usr/bin/curl ]; then
  CURL_BIN="/usr/bin/curl"
elif [ -x /bin/curl ]; then
  CURL_BIN="/bin/curl"
elif [ -x /usr/local/bin/curl ]; then
  CURL_BIN="/usr/local/bin/curl"
fi

if [ -z "$CURL_BIN" ]; then
  log_err "curl not found on Kobo."
  log_err "PATH is: $PATH"
  log_err "Checked bundled path: $BUNDLED_BIN_DIR/curl"
  set_status "Error: curl not found on Kobo."
  exit 1
fi

if [ ! -f "$CACERT_FILE" ]; then
  log_err "CA bundle not found at $CACERT_FILE"
  set_status "Error: CA bundle not found."
  exit 1
fi

if [ ! -f "$PROMPT_TEMPLATE_PATH" ]; then
  log_err "Prompt template not found at $PROMPT_TEMPLATE_PATH"
  set_status "Error: prompt template not found."
  exit 1
fi

log_msg "Model: $OPENAI_MODEL"
log_msg "Using curl: $CURL_BIN"
log_msg "Using CA bundle: $CACERT_FILE"
log_msg "Using prompt template: $PROMPT_TEMPLATE_PATH"
set_status "Preparing prompt..."

cat >"$ESCAPE_HTML_PY" <<'PY'
import html
import sys

print(html.escape(sys.stdin.read()), end="")
PY

render_prompt_template
log_msg "Wrote prompt to $PROMPT_FILE"

if command -v python3 >/dev/null 2>&1; then
  log_msg "Using python3 to create request JSON."
  python3 - "$PROMPT_FILE" "$OPENAI_MODEL" >"$JSON_FILE" <<'PY'
import json
import sys

prompt_path = sys.argv[1]
model = sys.argv[2]

with open(prompt_path, "r", encoding="utf-8") as f:
    prompt = f.read()

payload = {
    "model": model,
    "input": prompt
}

print(json.dumps(payload, ensure_ascii=False))
PY
  JSON_STATUS=$?
else
  log_msg "python3 not found; using shell fallback to create request JSON."
  ESCAPED_PROMPT="$(sed 's/\\/\\\\/g; s/"/\\"/g' "$PROMPT_FILE" | awk '{printf "%s\\n", $0}')"
  cat >"$JSON_FILE" <<EOF
{"model":"$OPENAI_MODEL","input":"$ESCAPED_PROMPT"}
EOF
  JSON_STATUS=$?
fi

log_msg "JSON creation exit status: $JSON_STATUS"
if [ "$JSON_STATUS" -ne 0 ]; then
  log_err "Failed to create request JSON."
  set_status "Error: failed to create request JSON."
  exit 1
fi

log_msg "Request JSON bytes: $(wc -c <"$JSON_FILE" | tr -d ' ')"
set_status "Requesting explanation from OpenAI..."

: >"$CURL_ERR_FILE"
log_msg "Launching curl command..."
"$CURL_BIN" -sS -o "$RAW_FILE" -w "%{http_code}" https://api.openai.com/v1/responses \
  --cacert "$CACERT_FILE" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"$JSON_FILE" >"$HTTP_CODE_FILE" 2>"$CURL_ERR_FILE" &
CURL_PID=$!
WAIT_SECS=0
log_msg "curl pid: $CURL_PID"

while kill -0 "$CURL_PID" 2>/dev/null; do
  set_status "Waiting for OpenAI response... ${WAIT_SECS}s"
  sleep 1
  WAIT_SECS=$((WAIT_SECS + 1))
done

wait "$CURL_PID"
CURL_STATUS=$?
HTTP_CODE="$(tr -d '\r\n' <"$HTTP_CODE_FILE" 2>/dev/null)"
log_msg "curl exit status: $CURL_STATUS"
log_msg "HTTP code: $HTTP_CODE"

if [ "$CURL_STATUS" -ne 0 ]; then
  log_err "OpenAI request failed."
  if [ -s "$CURL_ERR_FILE" ]; then
    while IFS= read -r line; do
      log_err "$line"
    done <"$CURL_ERR_FILE"
  fi
  set_status "Error: OpenAI request failed."
  exit 1
fi

case "$HTTP_CODE" in
  200|201)
    set_status "OpenAI response received. Formatting answer..."
    ;;
  *)
    log_err "OpenAI API returned HTTP $HTTP_CODE."
    log_msg "Response body:"
    sed -n '1,80p' "$RAW_FILE" >>"$LOG"
    set_status "Error: OpenAI API returned HTTP $HTTP_CODE."
    exit 1
    ;;
esac

if command -v python3 >/dev/null 2>&1; then
  SELECTION_HTML="$(printf '%s' "$SELECTION_TEXT" | python3 "$ESCAPE_HTML_PY")"
  ESCAPE_STATUS=$?
else
  SELECTION_HTML="$(printf '%s' "$SELECTION_TEXT" | html_escape_sh)"
  ESCAPE_STATUS=$?
fi
log_msg "Selection HTML escape exit status: $ESCAPE_STATUS"

if command -v python3 >/dev/null 2>&1; then
  python3 - "$RAW_FILE" >"$RESPONSE_TEXT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    raise SystemExit(1)

text = data.get("output_text")
if text:
    print(text, end="")
    raise SystemExit

parts = []
for item in data.get("output", []):
    for content in item.get("content", []):
        if content.get("type") in ("output_text", "text"):
            parts.append(content.get("text", ""))

print("\n".join(parts), end="")
PY
  RESPONSE_PARSE_STATUS=$?
else
  extract_response_text_sh
  RESPONSE_PARSE_STATUS=$?
fi

log_msg "Response parse exit status: $RESPONSE_PARSE_STATUS"
if [ "$RESPONSE_PARSE_STATUS" -ne 0 ] || [ ! -s "$RESPONSE_TEXT_FILE" ]; then
  log_err "Could not extract clean response text."
  set_status "Error: could not extract response text."
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  RESPONSE_HTML="$(python3 "$ESCAPE_HTML_PY" <"$RESPONSE_TEXT_FILE")"
  RESPONSE_ESCAPE_STATUS=$?
else
  RESPONSE_HTML="$(html_escape_sh <"$RESPONSE_TEXT_FILE")"
  RESPONSE_ESCAPE_STATUS=$?
fi
log_msg "Response HTML escape exit status: $RESPONSE_ESCAPE_STATUS"

  {
    echo "<html><head><meta charset='utf-8'>"
    echo "<title>Kobo AI Answer</title>"
    echo "<style>"
    echo "html, body { margin: 0; min-height: 100%; background: #000; color: #fff; overflow-y: scroll; }"
    echo "body { font-family: Georgia, serif; line-height: 1.75; padding: 1.4em; font-size: 1.22em; }"
    echo ".card { background: #111; border: 1px solid #444; border-radius: 14px; padding: 1.1em; margin-bottom: 1em; }"
    echo "h1 { font-size: 1.9em; margin-bottom: 0.25em; color: #fff; }"
    echo "h2 { font-size: 1.1em; margin-bottom: 0.5em; text-transform: uppercase; letter-spacing: 0.05em; color: #d0d0d0; }"
    echo ".label { font-size: 1em; color: #c8c8c8; margin-bottom: 1em; }"
    echo "pre { white-space: pre-wrap; word-wrap: break-word; font-family: Georgia, serif; font-size: 1.02em; margin: 0; color: #fff; }"
    echo "::-webkit-scrollbar { width: 18px; }"
    echo "::-webkit-scrollbar-track { background: #111; }"
    echo "::-webkit-scrollbar-thumb { background: #666; border-radius: 10px; border: 3px solid #111; }"
    echo "</style></head><body>"
  echo "<h1>AI Answer</h1>"
  echo "<div class='label'>Generated from your current selection</div>"
  echo "<div class='card'>"
  echo "<h2>Selected Text</h2>"
  echo "<pre>$SELECTION_HTML</pre>"
  echo "</div>"
  echo "<div class='card'>"
  echo "<h2>Simple Explanation</h2>"
  echo "<pre>$RESPONSE_HTML</pre>"
  echo "</div>"
  echo "</body></html>"
} >"$ANSWER_FILE"
ANSWER_STATUS=$?

log_msg "HTML write exit status: $ANSWER_STATUS"
if [ "$ANSWER_STATUS" -ne 0 ]; then
  log_err "Failed to write HTML answer."
  set_status "Error: failed to write HTML answer."
  exit 1
fi

log_msg "Saved: $ANSWER_FILE"
log_msg "Done."
