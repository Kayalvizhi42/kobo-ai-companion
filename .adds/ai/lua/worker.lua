local providers = require("providers")

local M = {}

function M.process_request(request, resolved_type, rt, cfg)
  local provider = providers.get(resolved_type.provider_name)
  return provider.perform(request, resolved_type, rt, cfg)
end

return M
