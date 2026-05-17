local M = {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function json_escape(value)
  return tostring(value or "")
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
end

local function write_file(path, content)
  local handle, err = io.open(path, "wb")
  if not handle then
    return nil, err
  end
  handle:write(content)
  handle:close()
  return true
end

local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function first_nonempty(...)
  for index = 1, select("#", ...) do
    local value = select(index, ...)
    if value and value ~= "" then
      return value
    end
  end
  return nil
end

local function extract_json_string(payload, key)
  local start_pos = payload:find('"' .. key .. '"', 1, true)
  if not start_pos then
    return nil
  end

  local colon_pos = payload:find(":", start_pos, true)
  if not colon_pos then
    return nil
  end

  local index = colon_pos + 1
  while index <= #payload and payload:sub(index, index):match("%s") do
    index = index + 1
  end

  if payload:sub(index, index) ~= '"' then
    return nil
  end

  index = index + 1
  local parts = {}
  local escaped = false

  while index <= #payload do
    local ch = payload:sub(index, index)
    if escaped then
      if ch == "n" then
        table.insert(parts, "\n")
      elseif ch == "r" then
        table.insert(parts, "\r")
      elseif ch == "t" then
        table.insert(parts, "\t")
      else
        table.insert(parts, ch)
      end
      escaped = false
    elseif ch == "\\" then
      escaped = true
    elseif ch == '"' then
      return table.concat(parts)
    else
      table.insert(parts, ch)
    end
    index = index + 1
  end

  return nil
end

local function extract_response_text(raw_response)
  return first_nonempty(
    extract_json_string(raw_response, "output_text"),
    extract_json_string(raw_response, "text")
  )
end

function M.perform(request, resolved_type, rt, cfg)
  if not cfg.openai_api_key or cfg.openai_api_key == "" then
    return {
      ok = false,
      error_message = "OPENAI_API_KEY is empty.",
      raw_response = "",
    }
  end

  if not rt.curl_bin then
    return {
      ok = false,
      error_message = "curl runtime not found.",
      raw_response = "",
    }
  end

  if not rt.cert_file or not read_file(rt.cert_file) then
    return {
      ok = false,
      error_message = "CA bundle not found.",
      raw_response = "",
    }
  end

  local request_id = tostring(request.id)
  local json_file = rt.tmp_dir .. "/request_" .. request_id .. ".json"
  local raw_file = rt.tmp_dir .. "/request_" .. request_id .. "_raw.json"
  local http_file = rt.tmp_dir .. "/request_" .. request_id .. "_http.code"
  local err_file = rt.tmp_dir .. "/request_" .. request_id .. "_curl.err"
  local model_name = resolved_type.model or cfg.openai_model

  local payload = string.format(
    '{"model":"%s","input":"%s"}',
    json_escape(model_name),
    json_escape(request.body or "")
  )

  local ok, err = write_file(json_file, payload)
  if not ok then
    return {
      ok = false,
      error_message = "Failed to write OpenAI payload: " .. tostring(err),
      raw_response = "",
    }
  end

  write_file(err_file, "")

  local command = table.concat({
    shell_quote(rt.curl_bin),
    "-sS",
    "-o", shell_quote(raw_file),
    "-w", shell_quote("%{http_code}"),
    shell_quote("https://api.openai.com/v1/responses"),
    "--cacert", shell_quote(rt.cert_file),
    "-H", shell_quote("Authorization: Bearer " .. cfg.openai_api_key),
    "-H", shell_quote("Content-Type: application/json"),
    "-d", "@" .. shell_quote(json_file),
    ">" .. shell_quote(http_file),
    "2>" .. shell_quote(err_file),
  }, " ")

  local exec_ok, _, exit_code = os.execute(command)
  local curl_ok = exec_ok == true or exec_ok == 0
  local http_code = (read_file(http_file) or ""):gsub("%s+$", "")
  local raw_response = read_file(raw_file) or ""
  local curl_error = read_file(err_file) or ""

  if not curl_ok then
    return {
      ok = false,
      error_message = first_nonempty(curl_error:match("^([^\n]+)"), "curl exited with status " .. tostring(exit_code) .. "."),
      raw_response = raw_response,
    }
  end

  if http_code ~= "200" and http_code ~= "201" then
    return {
      ok = false,
      error_message = "OpenAI API returned HTTP " .. tostring(http_code) .. ".",
      raw_response = raw_response,
    }
  end

  local response_text = extract_response_text(raw_response or "")
  if not response_text or response_text == "" then
    return {
      ok = false,
      error_message = "Could not extract response text from the OpenAI response.",
      raw_response = raw_response,
    }
  end

  return {
    ok = true,
    response_text = response_text,
    raw_response = raw_response,
  }
end

return M
