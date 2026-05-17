local runtime = require("runtime")

local M = {}

local function replace_tokens(template, replacements)
  local rendered = template
  for key, value in pairs(replacements) do
    rendered = rendered:gsub("{{" .. key .. "}}", function()
      return value or ""
    end)
  end
  return rendered
end

local function read_template(path, label)
  local template, err = runtime.read_file(path)
  if not template then
    error("could not read " .. label .. ": " .. tostring(err))
  end
  return template
end

function M.render_request_page(rt, data)
  local template = read_template(rt.request_template, "request template")
  local css = read_template(rt.page_styles, "page styles")

  return replace_tokens(template, {
    PAGE_CSS = css,
    REFRESH_LINE = data.refresh_line or "",
    REQUEST_META = data.meta or "",
    RESULT_CARD_BLOCK = data.result_block or "",
    SELECTION_HTML = data.selection_html or "",
  })
end

function M.render_loading_page(rt, status_message)
  local template = read_template(rt.loading_template, "loading template")
  local css = read_template(rt.page_styles, "page styles")

  return replace_tokens(template, {
    PAGE_CSS = css,
    STATUS_MESSAGE = runtime.html_escape(status_message or "Generating response..."),
  })
end

function M.render_simple_error_page(message)
  return "<html><head><meta charset='utf-8'><title>Ask AI</title></head><body>"
    .. "<p>" .. runtime.html_escape(message or "Unknown error.") .. "</p>"
    .. "</body></html>"
end

function M.render_result_block(state, text_html)
  if state == "complete" then
    return "<details class='card collapsible'>\n"
      .. "<summary><span class='summary-arrow'>▾</span><span class='summary-title'>Simple Explanation</span></summary>\n"
      .. "<pre>" .. (text_html or "") .. "</pre>\n"
      .. "</details>"
  end

  if state == "error" then
    return "<details class='card collapsible'>\n"
      .. "<summary><span class='summary-arrow'>▾</span><span class='summary-title'>Details</span></summary>\n"
      .. "<pre>" .. (text_html or "") .. "</pre>\n"
      .. "</details>"
  end

  return ""
end

function M.render_result_page(rt, options)
  local state = options.state or "complete"
  local status_label = options.status_label
  local status_body = options.status_body

  if not status_label then
    if state == "complete" then
      status_label = "complete"
      status_body = status_body or "Your explanation is ready."
    elseif state == "error" then
      status_label = "error"
      status_body = status_body or options.error_message or "Unknown error."
    else
      status_label = state
      status_body = status_body or ""
    end
  end

  local result_text = ""
  if state == "complete" then
    result_text = options.response or ""
  elseif state == "error" then
    result_text = options.error_message or ""
  end

  local meta = options.meta
  if not meta then
    local id_part = options.request_id and ("Request #" .. tostring(options.request_id) .. " | ") or ""
    meta = id_part .. status_label .. " | " .. runtime.html_escape(status_body or "")
  end

  return M.render_request_page(rt, {
    refresh_line = options.refresh_line or "",
    meta = meta,
    selection_html = runtime.html_escape(options.selection_text or ""),
    result_block = M.render_result_block(state, runtime.html_escape(result_text)),
  })
end

function M.write_file(path, content)
  local ok, err = runtime.write_file(path, content)
  if not ok then
    error("could not write file: " .. tostring(err))
  end
end

function M.write_latest_page(rt, content)
  M.write_file(rt.answer_index_file, content)
end

return M
