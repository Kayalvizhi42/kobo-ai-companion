#!/bin/sh

BASE_DIR="/mnt/onboard/.adds/ai"
CONFIG_FILE="$BASE_DIR/config.env"
DEFAULT_PROMPT_TEMPLATE="$BASE_DIR/prompt_template.tmpl"
PAGE_STYLES_FILE="$BASE_DIR/page_styles.css"
DISPATCH_TEMPLATE_FILE="$BASE_DIR/dispatch_page.html.tmpl"
LOADING_TEMPLATE_FILE="$BASE_DIR/loading_page.html.tmpl"
REQUEST_TEMPLATE_FILE="$BASE_DIR/request_page.html.tmpl"

OUT_DIR="$BASE_DIR/output"
WORK_DIR="$BASE_DIR/tmp"
LOG_DIR="$BASE_DIR/logs"
DB_FILE="$BASE_DIR/requests.db"
LOG_FILE="$LOG_DIR/ai_activity.log"

BUNDLED_BIN_DIR="/mnt/onboard/.adds/bin"
BUNDLED_CERT_DIR="/mnt/onboard/.adds/certs"
CACERT_FILE="$BUNDLED_CERT_DIR/cacert.pem"
SQLITE3_BIN=""

ANSWER_INDEX_FILE="$OUT_DIR/latest_ai_answer.html"

REQUEST_TYPE_NAME="explain_selection"
PROMPT_SLUG="explain_selection_default"

