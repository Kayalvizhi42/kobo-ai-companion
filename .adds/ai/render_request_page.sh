#!/bin/sh

. /mnt/onboard/.adds/ai/ai_request_lib.sh

REQUEST_ID="$1"

ensure_runtime_dirs
require_sqlite3 || exit 1
init_db

if [ -z "$REQUEST_ID" ]; then
  log_err "render_request_page.sh started without a request id."
  exit 1
fi

while :; do
  render_request_html "$REQUEST_ID"
  STATE="$(request_field state "$REQUEST_ID")"

  case "$STATE" in
    complete|error)
      break
      ;;
  esac

  sleep 1
done

exit 0
