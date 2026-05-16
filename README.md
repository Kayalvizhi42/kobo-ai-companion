# Kobo AI Companion

Use a Kobo selection to ask an OpenAI model for a simple, teacher-style explanation of the selected passage.

The current workflow:

- Select text inside a book on Kobo.
- Tap `Ask LLM` from the selection menu.
- Kobo opens a local HTML page immediately.
- A SQLite-backed request is queued and processed in the background.
- While the request runs, a request-specific page shows live status updates.
- When the response is ready, that page refreshes into a formatted answer view.

The answer page is designed for on-device reading:

- black background
- white text
- larger type
- scrollable long-form response

## Screenshots

Selection and launch flow:

<img src="images/screen_004.png" alt="Ask LLM menu action on Kobo" width="420" />

Generated answer view:

<table>
  <tr>
    <td><img src="images/screen_005.png" alt="Formatted AI answer on Kobo" width="320" /></td>
    <td><img src="images/screen_002.png" alt="Long-form explanation view on Kobo" width="320" /></td>
  </tr>
</table>

## What This Project Contains

This repository mirrors the files that live on the Kobo:

```text
.adds/
  ai/
    debug_latest_highlight.sh
    ai_request_lib.sh
    submit_explanation_request.sh
    open_explanation_request.sh
    process_request_queue_item.sh
    render_request_page.sh
    config.env.example
    prompt_template.tmpl
  bin/
    curl
    sqlite3
  certs/
    cacert.pem
  nm/
    config
```

What each file does:

- `.adds/ai/debug_latest_highlight.sh`
  Small database test helper that writes the latest highlight text to a log file under `.adds/ai/output/`.
- `.adds/ai/ai_request_lib.sh`
  Shared shell helpers for SQLite access, prompt seeding, hashing, and HTML rendering.
- `.adds/ai/submit_explanation_request.sh`
  Request submitter. Seeds the prompt library, creates or reuses a request, and launches the worker and watcher.
- `.adds/ai/open_explanation_request.sh`
  Small wrapper that creates the loading page first, then launches the background AI request.
- `.adds/ai/process_request_queue_item.sh`
  Background worker that claims a queued request, calls OpenAI, and stores the response in SQLite.
- `.adds/ai/render_request_page.sh`
  Background poller that keeps rewriting the request page until the request becomes `complete` or `error`.
- `.adds/ai/config.env.example`
  Template for your API key and model selection.
- `.adds/ai/prompt_template.tmpl`
  Editable default prompt template used to seed the prompt library.
- `.adds/bin/curl`
  Bundled static ARM `curl` binary used by Kobo.
- `.adds/bin/sqlite3`
  Bundled `sqlite3` binary used by the request queue and debug helper when Kobo does not provide one.
- `.adds/certs/cacert.pem`
  CA bundle so `curl` can validate HTTPS to `api.openai.com`.
- `.adds/nm/config`
  NickelMenu entry for `Ask LLM`.

## Prerequisites

You need:

- a Kobo device
- NickelMenu installed
- an OpenAI API key
- a working `sqlite3` binary on the Kobo, either system-provided or copied to `.adds/bin/sqlite3`
- USB access to copy files to the Kobo storage

## 1. Install NickelMenu

This setup depends on NickelMenu.

Primary repo:

- https://github.com/pgaskin/NickelMenu

NickelMenu release downloads:

- https://github.com/pgaskin/NickelMenu/releases

Install steps:

1. Download the latest `KoboRoot.tgz` from the NickelMenu releases page.
2. Connect the Kobo over USB.
3. Copy `KoboRoot.tgz` into the Kobo’s hidden `.kobo` folder.
4. Eject the device safely.
5. Let Kobo reboot and install NickelMenu.

NickelMenu’s README documents the same manual install flow: copy `KoboRoot.tgz` to `.kobo`, then eject so Kobo installs it.

## 2. Create an OpenAI API Key

OpenAI quickstart:

- https://platform.openai.com/docs/quickstart?api-mode=responses&lang=curl

OpenAI authentication reference:

- https://platform.openai.com/docs/api-reference/authentication?api-mode=responses

What to do:

1. Create or sign into your OpenAI account.
2. Create an API key in the OpenAI dashboard.
3. Make sure your project has billing/credits enabled if required for API usage.
4. Keep the API key private.

Important:

- Do not commit your real API key into git.
- Use the template file in this repo and create your real config only on the Kobo.
- If you previously exposed your key while testing, rotate it and create a fresh one.

## 3. Copy The Project Files To Kobo

Connect the Kobo over USB.

The root of the mounted device is typically something like:

- `KOBOeReader/`

Copy this repo’s `.adds` contents onto the Kobo so the device ends up with:

```text
/mnt/onboard/.adds/ai/debug_latest_highlight.sh
/mnt/onboard/.adds/ai/ai_request_lib.sh
/mnt/onboard/.adds/ai/submit_explanation_request.sh
/mnt/onboard/.adds/ai/open_explanation_request.sh
/mnt/onboard/.adds/ai/process_request_queue_item.sh
/mnt/onboard/.adds/ai/render_request_page.sh
/mnt/onboard/.adds/ai/prompt_template.tmpl
/mnt/onboard/.adds/ai/config.env
/mnt/onboard/.adds/bin/curl
/mnt/onboard/.adds/bin/sqlite3
/mnt/onboard/.adds/certs/cacert.pem
/mnt/onboard/.adds/nm/config
```

Practical copy steps:

1. Copy `.adds/ai/debug_latest_highlight.sh` to `KOBOeReader/.adds/ai/`
2. Copy `.adds/ai/ai_request_lib.sh` to `KOBOeReader/.adds/ai/`
3. Copy `.adds/ai/submit_explanation_request.sh` to `KOBOeReader/.adds/ai/`
4. Copy `.adds/ai/open_explanation_request.sh` to `KOBOeReader/.adds/ai/`
5. Copy `.adds/ai/process_request_queue_item.sh` to `KOBOeReader/.adds/ai/`
6. Copy `.adds/ai/render_request_page.sh` to `KOBOeReader/.adds/ai/`
7. Copy `.adds/ai/prompt_template.tmpl` to `KOBOeReader/.adds/ai/`
8. Copy `.adds/bin/curl` to `KOBOeReader/.adds/bin/`
9. Copy `.adds/bin/sqlite3` to `KOBOeReader/.adds/bin/` unless your Kobo already has a working `sqlite3`
10. Copy `.adds/certs/cacert.pem` to `KOBOeReader/.adds/certs/`
11. Copy `.adds/nm/config` to `KOBOeReader/.adds/nm/`

If you already have a NickelMenu config:

- merge the `Ask LLM` entry into your existing `KOBOeReader/.adds/nm/config`
- do not blindly overwrite a custom config unless that is what you want

## 4. Create `config.env`

On the Kobo, create:

- `KOBOeReader/.adds/ai/config.env`

Start from this template:

```sh
OPENAI_API_KEY="sk-your-api-key-here"
OPENAI_MODEL="gpt-4.1-mini"
PROMPT_TEMPLATE="/mnt/onboard/.adds/ai/prompt_template.tmpl"
```

You can copy `config.env.example` and rename it to `config.env`, then replace the placeholder key.

## 4b. Customize The Prompt

The explanation prompt now lives outside the shell script in:

- `KOBOeReader/.adds/ai/prompt_template.tmpl`

The selected passage is injected where the template contains:

```text
{{SELECTED_TEXT}}
```

For the current shell implementation, keep `{{SELECTED_TEXT}}` on its own line for the most reliable rendering.

You can customize the behavior by editing that template file directly. On the next request, the script seeds the `prompt_library` table from that file and the `explain_selection` request type points at the updated template.

`config.env` may define:

```sh
PROMPT_TEMPLATE="/mnt/onboard/.adds/ai/prompt_template.tmpl"
```

If `PROMPT_TEMPLATE` is set, the seeding step will use that path by default.

## 5. Eject And Let Kobo Reload

After copying files:

1. Eject the Kobo safely.
2. Disconnect USB.
3. If NickelMenu was newly installed, let the device reboot.
4. If you only changed `.adds` files, reopening Nickel may be enough, but a reboot is the safest option if the new menu item does not appear immediately.

## 6. How To Use It

On the Kobo:

1. Open a book.
2. Select a passage.
3. Tap `Ask LLM`.
4. A local HTML page opens and shows loading status.
5. Wait for the answer page to refresh into the final explanation.

## Prompt Behavior

The current prompt is tuned to act like a teacher:

- explain the selected passage in simple language
- assume the reader is confused and needs clarity
- use context clues from the passage
- optionally use analogy when helpful
- keep the answer concise
- end with 1 or 2 curiosity-sparking questions

If you want to tune the behavior, edit:

- `.adds/ai/prompt_template.tmpl`

The selected passage is inserted where the template contains `{{SELECTED_TEXT}}`.

## Where Output And Logs Go

Answer page:

- `/mnt/onboard/.adds/ai/output/latest_ai_answer.html`
- `/mnt/onboard/.adds/ai/output/request_<id>.html`

Database test output:

- `/mnt/onboard/.adds/ai/output/latest_highlight.log`

Hidden log file:

- `/mnt/onboard/.adds/ai/logs/ai_activity.log`

SQLite request database:

- `/mnt/onboard/.adds/ai/requests.db`

Runtime tables:

- `prompt_library`
- `request_types`
- `requests`

Why these files stay under `.adds`:

- Kobo may index supported text files from normal user storage into `My Books`
- keeping output and logs under `.adds` avoids polluting the book list

## Technical Notes

- The Kobo environment used here did not provide a working `curl`, so this repo includes a bundled static ARM `curl`.
- The SQLite-backed request flow depends on `sqlite3`. The scripts first look for `/mnt/onboard/.adds/bin/sqlite3`, then fall back to a system `sqlite3` if the device already has one.
- The Kobo environment also needed a CA bundle for HTTPS verification, so `cacert.pem` is included.
- The request flow is now database-backed, so prompt templates, request types, request state, responses, and cache hits live in SQLite instead of shared temp files.
- The script does not rely on `python3` being installed on the Kobo, though it will use it when available for safer JSON handling.
- The immediate UI is still a local browser modal page. This repo does not yet implement a native Kobo popup window.
- The OpenAI call uses the Responses API endpoint:
  `https://api.openai.com/v1/responses`

## Troubleshooting

If `Ask LLM` does not appear:

- confirm NickelMenu is installed
- confirm the menu entry exists in `KOBOeReader/.adds/nm/config`
- reboot the Kobo after changing menu files

If the page opens but no answer appears:

- inspect `/mnt/onboard/.adds/ai/logs/ai_activity.log`
- inspect `/mnt/onboard/.adds/ai/requests.db` for stuck `queued` or `processing` rows

If HTTPS fails:

- verify `.adds/bin/curl` exists
- verify `.adds/certs/cacert.pem` exists

If request submission fails immediately:

- verify `.adds/bin/sqlite3` exists, or verify the Kobo already has a working `sqlite3`

If API calls fail:

- confirm the API key in `config.env`
- confirm your OpenAI project can make API requests

## Sources

- NickelMenu repo: https://github.com/pgaskin/NickelMenu
- NickelMenu releases: https://github.com/pgaskin/NickelMenu/releases
- OpenAI quickstart: https://platform.openai.com/docs/quickstart?api-mode=responses&lang=curl
- OpenAI authentication reference: https://platform.openai.com/docs/api-reference/authentication?api-mode=responses
- OpenAI Responses API reference: https://platform.openai.com/docs/api-reference/responses/create