ensure_runtime_dirs() {
  mkdir -p "$OUT_DIR" "$WORK_DIR" "$LOG_DIR" "$BUNDLED_CERT_DIR"
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_msg() {
  ensure_runtime_dirs
  printf '%s %s\n' "$(timestamp_utc)" "$1" >>"$LOG_FILE"
}

log_err() {
  log_msg "ERROR: $1"
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

db_exec() {
  "$SQLITE3_BIN" "$DB_FILE" "$1"
}

db_value() {
  "$SQLITE3_BIN" -batch -noheader "$DB_FILE" "$1"
}

init_db() {
  "$SQLITE3_BIN" "$DB_FILE" <<'SQL'
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS prompt_library (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  template_body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS request_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  prompt_id INTEGER NOT NULL REFERENCES prompt_library(id),
  model_override TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_hash TEXT NOT NULL,
  request_type_id INTEGER NOT NULL REFERENCES request_types(id),
  selection_text TEXT NOT NULL,
  body TEXT NOT NULL,
  model TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('queued', 'processing', 'complete', 'error')),
  response TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_requests_hash_state
  ON requests(request_hash, state);

CREATE INDEX IF NOT EXISTS idx_requests_state_created
  ON requests(state, created_at);
SQL
}

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  : "${OPENAI_MODEL:=gpt-4.1-mini}"
  : "${PROMPT_TEMPLATE:=$DEFAULT_PROMPT_TEMPLATE}"
  return 0
}

seed_prompt_library() {
  TEMPLATE_SOURCE="$1"

  if [ ! -f "$TEMPLATE_SOURCE" ]; then
    return 1
  fi

  TEMPLATE_BODY="$(cat "$TEMPLATE_SOURCE")"
  ESCAPED_TEMPLATE_BODY="$(sql_escape "$TEMPLATE_BODY")"

  db_exec "
    INSERT OR IGNORE INTO prompt_library (slug, title, template_body)
    VALUES ('$(sql_escape "$PROMPT_SLUG")', 'Explain Selection', '$ESCAPED_TEMPLATE_BODY');

    UPDATE prompt_library
    SET title = 'Explain Selection',
        template_body = '$ESCAPED_TEMPLATE_BODY',
        updated_at = CURRENT_TIMESTAMP
    WHERE slug = '$(sql_escape "$PROMPT_SLUG")';

    INSERT OR IGNORE INTO request_types (name, description, prompt_id, model_override)
    SELECT '$(sql_escape "$REQUEST_TYPE_NAME")',
           'Explain a highlighted book passage in simple language.',
           id,
           NULL
    FROM prompt_library
    WHERE slug = '$(sql_escape "$PROMPT_SLUG")';

    UPDATE request_types
    SET prompt_id = (
          SELECT id FROM prompt_library
          WHERE slug = '$(sql_escape "$PROMPT_SLUG")'
        ),
        description = 'Explain a highlighted book passage in simple language.',
        updated_at = CURRENT_TIMESTAMP
    WHERE name = '$(sql_escape "$REQUEST_TYPE_NAME")';
  " >/dev/null
}

request_type_id() {
  db_value "
    SELECT id
    FROM request_types
    WHERE name = '$(sql_escape "$1")'
    LIMIT 1;
  "
}

request_type_model() {
  DEFAULT_MODEL="$2"
  MODEL_OVERRIDE="$(db_value "
    SELECT COALESCE(model_override, '')
    FROM request_types
    WHERE name = '$(sql_escape "$1")'
    LIMIT 1;
  ")"

  if [ -n "$MODEL_OVERRIDE" ]; then
    printf '%s' "$MODEL_OVERRIDE"
  else
    printf '%s' "$DEFAULT_MODEL"
  fi
}

prompt_template_for_type() {
  db_value "
    SELECT p.template_body
    FROM request_types rt
    JOIN prompt_library p ON p.id = rt.prompt_id
    WHERE rt.name = '$(sql_escape "$1")'
    LIMIT 1;
  "
}

render_prompt_from_template() {
  SELECTION_TEXT="$1"
  TEMPLATE_FILE="$2"
  OUTPUT_FILE="$3"

  awk -v selection="$SELECTION_TEXT" '
    {
      placeholder = "{{SELECTED_TEXT}}"
      pos = index($0, placeholder)

      if (!pos) {
        print
        next
      }

      prefix = substr($0, 1, pos - 1)
      suffix = substr($0, pos + length(placeholder))
      printf "%s%s%s\n", prefix, selection, suffix
    }
  ' "$TEMPLATE_FILE" >"$OUTPUT_FILE"
}

hash_request() {
  MODEL_NAME="$1"
  REQUEST_BODY="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s\n%s' "$MODEL_NAME" "$REQUEST_BODY" | sha256sum | awk '{print $1}'
  elif command -v md5sum >/dev/null 2>&1; then
    printf '%s\n%s' "$MODEL_NAME" "$REQUEST_BODY" | md5sum | awk '{print $1}'
  else
    printf '%s\n%s' "$MODEL_NAME" "$REQUEST_BODY" | cksum | awk '{print $1 "-" $2}'
  fi
}

find_cached_request_id() {
  REQUEST_HASH="$1"

  db_value "
    SELECT id
    FROM requests
    WHERE request_hash = '$(sql_escape "$REQUEST_HASH")'
      AND state = 'complete'
    ORDER BY id DESC
    LIMIT 1;
  "
}

insert_request() {
  REQUEST_HASH="$1"
  REQUEST_TYPE_ID="$2"
  SELECTION_TEXT="$3"
  REQUEST_BODY="$4"
  MODEL_NAME="$5"

  db_value "
    INSERT INTO requests (
      request_hash,
      request_type_id,
      selection_text,
      body,
      model,
      state
    ) VALUES (
      '$(sql_escape "$REQUEST_HASH")',
      $REQUEST_TYPE_ID,
      '$(sql_escape "$SELECTION_TEXT")',
      '$(sql_escape "$REQUEST_BODY")',
      '$(sql_escape "$MODEL_NAME")',
      'queued'
    );
    SELECT last_insert_rowid();
  "
}

request_field() {
  FIELD_NAME="$1"
  REQUEST_ID="$2"

  db_value "
    SELECT $FIELD_NAME
    FROM requests
    WHERE id = $REQUEST_ID
    LIMIT 1;
  "
}

claim_request() {
  REQUEST_ID="$1"

  db_value "
    UPDATE requests
    SET state = 'processing',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = $REQUEST_ID
      AND state = 'queued';
    SELECT changes();
  "
}

complete_request() {
  REQUEST_ID="$1"
  RESPONSE_TEXT="$2"

  db_exec "
    UPDATE requests
    SET state = 'complete',
        response = '$(sql_escape "$RESPONSE_TEXT")',
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = $REQUEST_ID;
  " >/dev/null
}

error_request() {
  REQUEST_ID="$1"
  ERROR_TEXT="$2"

  db_exec "
    UPDATE requests
    SET state = 'error',
        error_message = '$(sql_escape "$ERROR_TEXT")',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = $REQUEST_ID;
  " >/dev/null
}

html_escape_sh() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

page_styles() {
  cat "$PAGE_STYLES_FILE"
}

render_template_file() {
  TEMPLATE_FILE="$1"
  OUTPUT_FILE="$2"

  env \
    TPL_PAGE_CSS="$TPL_PAGE_CSS" \
    TPL_TARGET_FILE="$TPL_TARGET_FILE" \
    TPL_REFRESH_LINE="$TPL_REFRESH_LINE" \
    TPL_REQUEST_META="$TPL_REQUEST_META" \
    TPL_STATUS_LABEL="$TPL_STATUS_LABEL" \
    TPL_STATUS_BODY="$TPL_STATUS_BODY" \
    TPL_SELECTION_HTML="$TPL_SELECTION_HTML" \
    TPL_RESULT_CARD_BLOCK="$TPL_RESULT_CARD_BLOCK" \
    TPL_STATUS_MESSAGE="$TPL_STATUS_MESSAGE" \
    awk '
      {
        if ($0 == "{{PAGE_CSS}}") {
          print ENVIRON["TPL_PAGE_CSS"]
        } else if ($0 == "{{REFRESH_LINE}}") {
          print ENVIRON["TPL_REFRESH_LINE"]
        } else if ($0 == "{{RESULT_CARD_BLOCK}}") {
          print ENVIRON["TPL_RESULT_CARD_BLOCK"]
        } else if ($0 == "<meta http-equiv='\''refresh'\'' content='\''0;url=file://{{TARGET_FILE}}'\''>") {
          print "<meta http-equiv='\''refresh'\'' content='\''0;url=file://" ENVIRON["TPL_TARGET_FILE"] "'\''>"
        } else if ($0 == "<p><a href='\''file://{{TARGET_FILE}}'\''>Tap here if it does not open automatically.</a></p>") {
          print "<p><a href='\''file://" ENVIRON["TPL_TARGET_FILE"] "'\''>Tap here if it does not open automatically.</a></p>"
        } else if ($0 == "<div class='\''label'\''>{{REQUEST_META}}</div>") {
          print "<div class='\''label'\''>" ENVIRON["TPL_REQUEST_META"] "</div>"
        } else if ($0 == "<pre>{{STATUS_LABEL}}</pre>") {
          print "<pre>" ENVIRON["TPL_STATUS_LABEL"] "</pre>"
        } else if ($0 == "<pre>{{STATUS_BODY}}</pre>") {
          print "<pre>" ENVIRON["TPL_STATUS_BODY"] "</pre>"
        } else if ($0 == "<pre>{{SELECTION_HTML}}</pre>") {
          print "<pre>" ENVIRON["TPL_SELECTION_HTML"] "</pre>"
        } else if ($0 == "<pre>{{STATUS_MESSAGE}}</pre>") {
          print "<pre>" ENVIRON["TPL_STATUS_MESSAGE"] "</pre>"
        } else {
          print
        }
      }
    ' "$TEMPLATE_FILE" >"$OUTPUT_FILE"
}

request_output_file() {
  printf '%s/request_%s.html' "$OUT_DIR" "$1"
}

write_dispatch_html() {
  TARGET_FILE="$1"
  TPL_TARGET_FILE="$TARGET_FILE"
  render_template_file "$DISPATCH_TEMPLATE_FILE" "$ANSWER_INDEX_FILE"
}

render_request_html() {
  REQUEST_ID="$1"
  OUTPUT_FILE="$(request_output_file "$REQUEST_ID")"

  STATE="$(request_field state "$REQUEST_ID")"
  SELECTION_TEXT="$(request_field selection_text "$REQUEST_ID")"
  RESPONSE_TEXT="$(request_field response "$REQUEST_ID")"
  ERROR_TEXT="$(request_field error_message "$REQUEST_ID")"
  TYPE_NAME="$(db_value "
    SELECT rt.name
    FROM requests r
    JOIN request_types rt ON rt.id = r.request_type_id
    WHERE r.id = $REQUEST_ID
    LIMIT 1;
  ")"

  if [ -z "$STATE" ]; then
    STATE="error"
    ERROR_TEXT="Request $REQUEST_ID was not found."
  fi

  SELECTION_HTML="$(printf '%s' "$SELECTION_TEXT" | html_escape_sh)"
  RESPONSE_HTML="$(printf '%s' "$RESPONSE_TEXT" | html_escape_sh)"
  ERROR_HTML="$(printf '%s' "$ERROR_TEXT" | html_escape_sh)"
  TYPE_HTML="$(printf '%s' "$TYPE_NAME" | html_escape_sh)"
  PAGE_CSS="$(page_styles)"

  REFRESH_LINE=""
  STATUS_LABEL=""
  STATUS_BODY=""

  case "$STATE" in
    queued)
      REFRESH_LINE="<meta http-equiv='refresh' content='2'>"
      STATUS_LABEL="Queued"
      STATUS_BODY="Your request is waiting to be processed."
      ;;
    processing)
      REFRESH_LINE="<meta http-equiv='refresh' content='2'>"
      STATUS_LABEL="Processing"
      STATUS_BODY="OpenAI is generating your explanation."
      ;;
    complete)
      STATUS_LABEL="Complete"
      STATUS_BODY="Your explanation is ready."
      ;;
    error|*)
      STATUS_LABEL="Error"
      STATUS_BODY="$ERROR_HTML"
      ;;
  esac

  case "$STATE" in
    complete)
      RESULT_CARD_BLOCK="<div class='card'>
