#!/bin/sh

SCRIPT="/mnt/onboard/.adds/ai/run_lua_backend.sh"
RUN_SCRIPT="/mnt/onboard/.adds/ai/run_explanation_request_lua.sh"
SELECTION_TEXT="$1"

"$SCRIPT" prepare "$SELECTION_TEXT" || exit 1
"$RUN_SCRIPT" "$SELECTION_TEXT" >/dev/null 2>&1 &
