#!/bin/sh

BASE_DIR="/mnt/onboard/.adds/ai"
LUA_DIR="$BASE_DIR/lua"
BIN_DIR="/mnt/onboard/.adds/bin"

find_lua_runtime() {
  for candidate in \
    "$BIN_DIR/luajit" \
    "$BIN_DIR/lua" \
    /usr/bin/luajit \
    /usr/bin/lua \
    /bin/luajit \
    /bin/lua \
    /usr/local/bin/luajit \
    /usr/local/bin/lua
  do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  if command -v luajit >/dev/null 2>&1; then
    command -v luajit
    return 0
  fi

  if command -v lua >/dev/null 2>&1; then
    command -v lua
    return 0
  fi

  return 1
}

LUA_BIN="$(find_lua_runtime)"
if [ -z "$LUA_BIN" ]; then
  echo "ERROR: no Lua runtime found. Expected .adds/bin/luajit or .adds/bin/lua." >&2
  exit 1
fi

LUA_PATH_PREFIX="$LUA_DIR/?.lua;$LUA_DIR/?/init.lua"
if [ -n "$LUA_PATH" ]; then
  export LUA_PATH="$LUA_PATH_PREFIX;$LUA_PATH"
else
  export LUA_PATH="$LUA_PATH_PREFIX;;"
fi

exec "$LUA_BIN" "$LUA_DIR/main.lua" "$@"
