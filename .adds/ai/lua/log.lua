local runtime = require("runtime")

local M = {}

local function utc_timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function append(rt, level, message)
  runtime.ensure_dirs(rt)
  local handle = io.open(rt.log_file, "ab")
  if not handle then
    return
  end
  handle:write(string.format("%s %s: %s\n", utc_timestamp(), level, tostring(message)))
  handle:close()
end

function M.info(rt, message)
  append(rt, "INFO", message)
end

function M.error(rt, message)
  append(rt, "ERROR", message)
end

return M
