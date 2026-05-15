#!/bin/sh

ANSWER_FILE="/mnt/onboard/.adds/ai/output/latest_ai_answer.html"
OUT_DIR="/mnt/onboard/.adds/ai/output"
SCRIPT="/mnt/onboard/.adds/ai/ask_ai_selection.sh"
SELECTION_TEXT="$1"

mkdir -p "$OUT_DIR"

cat >"$ANSWER_FILE" <<EOF
<html><head><meta charset='utf-8'>
<meta http-equiv='refresh' content='2'>
<title>Kobo AI Answer</title>
<style>
html, body { margin: 0; min-height: 100%; background: #000; color: #fff; overflow-y: scroll; }
body { font-family: Georgia, serif; line-height: 1.75; padding: 1.4em; font-size: 1.22em; }
.card { background: #111; border: 1px solid #444; border-radius: 14px; padding: 1.1em; margin-bottom: 1em; }
h1 { font-size: 1.9em; margin-bottom: 0.25em; color: #fff; }
h2 { font-size: 1.1em; margin-bottom: 0.5em; text-transform: uppercase; letter-spacing: 0.05em; color: #d0d0d0; }
pre { white-space: pre-wrap; word-wrap: break-word; font-family: Georgia, serif; font-size: 1.02em; margin: 0; color: #fff; }
</style></head><body>
<h1>AI Answer</h1>
<div class='card'>
<h2>Status</h2>
<pre>Starting AI explanation...</pre>
</div>
</body></html>
EOF

"$SCRIPT" "$SELECTION_TEXT" >/dev/null 2>&1 &
