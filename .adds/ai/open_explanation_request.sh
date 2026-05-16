#!/bin/sh

ANSWER_FILE="/mnt/onboard/.adds/ai/output/latest_ai_answer.html"
OUT_DIR="/mnt/onboard/.adds/ai/output"
SCRIPT="/mnt/onboard/.adds/ai/submit_explanation_request.sh"
SELECTION_TEXT="$1"

. /mnt/onboard/.adds/ai/ai_request_lib.sh

mkdir -p "$OUT_DIR"

TPL_PAGE_CSS="$(page_styles)"
TPL_STATUS_MESSAGE="Preparing request..."
render_template_file "$LOADING_TEMPLATE_FILE" "$ANSWER_FILE"

"$SCRIPT" "$SELECTION_TEXT" >/dev/null 2>&1 &
