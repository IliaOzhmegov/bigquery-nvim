-- Best-effort integration with vim-dadbod-ui.
--
-- vim-dadbod-ui hard-codes the BigQuery table-listing query to
-- INFORMATION_SCHEMA.TABLES which requires project-level permissions.
-- This module fetches the same data via `bq ls` (dataset-level permissions
-- are enough) and writes it into DBUI's JSON schema cache so the sidebar
-- shows tables correctly.
--
-- Usage:
--   :BigQuerySyncDBUI [project]   -- manual sync
--   setup({ dadbod = { auto_populate = true } })  -- auto-sync on DBUIOpened
local M = {}
local bq = require("bigquery.bq")

-- DBUI default schema-cache directory (matches vim-dadbod-ui source).
local function queries_path()
  if vim.g.db_ui_tmp_query_location then
    return vim.fn.expand(vim.g.db_ui_tmp_query_location)
  end
  local xdg = os.getenv("XDG_DATA_HOME")
  local base = xdg or (vim.fn.expand("~") .. "/.local/share")
  return base .. "/nvim/db_ui_queries"
end

-- DBUI expects: { "dataset_name": ["table1", "table2", ...], ... }
local function build_json(datasets_tables)
  local out = {}
  for ds, tables in pairs(datasets_tables) do
    local names = {}
    for _, t in ipairs(tables) do
      names[#names + 1] = t.id
    end
    out[ds] = names
  end
  return vim.json.encode(out)
end

-- Scan the cache dir for an existing BigQuery cache file.
-- DBUI names files after the connection key; we match on content / filename.
local function find_existing(dir, project)
  if vim.fn.isdirectory(dir) == 0 then return nil end
  local slug = project:lower():gsub("[^%w%-]", "_")
  local candidates = vim.fn.glob(dir .. "/*.json", false, true)
  for _, f in ipairs(candidates) do
    local base = vim.fn.fnamemodify(f, ":t:r"):lower()
    if base:find("bigquery", 1, true) or base:find(slug, 1, true) then
      return f
    end
  end
  return nil
end

local function write_cache(project, datasets_tables)
  local json = build_json(datasets_tables)
  local dir  = queries_path()
  vim.fn.mkdir(dir, "p")

  local target = find_existing(dir, project)
  if not target then
    local slug = project:lower():gsub("[^%w%-]", "_")
    target = dir .. "/bigquery_" .. slug .. ".json"
  end

  vim.fn.writefile({ json }, target)
  return target
end

--- Fetch all datasets + their tables for `project`, then write the cache.
--- cb(err, datasets_tables)  -- optional
function M.populate(project, opts, cb)
  opts = opts or {}
  cb   = cb or function() end

  bq.list_datasets(project, function(err, datasets)
    if err then
      vim.notify("[bigquery] dadbod: " .. err, vim.log.levels.WARN)
      cb(err)
      return
    end
    if #datasets == 0 then
      vim.notify("[bigquery] dadbod: no datasets found in " .. project, vim.log.levels.WARN)
      cb(nil, {})
      return
    end

    local collected = {}
    local pending   = #datasets

    for _, ds in ipairs(datasets) do
      bq.list_tables(project, ds, function(terr, tables)
        if not terr then collected[ds] = tables or {} end
        pending = pending - 1
        if pending == 0 then
          local target = write_cache(project, collected)
          vim.notify("[bigquery] wrote DBUI schema cache → " .. target, vim.log.levels.INFO)
          -- Ask DBUI to refresh its sidebar if it is currently open.
          if vim.fn.exists(":DBUIRefreshSchemas") == 2 then
            pcall(vim.cmd, "DBUIRefreshSchemas")
          end
          cb(nil, collected)
        end
      end)
    end
  end)
end

--- Register autocmd to auto-populate on DBUIOpened (requires auto_populate = true).
function M.setup()
  local cfg = require("bigquery.config").options
  if not (cfg.dadbod.auto_populate and cfg.project) then return end

  vim.api.nvim_create_autocmd("User", {
    pattern  = "DBUIOpened",
    callback = function()
      M.populate(cfg.project, {})
    end,
  })
end

return M
