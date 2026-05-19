local M = {}

--- Configure the plugin.
--- @param opts table
--- @field project string  GCP project ID (e.g. "beyond-data-dev")
--- @field cache_ttl? number  seconds to cache bq ls results (default 300)
--- @field dadbod? { enabled?: boolean, auto_populate?: boolean }
function M.setup(opts)
  require("bigquery.config").setup(opts)

  -- Highlight groups (link to standard groups; user's colorscheme wins)
  local hl = vim.api.nvim_set_hl
  hl(0, "BigQueryProject", { link = "Title",     default = true })
  hl(0, "BigQueryDataset", { link = "Directory", default = true })
  hl(0, "BigQueryTable",   { link = "Normal",    default = true })
  hl(0, "BigQueryView",    { link = "Comment",   default = true })

  local cfg = require("bigquery.config").options
  if cfg.dadbod.enabled then
    require("bigquery.sync").setup()
  end
end

--- Open the BigQuery tree browser.
--- @param project? string  overrides config.project
function M.browse(project)
  require("bigquery.browser").open(project)
end

--- Toggle the tree browser open/closed.
--- @param project? string
function M.toggle(project)
  require("bigquery.browser").toggle(project)
end

--- Populate vim-dadbod-ui's schema cache with tables fetched via `bq ls`.
--- @param project? string  overrides config.project
function M.sync_dbui(project)
  local cfg = require("bigquery.config").options
  project = project or cfg.project
  if not project then
    vim.notify("[bigquery] sync_dbui: no project — pass one or set it in setup()",
      vim.log.levels.ERROR)
    return
  end
  vim.notify("[bigquery] fetching schema for " .. project .. " …", vim.log.levels.INFO)
  require("bigquery.sync").populate(project, {})
end

return M
