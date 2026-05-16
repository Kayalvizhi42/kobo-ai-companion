#!/bin/sh

OUT="/mnt/onboard/.adds/ai/output/latest_highlight.log"
DB="/mnt/onboard/.kobo/KoboReader.sqlite"
BUNDLED_BIN_DIR="/mnt/onboard/.adds/bin"
SQLITE3_BIN=""

find_sqlite3_bin() {
  if [ -x "$BUNDLED_BIN_DIR/sqlite3" ]; then
    printf '%s' "$BUNDLED_BIN_DIR/sqlite3"
    return 0
  fi

  if command -v sqlite3 >/dev/null 2>&1; then
    command -v sqlite3
    return 0
  fi

  for CANDIDATE in /usr/bin/sqlite3 /bin/sqlite3 /usr/local/bin/sqlite3; do
    if [ -x "$CANDIDATE" ]; then
      printf '%s' "$CANDIDATE"
      return 0
    fi
  done

  return 1
}

mkdir -p /mnt/onboard/.adds/ai/output

echo "Testing Kobo annotation database..." >"$OUT"
echo "" >>"$OUT"

if [ ! -f "$DB" ]; then
  echo "ERROR: KoboReader.sqlite not found at $DB" >>"$OUT"
  exit 1
fi

echo "Database found." >>"$OUT"
echo "" >>"$OUT"

SQLITE3_BIN="$(find_sqlite3_bin)"
if [ -z "$SQLITE3_BIN" ]; then
  echo "ERROR: sqlite3 not found. Copy a sqlite3 binary to /mnt/onboard/.adds/bin/sqlite3" >>"$OUT"
  exit 1
fi

"$SQLITE3_BIN" "$DB" "SELECT Text FROM Bookmark WHERE Text IS NOT NULL AND Text != '' ORDER BY DateCreated DESC LIMIT 1;" >>"$OUT" 2>>"$OUT"