<h2>Simple Explanation</h2>
<pre>$RESPONSE_HTML</pre>
</div>"
      ;;
    error|*)
      RESULT_CARD_BLOCK="<div class='card'>
<h2>Details</h2>
<pre>$ERROR_HTML</pre>
</div>"
      ;;
    *)
      RESULT_CARD_BLOCK=""
      ;;
  esac

  TPL_PAGE_CSS="$PAGE_CSS"
  TPL_REFRESH_LINE="$REFRESH_LINE"
  TPL_REQUEST_META="Request #$REQUEST_ID | Type: $TYPE_HTML"
  TPL_STATUS_LABEL="$STATUS_LABEL"
  TPL_STATUS_BODY="$STATUS_BODY"
  TPL_SELECTION_HTML="$SELECTION_HTML"
  TPL_RESULT_CARD_BLOCK="$RESULT_CARD_BLOCK"
  render_template_file "$REQUEST_TEMPLATE_FILE" "$OUTPUT_FILE"
}

json_payload_from_prompt() {
  PROMPT_FILE="$1"
  MODEL_NAME="$2"
  OUTPUT_FILE="$3"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$PROMPT_FILE" "$MODEL_NAME" >"$OUTPUT_FILE" <<'PY'
import json
import sys

prompt_path = sys.argv[1]
model = sys.argv[2]

with open(prompt_path, "r", encoding="utf-8") as f:
    prompt = f.read()

print(json.dumps({"model": model, "input": prompt}, ensure_ascii=False))
PY
    return $?
  fi

  {
    printf '{"model":"'
    printf '%s' "$MODEL_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g'
    printf '","input":"'
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g' "$PROMPT_FILE" | awk '{printf "%s\\n", $0}'
    printf '"}'
  } >"$OUTPUT_FILE"
}

