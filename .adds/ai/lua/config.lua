local M = {}

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function parse_env_line(line)
  if line:match("^%s*$") or line:match("^%s*#") then
    return nil, nil
  end

  local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
  if not key then
    return nil, nil
  end

  value = trim(value)
  if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
    value = value:sub(2, -2)
  elseif value:sub(1, 1) == "'" and value:sub(-1) == "'" then
    value = value:sub(2, -2)
  end

  value = value:gsub('\\"', '"')
  return key, value
end

function M.load(rt)
  local cfg = {
    ask_ai_backend = "lua",
    default_provider = "openai",
    default_request_type = "explain_selection",
    openai_model = "gpt-4.1-mini",
    prompt_template = rt.prompt_template,
  }

  local handle = io.open(rt.config_file, "rb")
  if not handle then
    return cfg
  end

  for line in handle:lines() do
    local key, value = parse_env_line(line)
    if key then
      cfg[key:lower()] = value
    end
  end

  handle:close()

  cfg.ask_ai_backend = cfg.ask_ai_backend or "lua"
  cfg.default_provider = cfg.default_provider or "openai"
  cfg.default_request_type = cfg.default_request_type or "explain_selection"
  cfg.openai_model = cfg.openai_model or cfg.model or "gpt-4.1-mini"
  cfg.prompt_template = cfg.prompt_template or rt.prompt_template

  return cfg
end

return M
