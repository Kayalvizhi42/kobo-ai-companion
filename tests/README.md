# Tests

This directory holds local test helpers for the current Lua architecture.

Current test:

- `test_lua_run_flow.sh`
  Creates a temporary addon directory and exercises the new single-page Lua architecture:
  - one backend run both updates the cache DB and overwrites `latest_ai_answer.html`
  - the second identical run is served from cache
  - the DB is used as cache, not as a live browser-state store

Run it from the repo root:

```sh
sh tests/test_lua_run_flow.sh
```
