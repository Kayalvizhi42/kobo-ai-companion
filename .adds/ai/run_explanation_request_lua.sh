#!/bin/sh

SCRIPT="/mnt/onboard/.adds/ai/run_lua_backend.sh"
SELECTION_TEXT="$1"

exec "$SCRIPT" run "$SELECTION_TEXT"
