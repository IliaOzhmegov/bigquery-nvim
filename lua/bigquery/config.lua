local M = {}

M.options = {
  project   = nil,
  cache_ttl = 300,
  dadbod = {
    enabled      = true,
    auto_populate = false,
  },
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
