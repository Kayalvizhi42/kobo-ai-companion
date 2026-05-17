local M = {}

function M.perform(request, resolved_type, rt, cfg)
  local response_text = os.getenv("ASK_AI_MOCK_RESPONSE")
    or ("Mock explanation for request " .. tostring(request.id))

  return {
    ok = true,
    response_text = response_text,
    raw_response = string.format(
      '{"provider":"%s","request_id":%d,"model":"%s"}',
      tostring(resolved_type.provider_name),
      tonumber(request.id),
      tostring(resolved_type.model or cfg.openai_model)
    ),
  }
end

return M
