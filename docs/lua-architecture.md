# Lua Architecture

## Goal

Move the Kobo addon backend from shell scripts to a small Lua application that is easier to read, test, and extend.

The external behavior should stay familiar:

- NickelMenu launches the addon from a text selection
- a local HTML page opens immediately
- the backend either reuses a cached answer or calls the provider
- that same backend command overwrites one stable HTML result page

## NickelMenu Launch Model

NickelMenu launches shell commands, not Lua modules directly.

That means the clean launch chain is:

1. NickelMenu runs a tiny shell wrapper.
2. That wrapper calls `run_lua_backend.sh prepare "$selection"` to write the loading page.
3. The same wrapper backgrounds another tiny shell wrapper for `run`.
4. That second wrapper calls `run_lua_backend.sh run "$selection"`.

Responsibility split:

- shell owns process startup and backgrounding
- Lua owns page rendering, cache lookup, provider calls, DB updates, and final page writes

This keeps Kobo-specific launch behavior in shell, while the app logic stays in Lua.

## Runtime Decision

This project will bundle its own Lua runtime.

We will not depend on KOReader's `luajit` binary or Lua modules.

Why:

- keeps the addon standalone
- avoids hidden coupling to KOReader installs and versions
- makes the runtime behavior predictable
- lets Nickel-only users install the addon cleanly

Planned runtime lookup order:

1. `/mnt/onboard/.adds/bin/luajit`
2. `/mnt/onboard/.adds/bin/lua`
3. system `luajit`
4. system `lua`

In practice, we should ship `luajit` in `.adds/bin/` and treat that as the expected runtime.

For mutable runtime state on Kobo:

- keep templates, rendered browser HTML, and the default SQLite cache under `/mnt/onboard/.adds/ai`
- allow an override path when debugging or experimenting with alternate state locations

## Design Principles

- Keep shell small. Shell should only launch the Lua app.
- Separate domain logic from provider-specific code.
- Keep the request pipeline provider-agnostic.
- Keep HTML rendering separate from request/state logic.
- Keep the database behind a single adapter.
- Make cache and retry behavior explicit.
- Prefer simple module boundaries over a large framework.

## High-Level Flow

1. NickelMenu launches a tiny shell wrapper.
2. The shell wrapper finds the bundled Lua runtime and starts `main.lua`.
3. `main.lua open` writes a loading page and spawns `main.lua run`.
4. `main.lua run` loads config, resolves the request type, renders the prompt, computes the request hash, and checks cache.
5. If a completed cached request exists, it immediately overwrites `latest_ai_answer.html` with the cached result.
6. Otherwise it calls the provider, stores the fresh result in SQLite, and overwrites that same HTML file with the final answer.

## Core Concepts

### Provider

A provider is any backend that can fulfill an LLM request.

Examples:

- OpenAI
- Anthropic
- local HTTP LLM endpoint
- future lightweight on-device or LAN model gateway

The rest of the app should not care which provider is being used.

### Request Type

A request type describes what kind of task we are doing.

Examples:

- `explain_selection`
- `summarize_selection`
- `translate_selection`

A request type should point to:

- a prompt template
- a provider
- a default model
- optional provider-specific settings

### Request

A request row is primarily a cache record.

It includes:

- request type
- selection text
- rendered prompt body
- request hash
- bookkeeping state
- normalized response text
- raw provider response for debugging

## Proposed Module Layout

```text
.adds/ai/
  lua/
    main.lua
    runtime.lua
    config.lua
    log.lua
    db.lua
    prompts.lua
    request_types.lua
    requests.lua
    render.lua
    worker.lua
    providers/
      init.lua
      openai.lua
  loading_page.html.tmpl
  request_page.html.tmpl
  page_styles.css
  open_explanation_request_lua.sh
  run_explanation_request_lua.sh
```

## Module Responsibilities

### `main.lua`

Entry point and command dispatcher.

Example commands:

- `prepare`
- `run`
- `debug`

### `runtime.lua`

Resolves:

