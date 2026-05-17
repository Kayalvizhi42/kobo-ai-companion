local runtime = require("runtime")

local Database = {}
Database.__index = Database

local function trim_trailing_newline(value)
  return (value or ""):gsub("%s+$", "")
end

local function parse_tsv_line(line, headers)
  local row = {}
  local index = 1
  for field in (line .. "\t"):gmatch("(.-)\t") do
    row[headers[index]] = field
    index = index + 1
  end
  return row
end

function Database:_run(sql, mode)
  if not self.sqlite3_bin then
    error("sqlite3 runtime not found")
  end

  local input = (mode or "")
    .. "\n"
    .. sql
    .. "\n"
  local command = "printf %s "
    .. runtime.shell_quote(input)
    .. " | "
    .. runtime.shell_quote(self.sqlite3_bin)
    .. " "
    .. runtime.shell_quote(self.db_file)

  local handle = io.popen(command, "r")
  if not handle then
    error("failed to open sqlite3 process")
  end

  local output = handle:read("*a")
  local ok, _, exit_code = handle:close()
  if ok == nil or exit_code ~= 0 then
    error("sqlite3 command failed")
  end

  return output
end

function Database:exec(sql)
  self:_run(sql, "")
  return true
end

function Database:one(sql)
  local output = self:_run(sql, ".mode tabs\n.headers on")
  output = trim_trailing_newline(output)
  if output == "" then
    return nil
  end

  local lines = {}
  for line in output:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  if #lines < 2 then
    return nil
  end

  local headers = {}
  for field in (lines[1] .. "\t"):gmatch("(.-)\t") do
    table.insert(headers, field)
  end

  return parse_tsv_line(lines[2], headers)
end

function Database:all(sql)
  local output = self:_run(sql, ".mode tabs\n.headers on")
  output = trim_trailing_newline(output)
  if output == "" then
    return {}
  end

  local lines = {}
  for line in output:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  if #lines < 2 then
    return {}
  end

  local headers = {}
  for field in (lines[1] .. "\t"):gmatch("(.-)\t") do
    table.insert(headers, field)
  end

  local rows = {}
  for index = 2, #lines do
    table.insert(rows, parse_tsv_line(lines[index], headers))
  end
  return rows
end

function Database:init_schema()
  self:exec([[
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS prompt_library (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  template_body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS providers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS request_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  prompt_id INTEGER NOT NULL REFERENCES prompt_library(id),
  provider_id INTEGER NOT NULL REFERENCES providers(id),
  model_override TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_hash TEXT NOT NULL,
  request_type_id INTEGER NOT NULL REFERENCES request_types(id),
  selection_text TEXT NOT NULL,
  body TEXT NOT NULL,
  model TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('queued', 'processing', 'complete', 'error')),
  response TEXT,
  raw_response TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_requests_hash_state
  ON requests(request_hash, state);

CREATE INDEX IF NOT EXISTS idx_requests_state_created
  ON requests(state, created_at);
]])
end

function Database:close()
  return true
end

local M = {}

function M.new(rt)
  runtime.ensure_dirs(rt)

  local instance = {
    db_file = rt.db_file,
    sqlite3_bin = rt.sqlite3_bin,
  }

  return setmetatable(instance, Database)
end

return M
