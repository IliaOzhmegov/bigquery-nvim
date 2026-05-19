-- Tree browser: BigQuery project → datasets → tables.
-- Uses `bq ls` (not INFORMATION_SCHEMA) so dataset-level permissions suffice.
local M = {}
local bq    = require("bigquery.bq")
local cache = require("bigquery.cache")

local BUF_NAME = "BigQuery"
local ns = vim.api.nvim_create_namespace("bigquery_browser")

-- Single global state (one browser window at a time).
local S = {
  buf     = nil,
  win     = nil,
  project = nil,
  root    = nil,  -- project node
  nodes   = {},   -- flat ordered list of currently visible nodes
}

--------------------------------------------------------------------
-- Node helpers
--------------------------------------------------------------------

local function mk_node(kind, name, parent)
  return {
    kind       = kind,   -- "project" | "dataset" | "table"
    name       = name,
    parent     = parent,
    expanded   = false,
    loading    = false,
    children   = nil,    -- nil = not yet fetched
    table_type = nil,    -- "TABLE" | "VIEW" | "EXTERNAL" …
  }
end

--------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------

local function prefix(node)
  if node.kind == "project" then
    if node.loading then return "  " end
    return node.expanded and "▾ " or "▸ "
  elseif node.kind == "dataset" then
    if node.loading then return "    " end
    return node.expanded and "  ▾ " or "  ▸ "
  else  -- table
    local icon = node.table_type == "VIEW" and "⊡" or "⊞"
    return "    " .. icon .. " "
  end
end

