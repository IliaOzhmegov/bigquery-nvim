-- :checkhealth bigquery
local M = {}

function M.check()
  vim.health.start("bigquery-nvim")

  -- bq CLI
  if vim.fn.executable("bq") == 1 then
    vim.health.ok("bq CLI: " .. vim.fn.exepath("bq"))
  else
    vim.health.error(
      "bq CLI not found",
      { "Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install",
        "then: gcloud components install bq" })
  end

  -- gcloud auth
  vim.fn.system("gcloud auth application-default print-access-token 2>/dev/null")
  if vim.v.shell_error == 0 then
    vim.health.ok("gcloud application-default credentials active")
  else
    vim.health.warn(
      "gcloud ADC not configured",
      { "run: gcloud auth application-default login" })
  end

  -- plugin config
  local ok, cfg = pcall(require, "bigquery.config")
  if ok and cfg.options.project then
    vim.health.ok("project = " .. cfg.options.project)
  else
    vim.health.warn(
      "no project configured",
      { 'add `project = "your-gcp-project"` to require("bigquery").setup({...})' })
  end

  -- vim-dadbod-ui (optional)
  if vim.fn.exists(":DBUI") == 2 then
    vim.health.ok("vim-dadbod-ui detected")
    local qp = vim.g.db_ui_tmp_query_location
         or (vim.fn.expand("~/.local/share/nvim/db_ui_queries"))
    vim.health.info("DBUI schema cache dir: " .. qp)
  else
    vim.health.info("vim-dadbod-ui not detected (optional)")
  end
end

return M