extract_response_text() {
  RAW_FILE="$1"
  OUTPUT_FILE="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$RAW_FILE" >"$OUTPUT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

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
    return $?
  fi

  awk -v output_file="$OUTPUT_FILE" '
    BEGIN {
      RS = ""
      ORS = ""
    }

    function extract_string_value(payload, key,    pattern, start, tail, colon, first, i, c, escaped, out) {
      pattern = "\"" key "\""
      start = index(payload, pattern)
      if (!start) {
        return ""
      }

      tail = substr(payload, start + length(pattern))
      colon = index(tail, ":")
      if (!colon) {
        return ""
      }

      tail = substr(tail, colon + 1)
      while (length(tail) > 0) {
        first = substr(tail, 1, 1)
        if (first ~ /[[:space:]]/) {
          tail = substr(tail, 2)
        } else {
          break
        }
      }

      if (substr(tail, 1, 1) != "\"") {
        return ""
      }

      tail = substr(tail, 2)
      out = ""
      escaped = 0

      for (i = 1; i <= length(tail); i++) {
        c = substr(tail, i, 1)
        if (escaped) {
          if (c == "n") {
            out = out "\n"
          } else if (c == "r") {
            out = out "\r"
          } else if (c == "t") {
            out = out "\t"
          } else {
            out = out c
          }
          escaped = 0
          continue
        }

        if (c == "\\") {
          escaped = 1
          continue
        }

        if (c == "\"") {
          return out
        }

        out = out c
      }

      return ""
    }

    {
      text = extract_string_value($0, "output_text")
      if (text == "") {
        text = extract_string_value($0, "text")
      }

      if (text == "") {
        exit 1
      }

      printf "%s", text > output_file
    }
  ' "$RAW_FILE"
}

find_curl_bin() {
  if [ -x "$BUNDLED_BIN_DIR/curl" ]; then
    printf '%s' "$BUNDLED_BIN_DIR/curl"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    command -v curl
    return 0
  fi

  for CANDIDATE in /usr/bin/curl /bin/curl /usr/local/bin/curl; do
    if [ -x "$CANDIDATE" ]; then
      printf '%s' "$CANDIDATE"
      return 0
    fi
  done

  return 1
}

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

require_sqlite3() {
  SQLITE3_BIN="$(find_sqlite3_bin)"

  if [ -z "$SQLITE3_BIN" ]; then
    log_err "sqlite3 not found on Kobo."
    return 1
  fi

  return 0
}
