local M = {}

local function trim(value)
  return (value or ""):gsub("%s+$", "")
end

local function sql_escape(value)
  return tostring(value):gsub("'", "''")
end

function M.hash_request(model_name, request_body)
  local payload = string.format("%s\n%s", model_name or "", request_body or "")
  local command = "printf %s " .. "'" .. payload:gsub("'", "'\\''") .. "'"
    .. " | sha256sum | awk '{print $1}'"
  local handle = io.popen(command, "r")
  if not handle then
    error("failed to compute request hash")
  end
  local output = handle:read("*a")
  handle:close()
  return trim(output)
end

function M.find_cached_complete_request(database, request_hash)
  local row = database:one(string.format([[
    SELECT
      id,
      state,
      selection_text,
      response,
      error_message,
      raw_response
    FROM requests
    WHERE request_hash = '%s'
      AND state = 'complete'
    ORDER BY id DESC
    LIMIT 1;
  ]], sql_escape(request_hash)))

  if not row then
    return nil
  end

  return {
    id = tonumber(row.id),
    state = row.state,
    selection_text = row.selection_text,
    response = row.response,
    error_message = row.error_message,
    raw_response = row.raw_response,
  }
end

function M.insert_request(database, request_hash, request_type_id, selection_text, request_body, model_name, state)
  local initial_state = state or "queued"
  local row = database:one(string.format([[
    INSERT INTO requests (
      request_hash,
      request_type_id,
      selection_text,
      body,
      model,
      state
    ) VALUES (
      '%s',
      %d,
      '%s',
      '%s',
      '%s',
      '%s'
    )
    RETURNING id, state;
  ]],
    sql_escape(request_hash),
    tonumber(request_type_id),
    sql_escape(selection_text),
    sql_escape(request_body),
    sql_escape(model_name),
    sql_escape(initial_state)))

  if not row then
    error("failed to insert request")
  end

  return {
    id = tonumber(row.id),
    state = row.state,
  }
end

function M.count_requests(database)
  local row = database:one("SELECT COUNT(*) AS count FROM requests;")
  return tonumber(row and row.count or 0)
end

function M.fetch_request(database, request_id)
  local row = database:one(string.format([[
    SELECT
      id,
      request_hash,
      request_type_id,
      selection_text,
      body,
      model,
      state,
      response,
      raw_response,
      error_message
    FROM requests
    WHERE id = %d
    LIMIT 1;
  ]], tonumber(request_id)))

  if not row then
    return nil
  end

  return {
    id = tonumber(row.id),
    request_hash = row.request_hash,
    request_type_id = tonumber(row.request_type_id),
    selection_text = row.selection_text,
    body = row.body,
    model = row.model,
    state = row.state,
    response = row.response,
    raw_response = row.raw_response,
    error_message = row.error_message,
  }
end

function M.complete_request(database, request_id, response_text, raw_response)
  database:exec(string.format([[
    UPDATE requests
    SET state = 'complete',
        response = '%s',
        raw_response = '%s',
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = %d;
  ]],
    sql_escape(response_text or ""),
    sql_escape(raw_response or ""),
    tonumber(request_id)))
end

function M.error_request(database, request_id, error_message, raw_response)
  database:exec(string.format([[
    UPDATE requests
    SET state = 'error',
        error_message = '%s',
        raw_response = '%s',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = %d;
  ]],
    sql_escape(error_message or ""),
    sql_escape(raw_response or ""),
    tonumber(request_id)))
end

return M
