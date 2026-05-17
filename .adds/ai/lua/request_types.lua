local M = {}

local function sql_escape(value)
  return tostring(value):gsub("'", "''")
end

function M.seed_defaults(database, cfg)
  database:exec([[
    INSERT OR IGNORE INTO providers (name, description)
    VALUES ('openai', 'OpenAI Responses API provider');

    INSERT OR IGNORE INTO providers (name, description)
    VALUES ('mock', 'Mock provider used for local Lua tests');
  ]])

  database:exec(string.format([[
    INSERT OR IGNORE INTO request_types (name, description, prompt_id, provider_id, model_override)
    SELECT
      'explain_selection',
      'Explain a highlighted book passage in simple language.',
      p.id,
      pr.id,
      '%s'
    FROM prompt_library p, providers pr
    WHERE p.slug = 'explain_selection_default'
      AND pr.name = '%s';

    UPDATE request_types
    SET model_override = '%s',
        updated_at = CURRENT_TIMESTAMP
    WHERE name = 'explain_selection';
  ]], sql_escape(cfg.openai_model), sql_escape(cfg.default_provider), sql_escape(cfg.openai_model)))
end

function M.runtime_default(cfg)
  return {
    -- The current addon seeds a single default request type, explain_selection.
    -- For the live request path, we derive this from config instead of reading
    -- it back through the multiline-unsafe sqlite CLI adapter.
    id = 1,
    name = cfg.default_request_type or "explain_selection",
    description = "Explain a highlighted book passage in simple language.",
    model = cfg.openai_model,
    provider_name = cfg.default_provider or "openai",
  }
end

function M.resolve(database, type_name)
  local row = database:one(string.format([[
    SELECT
      rt.id,
      rt.name,
      rt.description,
      rt.model_override,
      pr.name AS provider_name
    FROM request_types rt
    JOIN providers pr ON pr.id = rt.provider_id
    WHERE rt.name = '%s'
    LIMIT 1;
  ]], sql_escape(type_name)))

  if not row then
    error("request type not found: " .. tostring(type_name))
  end

  return {
    id = tonumber(row.id),
    name = row.name,
    description = row.description,
    model = row.model_override,
    provider_name = row.provider_name,
  }
end

return M
