local M = {}

local provider_map = {
  mock = require("providers.mock"),
  openai = require("providers.openai"),
}

function M.get(name)
  local provider = provider_map[name]
  if not provider then
    error("provider not found: " .. tostring(name))
  end
  return provider
end

return M
