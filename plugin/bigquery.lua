if vim.g.loaded_bigquery_nvim then return end
vim.g.loaded_bigquery_nvim = true

vim.api.nvim_create_user_command("BigQuery", function(a)
  require("bigquery").browse(a.args ~= "" and a.args or nil)
end, { nargs = "?", desc = "Open BigQuery table browser" })

vim.api.nvim_create_user_command("BigQueryToggle", function(a)
  require("bigquery").toggle(a.args ~= "" and a.args or nil)
end, { nargs = "?", desc = "Toggle BigQuery table browser" })

vim.api.nvim_create_user_command("BigQuerySyncDBUI", function(a)
  require("bigquery").sync_dbui(a.args ~= "" and a.args or nil)
end, { nargs = "?", desc = "Sync BigQuery table listing to external schema cache" })

vim.api.nvim_create_user_command("BigQueryRefresh", function()
  require("bigquery.cache").clear()
  require("bigquery.browser").open()
end, { desc = "Clear BigQuery cache and refresh the browser" })
