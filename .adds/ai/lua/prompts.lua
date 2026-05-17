local runtime = require("runtime")

local M = {}

local PROMPT_SLUG = "explain_selection_default"

local function sql_escape(value)
  return tostring(value):gsub("'", "''")
end

function M.seed_default(database, cfg)
  local template_body, err = runtime.read_file(cfg.prompt_template)
  if not template_body then
    error("could not read prompt template: " .. tostring(err))
  end

  database:exec(string.format([[
    INSERT OR IGNORE INTO prompt_library (slug, title, template_body)
    VALUES ('%s', 'Explain Selection', '%s');

    UPDATE prompt_library
    SET title = 'Explain Selection',
        template_body = '%s',
        updated_at = CURRENT_TIMESTAMP
    WHERE slug = '%s';
  ]], sql_escape(PROMPT_SLUG), sql_escape(template_body), sql_escape(template_body), sql_escape(PROMPT_SLUG)))
end

function M.render_selection_prompt_from_file(template_path, selection_text)
  local template_body, err = runtime.read_file(template_path)
  if not template_body then
    error("could not read prompt template: " .. tostring(err))
  end

  return template_body:gsub("{{SELECTED_TEXT}}", selection_text)
end

function M.template_for_type(database, type_name)
  local row = database:one(string.format([[
    SELECT p.template_body
    FROM request_types rt
    JOIN prompt_library p ON p.id = rt.prompt_id
    WHERE rt.name = '%s'
    LIMIT 1;
  ]], sql_escape(type_name)))

  return row and row.template_body or nil
end

function M.render_selection_prompt(database, type_name, selection_text)
  local template = M.template_for_type(database, type_name)
  if not template then
    error("prompt template not found for request type " .. tostring(type_name))
  end

  return template:gsub("{{SELECTED_TEXT}}", selection_text)
end

return M