- runtime paths
- bundled binaries
- writable directories
- template locations

This is where bundled `curl`, `sqlite3`, and `luajit` discovery should live.

### `config.lua`

Loads user configuration from `config.env`-style settings and normalizes defaults.

This module should return a plain Lua table, not environment lookups scattered throughout the codebase.

### `log.lua`

Central logging helpers for:

- info events
- error events
- request lifecycle events

### `db.lua`

Single database adapter for SQLite access.

Version 1 can wrap the bundled `sqlite3` CLI.

Desired API shape:

- `db.exec(sql, params)`
- `db.one(sql, params)`
- `db.all(sql, params)`
- `db.transaction(fn)`

The rest of the application should never shell out to `sqlite3` directly.

### `prompts.lua`

Handles:

- reading prompt templates
- seeding prompt records
- rendering templates with variables such as selected text

### `request_types.lua`

Resolves request-type configuration from the database.

This is where request-type defaults should be assembled:

- prompt
- provider
- model
- options

### `requests.lua`

Owns cache logic:

- compute hash
- insert fresh result records
- find reusable completed results
- normalize stored request metadata

### `render.lua`

Owns HTML generation.

It should take structured page data and return rendered HTML, rather than mixing DB queries with templates.

### `worker.lua`

Runs one provider call for one rendered prompt and returns normalized output.

### `providers/openai.lua`

OpenAI-specific adapter only.

It should know how to:

- build the OpenAI payload
- call the Responses API
- parse OpenAI responses
- return normalized text/errors

## Provider Interface

Each provider module should expose the same shape.

Suggested interface:

```lua
provider.build_payload(request, resolved_type, config)
provider.execute(payload, runtime, config)
provider.parse_response(raw_result)
provider.normalize_error(raw_result)
```

Or, more simply:

```lua
provider.perform(request, resolved_type, runtime, config)
```

Returning:

```lua
{
  ok = true,
  response_text = "...",
  raw_response = "..."
}
```

or:

```lua
{
  ok = false,
  error_message = "...",
  raw_response = "..."
}
```

The simpler `perform(...)` interface is probably the best first step.

## Database Direction

We should keep SQLite, but treat it as cache and metadata storage rather than as a live browser-state source.

Suggested tables:

- `prompt_library`
- `providers`
- `request_types`
- `requests`

Suggested responsibilities:

- `prompt_library`: prompt templates by slug
- `providers`: provider definitions like `openai`
- `request_types`: links prompt + provider + defaults
- `requests`: cached executions and provider outputs

Useful `requests` fields:

- `id`
- `request_hash`
- `request_type_id`
- `selection_text`
- `body`
- `model`
- `state`
- `response`
- `raw_response`
- `error_message`
- `created_at`
- `updated_at`

## Cache Policy

Desired behavior:

- if matching `complete` exists, reuse it
- otherwise call the provider and store the fresh result

## HTML Direction

Templates and CSS should stay outside Lua code.

Lua should inject structured values into:

- loading page template
- request page template

The browser should center on one stable output file:

- `latest_ai_answer.html`

## Shell Boundary

Shell should remain only for:

- NickelMenu entrypoints
- launching the Lua app
- very small compatibility glue

All request logic, DB logic, rendering decisions, and provider code should move into Lua.

## Migration Plan

1. Add bundled Lua runtime detection and a tiny Lua launcher.
2. Scaffold the Lua module tree without changing the user-visible flow.
3. Port runtime/config/log/db helpers first.
4. Port the single-page `run` flow.
5. Keep shell as a minimal launcher during transition.
6. Remove old shell-heavy logic once Lua behavior is stable on-device.

## Non-Goals For First Pass

- No full plugin system yet
- No multiple providers on day one, beyond designing for them
- No database engine change away from SQLite
- No KOReader integration dependency

## Summary

The main architectural choice is:

- shell becomes a launcher
- Lua becomes the application
- SQLite remains the cache layer
- providers become swappable modules

That gives us a cleaner path to support OpenAI now and other LLM backends later without rewriting the request lifecycle again.
