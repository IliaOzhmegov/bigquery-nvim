# bigquery-nvim

A Neovim plugin for BigQuery that works with **dataset-level permissions** — no
project-wide `bigquery.tables.list` required.

## Why

`vim-dadbod-ui` lists BigQuery tables by querying
`INFORMATION_SCHEMA.TABLES`, which requires a project-level IAM role.
If your access is scoped to specific datasets (common in large orgs), the
sidebar shows `(0) tables` for every schema.

This plugin replaces that lookup with `bq ls project:dataset`, which only
needs dataset-level `roles/bigquery.metadataViewer`.

It also runs every `bq` invocation asynchronously, so your editor never
blocks while waiting for the CLI.

## Features

| Feature | Description |
|---------|-------------|
| **Tree browser** | Lazy-loading sidebar: project → datasets → tables |
| **Query scaffold** | `<CR>` on a table opens a `SELECT * … LIMIT 100` SQL buffer |
| **Table schema** | `d` on a table runs `bq show` and shows the JSON schema |
| **TTL cache** | Results cached in-memory (default 5 min); `r` to force-refresh |
| **DBUI integration** | `:BigQuerySyncDBUI` writes DBUI's JSON schema cache so the sidebar works |

## Requirements

- Neovim ≥ 0.9
- [google-cloud-sdk](https://cloud.google.com/sdk/docs/install) (`bq`, `gcloud`) on `$PATH`
- `gcloud auth application-default login` completed

## Installation

### lazy.nvim

```lua
{
  "your-username/bigquery-nvim",
  ft = { "sql", "bigquery" },
  cmd = { "BigQuery", "BigQueryToggle", "BigQuerySyncDBUI" },
  opts = {
    project = "your-gcp-project",  -- required
  },
}
```

### packer.nvim

```lua
use {
  "your-username/bigquery-nvim",
  config = function()
    require("bigquery").setup({ project = "your-gcp-project" })
  end,
}
```

## Configuration

```lua
require("bigquery").setup({
  -- GCP project ID (required)
  project = "beyond-data-dev",

  -- How long to keep bq ls results in memory (seconds)
  cache_ttl = 300,

  dadbod = {
    -- Enable :BigQuerySyncDBUI command
    enabled = true,

    -- Auto-populate DBUI schema cache whenever DBUIOpened fires
    -- (runs bq ls for all datasets on every DBUI open — can be slow)
    auto_populate = false,
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:BigQuery [project]` | Open the tree browser |
| `:BigQueryToggle [project]` | Toggle the tree browser |
| `:BigQuerySyncDBUI [project]` | Fetch tables via `bq ls` and write them into vim-dadbod-ui's schema cache |
| `:BigQueryRefresh` | Clear in-memory cache and reload the browser |
| `:checkhealth bigquery` | Verify dependencies and configuration |

## Browser key bindings

| Key | Action |
|-----|--------|
| `<CR>` | Expand dataset / collapse / open SELECT query for table |
| `d` | Describe table (runs `bq show`, opens JSON schema buffer) |
| `r` | Refresh — clears cache and re-fetches everything |
| `q` | Close browser |
| `?` | Show this help |

## vim-dadbod-ui integration

Configure your BigQuery connection in DBUI as usual:

```lua
vim.g.dbs = {
  { name = "bigquery-dev", url = "bigquery://beyond-data-dev" },
}
```

Then run `:BigQuerySyncDBUI` once (or add `auto_populate = true`).  The plugin
writes a JSON cache file that DBUI reads instead of running
`INFORMATION_SCHEMA.TABLES`.

> **Note**: DBUI names its cache files after the connection key, which is
> derived from the connection URL/name.  If the auto-detection doesn't match
> your connection, check `:checkhealth bigquery` for the detected cache path
> and adjust `vim.g.db_ui_tmp_query_location` if needed.

## Auth & latency

Authentication uses your gcloud Application Default Credentials
(`~/.config/gcloud/application_default_credentials.json`).  The access token
is cached on disk by gcloud and refreshed automatically.

The remaining latency (~0.5–2 s per operation) is `bq` CLI startup time.  To
reduce it:

- Use the browser's built-in cache (`r` only when you need fresh data)
- For heavy use, consider a service account key:
  `GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json`
