local M = {}

local function env(name, default)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return default
  end
  return value
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function is_executable(path)
  local ok = os.execute("[ -x " .. shell_quote(path) .. " ] >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function command_exists(name)
  local handle = io.popen("command -v " .. name .. " 2>/dev/null")
  if not handle then
    return nil
  end

  local output = handle:read("*a")
  handle:close()
  output = output:gsub("%s+$", "")
  if output == "" then
    return nil
  end
  return output
end

local function first_executable(candidates)
  for _, path in ipairs(candidates) do
    if is_executable(path) then
      return path
    end
  end
  return nil
end

function M.detect_lua_runtime()
  return first_executable({
    "/mnt/onboard/.adds/bin/luajit",
    "/mnt/onboard/.adds/bin/lua",
    "/usr/bin/luajit",
    "/usr/bin/lua",
    "/bin/luajit",
    "/bin/lua",
    "/usr/local/bin/luajit",
    "/usr/local/bin/lua",
  }) or command_exists("luajit") or command_exists("lua")
end

function M.detect_sqlite3()
  return first_executable({
    "/mnt/onboard/.adds/bin/sqlite3",
    "/usr/bin/sqlite3",
    "/bin/sqlite3",
    "/usr/local/bin/sqlite3",
  }) or command_exists("sqlite3")
end

function M.detect_curl()
  return first_executable({
    "/mnt/onboard/.adds/bin/curl",
    "/usr/bin/curl",
    "/bin/curl",
    "/usr/local/bin/curl",
  }) or command_exists("curl")
end

function M.build()
  local base_dir = env("ASK_AI_BASE_DIR", "/mnt/onboard/.adds/ai")
  local state_dir = env("ASK_AI_STATE_DIR", base_dir)
  local cert_dir = env("ASK_AI_CERT_DIR", "/mnt/onboard/.adds/certs")
  local sqlite3_bin = env("ASK_AI_SQLITE3_BIN", M.detect_sqlite3())
  local curl_bin = env("ASK_AI_CURL_BIN", M.detect_curl())
  local lua_bin = env("ASK_AI_LUA_BIN", M.detect_lua_runtime())

  return {
    base_dir = base_dir,
    state_dir = state_dir,
    lua_dir = base_dir .. "/lua",
    template_dir = base_dir,
    config_file = base_dir .. "/config.env",
    db_file = state_dir .. "/requests.db",
    output_dir = base_dir .. "/output",
    tmp_dir = state_dir .. "/tmp",
    log_dir = state_dir .. "/logs",
    log_file = state_dir .. "/logs/ai_activity.log",
    prompt_template = base_dir .. "/prompt_template.tmpl",
    page_styles = base_dir .. "/page_styles.css",
    loading_template = base_dir .. "/loading_page.html.tmpl",
    request_template = base_dir .. "/request_page.html.tmpl",
    answer_index_file = base_dir .. "/output/latest_ai_answer.html",
    runner_script = base_dir .. "/run_lua_backend.sh",
    cert_file = cert_dir .. "/cacert.pem",
    lua_bin = lua_bin,
    sqlite3_bin = sqlite3_bin,
    curl_bin = curl_bin,
  }
end

function M.sleep(seconds)
  os.execute("sleep " .. tostring(seconds))
end

function M.ensure_dirs(rt)
  os.execute("mkdir -p "
    .. shell_quote(rt.output_dir) .. " "
    .. shell_quote(rt.tmp_dir) .. " "
    .. shell_quote(rt.log_dir))
end

function M.read_file(path)
  local handle, err = io.open(path, "rb")
  if not handle then
    return nil, err
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

function M.write_file(path, content)
  local handle, err = io.open(path, "wb")
  if not handle then
    return nil, err
  end
  handle:write(content)
  handle:close()
  return true
end

function M.shell_quote(value)
  return shell_quote(value)
end

function M.html_escape(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
end

return M
