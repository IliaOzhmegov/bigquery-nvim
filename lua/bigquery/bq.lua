-- Async wrapper around the `bq` CLI.
-- All callbacks are called on the Neovim main loop (vim.schedule_wrap).
local M = {}
local uv = vim.uv or vim.loop  -- compat: vim.uv landed in nvim 0.10

local function spawn(args, on_done)
  local out_chunks = {}
  local err_chunks = {}
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local handle
  handle = uv.spawn("bq", {
    args  = args,
    stdio = { nil, stdout, stderr },
  }, vim.schedule_wrap(function(code)
    stdout:close()
    stderr:close()
    handle:close()
    on_done(code, table.concat(out_chunks), table.concat(err_chunks))
  end))

  if not handle then
    stdout:close()
    stderr:close()
    vim.schedule(function()
      on_done(-1, "", "failed to spawn 'bq' — is google-cloud-sdk installed and on PATH?")
    end)
    return
  end

  stdout:read_start(function(_, data)
    if data then out_chunks[#out_chunks + 1] = data end
  end)
  stderr:read_start(function(_, data)
    if data then err_chunks[#err_chunks + 1] = data end
  end)
end

-- bq sometimes writes errors to stdout; prefer stderr, fall back to stdout.
local function bq_err(out, err)
  local msg = err ~= "" and err or out
  return msg ~= "" and msg or "(no output)"
end

local function decode_json(raw, context)
  if raw == "" then return nil, {} end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    return "JSON parse error (" .. context .. "): " .. raw, nil
  end
  return nil, data
end

--- List datasets in `project`.  cb(err, {string,...})
function M.list_datasets(project, cb)
  spawn({ "ls", "--format=json", "--max_results=1000", "--project_id=" .. project },
    function(code, out, err)
      if code ~= 0 then
        cb(("bq ls %s: %s"):format(project, bq_err(out, err)))
        return
      end
      local jerr, data = decode_json(out, "list_datasets")
      if jerr then cb(jerr) return end
      local datasets = {}
      for _, item in ipairs(data) do
        if item.datasetReference then
          datasets[#datasets + 1] = item.datasetReference.datasetId
        end
      end
      table.sort(datasets)
      cb(nil, datasets)
    end)
end

--- List tables in `project:dataset`.  cb(err, {{id,type},...})
function M.list_tables(project, dataset, cb)
  spawn({
    "ls", "--format=json", "--max_results=10000",
    project .. ":" .. dataset,
  }, function(code, out, err)
    if code ~= 0 then
      cb(("bq ls %s:%s: %s"):format(project, dataset, bq_err(out, err)))
      return
    end
    local jerr, data = decode_json(out, "list_tables")
    if jerr then cb(jerr) return end
    local tables = {}
    for _, item in ipairs(data) do
      if item.tableReference then
        tables[#tables + 1] = {
          id   = item.tableReference.tableId,
          type = item.type or "TABLE",
        }
      end
    end
    table.sort(tables, function(a, b) return a.id < b.id end)
    cb(nil, tables)
  end)
end

--- Run a SQL query.  cb(err, output_string)
function M.query(sql, project, cb)
  local args = { "query", "--nouse_legacy_sql", "--format=pretty" }
  if project then
    args[#args + 1] = "--project_id=" .. project
  end
  args[#args + 1] = sql
  spawn(args, function(code, out, err)
    if code ~= 0 then cb("query failed: " .. bq_err(out, err))
    else cb(nil, out) end
  end)
end

--- Show table metadata (schema, partitioning, …).  cb(err, json_string)
function M.describe(project, dataset, table_name, cb)
  spawn({
    "show", "--format=prettyjson",
    ("%s:%s.%s"):format(project, dataset, table_name),
  }, function(code, out, err)
    if code ~= 0 then cb("bq show failed: " .. bq_err(out, err))
    else cb(nil, out) end
  end)
end

return M
