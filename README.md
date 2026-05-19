# bigquery-nvim

A Neovim plugin for browsing and querying BigQuery — no project-wide IAM
permissions required, no dadbod needed.

## Features

| Feature | Description |
|---------|-------------|
| **Tree browser** | Sidebar with lazy-loading project → datasets → tables |
| **Query scaffold** | `<CR>` on a table opens a `SELECT * … LIMIT 100` SQL buffer |
| **Table schema** | `d` on a table runs `bq show` and opens the JSON schema |
| **TTL cache** | Results cached in-memory (default 5 min); `r` to force-refresh |
| **Async** | Every `bq` call runs in the background — editor never blocks |

## Requirements

- Neovim ≥ 0.9
- [google-cloud-sdk](https://cloud.google.com/sdk/docs/install) (`bq`, `gcloud`) on `$PATH`
- `gcloud auth application-default login` completed

## Installation

### lazy.nvim

```lua
{
  "your-username/bigquery-nvim",
  cmd = { "BigQuery", "BigQueryToggle" },
  opts = {
    project = "your-gcp-project",
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
  project = "your-gcp-project",

  -- How long to keep bq ls results in memory (seconds)
  cache_ttl = 300,
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:BigQuery [project]` | Open the tree browser |
| `:BigQueryToggle [project]` | Toggle the tree browser |
| `:BigQueryRefresh` | Clear cache and reload |
| `:checkhealth bigquery` | Verify dependencies and configuration |

## Browser key bindings

| Key | Action |
|-----|--------|
| `<CR>` | Expand dataset / collapse / open SELECT query for table |
| `d` | Describe table (runs `bq show`, opens JSON schema buffer) |
| `r` | Refresh — clears cache and re-fetches everything |
| `q` | Close browser |
| `?` | Show this help |

## Auth & latency

Authentication uses gcloud Application Default Credentials
(`~/.config/gcloud/application_default_credentials.json`).  The access token
is cached on disk by gcloud and refreshed automatically.

The remaining latency (~0.5–2 s per operation) is `bq` CLI startup time.
The browser mitigates this with lazy loading (tables only fetched when you
expand a dataset) and in-memory caching.

For heavy use, a service account key eliminates the SSO round-trip:

```sh
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
```

## vim-dadbod-ui (optional)

If you use vim-dadbod-ui and its BigQuery sidebar shows `(0) tables`, you can
fix it with:

```
:BigQuerySyncDBUI [project]
```

This fetches tables via `bq ls` and writes them into DBUI's JSON schema cache.
To auto-sync whenever DBUI opens:

```lua
require("bigquery").setup({
  project   = "your-gcp-project",
  dadbod    = { auto_populate = true },
})
```