local function collect(node, out)
  out[#out + 1] = node
  if node.expanded and node.children then
    for _, child in ipairs(node.children) do
      collect(child, out)
    end
  end
end

local function render()
  if not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return end

  local nodes = {}
  if S.root then collect(S.root, nodes) end
  S.nodes = nodes

  local lines = {}
  for _, n in ipairs(nodes) do
    lines[#lines + 1] = prefix(n) .. n.name
  end

  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)

  local hl_for = {
    project = "BigQueryProject",
    dataset = "BigQueryDataset",
    table   = "BigQueryTable",
  }
  for i, n in ipairs(nodes) do
    local hl = hl_for[n.kind]
    if n.kind == "table" and n.table_type == "VIEW" then hl = "BigQueryView" end
    if hl then vim.api.nvim_buf_add_highlight(S.buf, ns, hl, i - 1, 0, -1) end
  end
end

--------------------------------------------------------------------
-- Expansion  (cache stores raw data; nodes are rebuilt on each expand)
--------------------------------------------------------------------

local function build_table_children(tables, parent)
  local children = {}
  for _, t in ipairs(tables) do
    local child = mk_node("table", t.id, parent)
    child.table_type = t.type
    children[#children + 1] = child
  end
  return children
end

local function expand_dataset(node)
  local key    = ("tables:%s:%s"):format(S.project, node.name)
  local cached = cache.get(key)
  if cached then
    node.children = build_table_children(cached, node)
    node.expanded = true
    render()
    return
  end
  node.loading = true
  render()
  bq.list_tables(S.project, node.name, function(err, tables)
    node.loading = false
    if err then
      vim.notify("[bigquery] " .. err, vim.log.levels.ERROR)
      render()
      return
    end
    cache.set(key, tables)
    node.children = build_table_children(tables, node)
    node.expanded = true
    render()
  end)
end

local function expand_project(node)
  local key    = ("datasets:%s"):format(S.project)
  local cached = cache.get(key)
  if cached then
    node.children = {}
    for _, ds in ipairs(cached) do
      node.children[#node.children + 1] = mk_node("dataset", ds, node)
    end
    node.expanded = true
    render()
    return
  end
  node.loading = true
  render()
  bq.list_datasets(S.project, function(err, datasets)
    node.loading = false
    if err then
      vim.notify("[bigquery] " .. err, vim.log.levels.ERROR)
      render()
      return
    end
    cache.set(key, datasets)
    node.children = {}
    for _, ds in ipairs(datasets) do
      node.children[#node.children + 1] = mk_node("dataset", ds, node)
    end
    node.expanded = true
    render()
  end)
end

--------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------

local function prev_win_id()
  local prev = vim.fn.winnr("#")
  if prev > 0 then return vim.fn.win_getid(prev) end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= S.win then return w end
  end
end

local function open_in_prev(buf)
  local w = prev_win_id()
  if w then
    vim.api.nvim_win_set_buf(w, buf)
    vim.api.nvim_set_current_win(w)
  else
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
  end
end

local function open_table_query(node)
  local dataset = node.parent and node.parent.name or ""
  local sql = ("SELECT *\nFROM `%s.%s.%s`\nLIMIT 100"):format(
    S.project, dataset, node.name)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].filetype  = "sql"
  vim.bo[b].buftype   = "nofile"
  vim.bo[b].buflisted = true
  vim.api.nvim_buf_set_name(b, ("bq: %s.%s"):format(dataset, node.name))
  vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(sql, "\n"))
  open_in_prev(b)
end

local function describe_table(node)
  local dataset = node.parent and node.parent.name or ""
  node.loading  = true
  render()
  bq.describe(S.project, dataset, node.name, function(err, out)
    node.loading = false
    render()
    if err then
      vim.notify("[bigquery] " .. err, vim.log.levels.ERROR)
      return
    end
    local b = vim.api.nvim_create_buf(false, true)
    vim.bo[b].filetype  = "json"
    vim.bo[b].buftype   = "nofile"
    vim.api.nvim_buf_set_name(b, ("bq schema: %s.%s"):format(dataset, node.name))
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(out, "\n"))
    open_in_prev(b)
  end)
end

--------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------

local function cur_node()
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then return end
  local lnum = vim.api.nvim_win_get_cursor(S.win)[1]
  return S.nodes[lnum]
end

local function on_cr()
  local node = cur_node()
  if not node then return end

  if node.kind == "project" then
    if node.expanded then node.expanded = false; render()
    else expand_project(node) end

  elseif node.kind == "dataset" then
    if node.expanded then
      node.expanded = false; render()
    elseif node.children then
      -- already loaded, just re-expand
      node.expanded = true; render()
    else
      expand_dataset(node)
    end

  elseif node.kind == "table" then
    open_table_query(node)
  end
end

local function on_d()
  local node = cur_node()
  if node and node.kind == "table" then describe_table(node) end
end

local function on_refresh()
  cache.clear()
  S.root = mk_node("project", S.project, nil)
  render()
  expand_project(S.root)
end

local function setup_keymaps(b)
  local o = { buffer = b, silent = true, noremap = true }
  local function map(k, fn, desc)
    vim.keymap.set("n", k, fn, vim.tbl_extend("force", o, { desc = desc }))
  end
  map("<CR>", on_cr,       "expand / open query")
  map("d",    on_d,        "describe table schema")
  map("r",    on_refresh,  "refresh (clear cache)")
  map("q", function()
    if S.win and vim.api.nvim_win_is_valid(S.win) then
      vim.api.nvim_win_close(S.win, true)
    end
  end, "close browser")
  map("?", function()
    vim.notify(table.concat({
      "BigQuery browser:",
      "  <CR>  expand dataset / open SELECT query for table",
      "  d     describe table (show schema JSON)",
      "  r     refresh (clears cache, re-fetches all)",
      "  q     close",
    }, "\n"), vim.log.levels.INFO)
  end, "show help")
end

--------------------------------------------------------------------
-- Buffer / window management
--------------------------------------------------------------------

local function get_buf()
  -- Reuse existing buffer if still valid
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) then return S.buf end
  -- Look for a named buffer that survived a window close
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.fn.bufname(b) == BUF_NAME then
      S.buf = b
      return b
    end
  end
  -- Create fresh
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(b, BUF_NAME)
  vim.bo[b].buftype    = "nofile"
  vim.bo[b].bufhidden  = "wipe"
  vim.bo[b].swapfile   = false
  vim.bo[b].modifiable = false
  vim.bo[b].filetype   = "bigquery"
  setup_keymaps(b)
  S.buf = b
  return b
end

--------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------

function M.open(project)
  project = project or require("bigquery.config").options.project
  if not project then
    vim.notify(
      "[bigquery] no project — set `project` in setup() or pass it as argument",
      vim.log.levels.ERROR)
    return
  end

  local project_changed = S.project ~= project
  S.project = project
  get_buf()

  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_set_current_win(S.win)
  else
    vim.cmd("leftabove 40vsplit")
    S.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(S.win, S.buf)
    vim.wo[S.win].number         = false
    vim.wo[S.win].relativenumber = false
    vim.wo[S.win].signcolumn     = "no"
    vim.wo[S.win].foldcolumn     = "0"
    vim.wo[S.win].winfixwidth    = true
    vim.wo[S.win].wrap           = false

    vim.api.nvim_create_autocmd("WinClosed", {
      buffer   = S.buf,
      once     = true,
      callback = function() S.win = nil end,
    })
  end

  if not S.root or project_changed then
    S.root = mk_node("project", project, nil)
    render()
    expand_project(S.root)
  else
    render()
  end
end

function M.close()
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
end

function M.toggle(project)
  if S.win and vim.api.nvim_win_is_valid(S.win) then
    M.close()
  else
    M.open(project)
  end
end

return M
