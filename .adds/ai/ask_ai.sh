#!/bin/sh

OUT="/mnt/onboard/.adds/ai/output/latest_highlight.log"
DB="/mnt/onboard/.kobo/KoboReader.sqlite"

mkdir -p /mnt/onboard/.adds/ai/output

echo "Testing Kobo annotation database..." >"$OUT"
echo "" >>"$OUT"

if [ ! -f "$DB" ]; then
  echo "ERROR: KoboReader.sqlite not found at $DB" >>"$OUT"
  exit 1
fi

echo "Database found." >>"$OUT"
echo "" >>"$OUT"

sqlite3 "$DB" "SELECT Text FROM Bookmark WHERE Text IS NOT NULL AND Text != '' ORDER BY DateCreated DESC LIMIT 1;" >>"$OUT" 2>>"$OUT"
