# limitbar

Native macOS status bar app that shows current AI limits/usage for:
- Claude
- Codex (OpenAI)
- Gemini

The app distinguishes account kinds (`API` vs `Subscription`) and shows `Not available` when a public API does not expose remaining limits.

Rows are compact by default:
- favicon-style badge
- account tag (`API · Search`, `Auth`, ...)
- progress bar from 0-100%
- details visible only after row expand

## Run

```bash
swift run
```

## Configuration

By default, limitbar loads account config from:

```text
~/.config/limitbar/accounts.json
```

Override with:

```bash
export LIMITBAR_CONFIG_PATH="/absolute/path/to/accounts.json"
```

See `accounts.example.json`.

### UI config

Configure what is visible and row bar width in `ui`:

```json
{
  "ui": {
    "menuBar": {
      "showPercentage": true,
      "showMiniBar": true,
      "showWarningCount": true,
      "aggregation": "worst"
    },
    "row": {
      "progressWidth": 148,
      "showPercentage": true,
      "detailsCollapsedByDefault": true
    }
  }
}
```

### Demo mode

Set per-account `"demo": "true"` in `settings` to render local data without API keys.

## Secrets (ENV only)

`<ACCOUNT_ID_SUFFIX>` is `account.id` uppercased with non-alphanumeric chars replaced by `_`.

### Codex (OpenAI API)
- `LIMITBAR_OPENAI_ADMIN_KEY_<ACCOUNT_ID_SUFFIX>`

### Claude (Anthropic API)
- `LIMITBAR_ANTHROPIC_ADMIN_KEY_<ACCOUNT_ID_SUFFIX>`

### Gemini (Google API)
- `LIMITBAR_GCP_PROJECT_<ACCOUNT_ID_SUFFIX>`
- `LIMITBAR_GOOGLE_OAUTH_TOKEN_<ACCOUNT_ID_SUFFIX>`

Global fallbacks are supported for local dev (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.), but per-account vars are preferred.
