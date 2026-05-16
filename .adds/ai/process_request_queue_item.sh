#!/bin/sh

. /mnt/onboard/.adds/ai/ai_request_lib.sh

REQUEST_ID="$1"
REQUEST_JSON_FILE="$WORK_DIR/request_${REQUEST_ID}.json"
RAW_FILE="$WORK_DIR/request_${REQUEST_ID}_raw.json"
RESPONSE_TEXT_FILE="$WORK_DIR/request_${REQUEST_ID}_response.txt"
HTTP_CODE_FILE="$WORK_DIR/request_${REQUEST_ID}_http.code"
CURL_ERR_FILE="$WORK_DIR/request_${REQUEST_ID}_curl.err"

ensure_runtime_dirs
require_sqlite3 || exit 1
init_db

if [ -z "$REQUEST_ID" ]; then
  log_err "process_request_queue_item.sh started without a request id."
  exit 1
fi

if ! load_config; then
  log_err "config.env not found at $CONFIG_FILE"
  error_request "$REQUEST_ID" "config.env not found."
  exit 1
fi

if [ -z "$OPENAI_API_KEY" ]; then
  log_err "OPENAI_API_KEY is empty in config.env"
  error_request "$REQUEST_ID" "OPENAI_API_KEY is empty."
  exit 1
fi

if [ ! -f "$CACERT_FILE" ]; then
  log_err "CA bundle not found at $CACERT_FILE"
  error_request "$REQUEST_ID" "CA bundle not found."
  exit 1
fi

CURL_BIN="$(find_curl_bin)"
if [ -z "$CURL_BIN" ]; then
  log_err "curl not found on Kobo."
  error_request "$REQUEST_ID" "curl not found on Kobo."
  exit 1
fi

CLAIMED="$(claim_request "$REQUEST_ID")"
if [ "$CLAIMED" != "1" ]; then
  log_msg "Request $REQUEST_ID was not in queued state; skipping worker."
  exit 0
fi

REQUEST_BODY="$(request_field body "$REQUEST_ID")"
MODEL_NAME="$(request_field model "$REQUEST_ID")"

if [ -z "$REQUEST_BODY" ] || [ -z "$MODEL_NAME" ]; then
  log_err "Request $REQUEST_ID is missing body or model."
  error_request "$REQUEST_ID" "Request is missing body or model."
  exit 1
fi

printf '%s' "$REQUEST_BODY" >"$RESPONSE_TEXT_FILE"
json_payload_from_prompt "$RESPONSE_TEXT_FILE" "$MODEL_NAME" "$REQUEST_JSON_FILE"
JSON_STATUS=$?

if [ "$JSON_STATUS" -ne 0 ]; then
  log_err "Failed to build JSON payload for request $REQUEST_ID."
  error_request "$REQUEST_ID" "Failed to build JSON payload."
  exit 1
fi

: >"$CURL_ERR_FILE"

"$CURL_BIN" -sS -o "$RAW_FILE" -w "%{http_code}" https://api.openai.com/v1/responses \
  --cacert "$CACERT_FILE" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"$REQUEST_JSON_FILE" >"$HTTP_CODE_FILE" 2>"$CURL_ERR_FILE"
CURL_STATUS=$?
HTTP_CODE="$(tr -d '\r\n' <"$HTTP_CODE_FILE" 2>/dev/null)"

if [ "$CURL_STATUS" -ne 0 ]; then
  log_err "OpenAI request failed for request $REQUEST_ID."
  if [ -s "$CURL_ERR_FILE" ]; then
    ERROR_BODY="$(sed -n '1,20p' "$CURL_ERR_FILE")"
  else
    ERROR_BODY="curl exited with status $CURL_STATUS."
  fi
  error_request "$REQUEST_ID" "$ERROR_BODY"
  exit 1
fi

case "$HTTP_CODE" in
  200|201)
    ;;
  *)
    ERROR_BODY="$(sed -n '1,40p' "$RAW_FILE")"
    log_err "OpenAI API returned HTTP $HTTP_CODE for request $REQUEST_ID."
    error_request "$REQUEST_ID" "OpenAI API returned HTTP $HTTP_CODE.
$ERROR_BODY"
    exit 1
    ;;
esac

extract_response_text "$RAW_FILE" "$RESPONSE_TEXT_FILE"
PARSE_STATUS=$?

if [ "$PARSE_STATUS" -ne 0 ] || [ ! -s "$RESPONSE_TEXT_FILE" ]; then
  log_err "Could not extract response text for request $REQUEST_ID."
  error_request "$REQUEST_ID" "Could not extract response text from the OpenAI response."
  exit 1
fi

RESPONSE_TEXT="$(cat "$RESPONSE_TEXT_FILE")"
complete_request "$REQUEST_ID" "$RESPONSE_TEXT"
log_msg "Completed request $REQUEST_ID"

exit 0
