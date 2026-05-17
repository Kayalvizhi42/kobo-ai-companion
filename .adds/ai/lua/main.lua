local runtime = require("runtime")
local config = require("config")
local log = require("log")
local db = require("db")
local prompts = require("prompts")
local request_types = require("request_types")
local requests = require("requests")
local render = require("render")
local worker = require("worker")

local app = {}

local function bootstrap_context()
  local rt = runtime.build()
  local cfg = config.load(rt)
  local database = db.new(rt)
  return rt, cfg, database
end

local function ensure_basics(database, cfg)
  database:init_schema()
  prompts.seed_default(database, cfg)
  request_types.seed_defaults(database, cfg)
end

function app.runtime_info()
  local rt, cfg, database = bootstrap_context()
  database:close()

  io.write("runtime=", rt.lua_bin or "unknown", "\n")
  io.write("db=", rt.db_file, "\n")
  io.write("sqlite3=", rt.sqlite3_bin or "missing", "\n")
  io.write("curl=", rt.curl_bin or "missing", "\n")
  io.write("backend=", cfg.ask_ai_backend, "\n")
  io.write("provider=", cfg.default_provider, "\n")
  io.write("model=", cfg.openai_model, "\n")
end

function app.run(selection_text)
  local rt, cfg, database = bootstrap_context()
  ensure_basics(database, cfg)

  if not selection_text or selection_text == "" then
    render.write_latest_page(rt, render.render_simple_error_page("No selected text was received."))
    database:close()
    error("no selected text was provided")
  end

  local resolved_type = request_types.runtime_default(cfg)
  local prompt_body = prompts.render_selection_prompt_from_file(cfg.prompt_template, selection_text)
  local model_name = resolved_type.model or cfg.openai_model
  local request_hash = requests.hash_request(model_name, prompt_body)
  local cached_request = requests.find_cached_complete_request(database, request_hash)

  if cached_request then
    log.info(rt, "Lua run reused cached request " .. cached_request.id .. " for hash " .. request_hash)
    render.write_latest_page(rt, render.render_result_page(rt, {
      request_id = cached_request.id,
      state = "complete",
      status_label = "cached",
      status_body = "Served from cache.",
      selection_text = cached_request.selection_text or selection_text,
      response = cached_request.response or "",
    }))
    io.write("request_id=", tostring(cached_request.id), "\n")
    io.write("request_state=complete\n")
    io.write("cache_hit=1\n")
    database:close()
    return
  end

  local request_record = requests.insert_request(
    database,
    request_hash,
    resolved_type.id,
    selection_text,
    prompt_body,
    model_name,
    "processing"
  )

  local request = {
    id = request_record.id,
    request_hash = request_hash,
    request_type_id = resolved_type.id,
    selection_text = selection_text,
    body = prompt_body,
    model = model_name,
    state = request_record.state,
  }
  local result = worker.process_request(request, resolved_type, rt, cfg)

  if result.ok then
    requests.complete_request(database, request_record.id, result.response_text, result.raw_response)
    render.write_latest_page(rt, render.render_result_page(rt, {
      request_id = request_record.id,
      state = "complete",
      selection_text = selection_text,
      response = result.response_text,
    }))
    log.info(rt, "Lua run completed request " .. tostring(request_record.id))
    io.write("request_id=", tostring(request_record.id), "\n")
    io.write("request_state=complete\n")
    io.write("cache_hit=0\n")
  else
    requests.error_request(database, request_record.id, result.error_message, result.raw_response)
    render.write_latest_page(rt, render.render_result_page(rt, {
      request_id = request_record.id,
      state = "error",
      selection_text = selection_text,
      error_message = result.error_message,
    }))
    log.error(rt, "Lua run failed request " .. tostring(request_record.id) .. ": " .. tostring(result.error_message))
    io.write("request_id=", tostring(request_record.id), "\n")
    io.write("request_state=error\n")
    io.write("cache_hit=0\n")
  end

  database:close()
end

function app.prepare(selection_text)
  local rt = runtime.build()
  runtime.ensure_dirs(rt)
  render.write_latest_page(rt, render.render_loading_page(rt, "Generating response..."))

  if not selection_text or selection_text == "" then
    render.write_latest_page(rt, render.render_simple_error_page("No selected text was received."))
    error("no selected text was provided")
  end
end

function app.debug()
  local rt, cfg, database = bootstrap_context()
  ensure_basics(database, cfg)
  local row = database:one("SELECT COUNT(*) AS count FROM requests;")
  database:close()
  io.write("requests_count=", row and row.count or "0", "\n")
end

local command = arg[1]

if command == "runtime-info" then
  app.runtime_info()
elseif command == "prepare" then
  app.prepare(arg[2])
elseif command == "open" then
  app.prepare(arg[2])
elseif command == "run" then
  app.run(arg[2])
elseif command == "debug" then
  app.debug()
else
  io.stderr:write("Usage: main.lua [runtime-info|prepare|open|run|debug] [arg]\n")
  os.exit(1)
end
