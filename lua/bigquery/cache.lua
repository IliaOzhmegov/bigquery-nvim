-- In-memory TTL cache.  Keys are arbitrary strings.
local M = {}
local _store = {}

function M.get(key)
  local e = _store[key]
  if not e then return nil end
  if os.time() > e.exp then
    _store[key] = nil
    return nil
  end
  return e.val
end

function M.set(key, val, ttl)
  local default_ttl = require("bigquery.config").options.cache_ttl
  _store[key] = { val = val, exp = os.time() + (ttl or default_ttl or 300) }
end

-- Delete all keys that start with `prefix`.
function M.del(prefix)
  for k in pairs(_store) do
    if k:sub(1, #prefix) == prefix then
      _store[k] = nil
    end
  end
end

function M.clear()
  _store = {}
end

return M
