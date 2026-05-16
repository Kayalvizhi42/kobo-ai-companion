#!/bin/sh

. /mnt/onboard/.adds/ai/ai_request_lib.sh

SELECTION_TEXT="$1"
PROMPT_TEMPLATE_FILE="$WORK_DIR/request_prompt_template_$$.tmpl"
PROMPT_BODY_FILE="$WORK_DIR/request_prompt_body_$$.txt"

ensure_runtime_dirs
require_sqlite3 || {
  {
    echo "<html><head><meta charset='utf-8'><title>Kobo AI Answer</title></head><body>"
    echo "<p>sqlite3 not found. Copy a sqlite3 binary to /mnt/onboard/.adds/bin/sqlite3 or install it on the device.</p>"
    echo "</body></html>"
  } >"$ANSWER_INDEX_FILE"
  exit 1
}
init_db

printf '\n===== %s =====\n' "$(date)" >>"$LOG_FILE"
log_msg "Starting request submission"

if [ -z "$SELECTION_TEXT" ]; then
  log_err "No selected text was received from Kobo."
  {
    echo "<html><head><meta charset='utf-8'><title>Kobo AI Answer</title></head><body>"
    echo "<p>No selected text was received.</p>"
    echo "</body></html>"
  } >"$ANSWER_INDEX_FILE"
  exit 1
fi

if ! load_config; then
  log_err "config.env not found at $CONFIG_FILE"
  {
    echo "<html><head><meta charset='utf-8'><title>Kobo AI Answer</title></head><body>"
    echo "<p>config.env not found.</p>"
    echo "</body></html>"
  } >"$ANSWER_INDEX_FILE"
  exit 1
fi

if [ -z "$OPENAI_API_KEY" ]; then
  log_err "OPENAI_API_KEY is empty in config.env"
  {
    echo "<html><head><meta charset='utf-8'><title>Kobo AI Answer</title></head><body>"
    echo "<p>OPENAI_API_KEY is empty.</p>"
    echo "</body></html>"
  } >"$ANSWER_INDEX_FILE"
  exit 1
fi

if [ ! -f "$PROMPT_TEMPLATE" ]; then
  log_err "Prompt template not found at $PROMPT_TEMPLATE"
  {
    echo "<html><head><meta charset='utf-8'><title>Kobo AI Answer</title></head><body>"
    echo "<p>Prompt template not found.</p>"
    echo "</body></html>"
  } >"$ANSWER_INDEX_FILE"
  exit 1
fi

seed_prompt_library "$PROMPT_TEMPLATE" || {
  log_err "Failed to seed prompt library from $PROMPT_TEMPLATE"
  exit 1
}

REQUEST_TYPE_ID="$(request_type_id "$REQUEST_TYPE_NAME")"
if [ -z "$REQUEST_TYPE_ID" ]; then
  log_err "Request type $REQUEST_TYPE_NAME was not found after seeding."
  exit 1
fi

MODEL_NAME="$(request_type_model "$REQUEST_TYPE_NAME" "$OPENAI_MODEL")"
PROMPT_TEMPLATE_BODY="$(prompt_template_for_type "$REQUEST_TYPE_NAME")"

if [ -z "$PROMPT_TEMPLATE_BODY" ]; then
  log_err "Prompt template body for $REQUEST_TYPE_NAME is empty."
  exit 1
fi

printf '%s' "$PROMPT_TEMPLATE_BODY" >"$PROMPT_TEMPLATE_FILE"
render_prompt_from_template "$SELECTION_TEXT" "$PROMPT_TEMPLATE_FILE" "$PROMPT_BODY_FILE"

REQUEST_BODY="$(cat "$PROMPT_BODY_FILE")"
REQUEST_HASH="$(hash_request "$MODEL_NAME" "$REQUEST_BODY")"
CACHED_REQUEST_ID="$(find_cached_request_id "$REQUEST_HASH")"

if [ -n "$CACHED_REQUEST_ID" ]; then
  log_msg "Serving cached request $CACHED_REQUEST_ID for hash $REQUEST_HASH"
  render_request_html "$CACHED_REQUEST_ID"
  write_dispatch_html "$(request_output_file "$CACHED_REQUEST_ID")"
  exit 0
fi

REQUEST_ID="$(insert_request "$REQUEST_HASH" "$REQUEST_TYPE_ID" "$SELECTION_TEXT" "$REQUEST_BODY" "$MODEL_NAME")"

if [ -z "$REQUEST_ID" ]; then
  log_err "Failed to insert request into database."
  exit 1
fi

log_msg "Queued request $REQUEST_ID for type $REQUEST_TYPE_NAME"
render_request_html "$REQUEST_ID"
write_dispatch_html "$(request_output_file "$REQUEST_ID")"

/mnt/onboard/.adds/ai/process_request_queue_item.sh "$REQUEST_ID" >/dev/null 2>&1 &
/mnt/onboard/.adds/ai/render_request_page.sh "$REQUEST_ID" >/dev/null 2>&1 &

exit 0
