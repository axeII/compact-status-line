# compact-status-line

A compact, single-line status line for [Claude Code](https://claude.com/claude-code).

![](.github/demo.png)

One line: directory (`~`-relative, collapsed if deep) · git branch with dirty/ahead-behind markers, then model (+ effort), a filling context-usage bar, and 5-hour/7-day rate limit usage. Each rate-limit/context segment is colored green/yellow/red by percentage, and omitted entirely if the data isn't available.

## Install

```
npx compact-status-line
```

This copies `bin/statusline.sh` to `~/.claude/statusline.sh` and points `statusLine` in `~/.claude/settings.json` at it. Restart Claude Code afterwards.

To remove it:

```
npx compact-status-line --uninstall
```

## How it works

Everything — reading the hook payload, computing colors, formatting output — lives in a single file, `bin/statusline.sh`. There's no separate background process, cache file, or data-fetching script.

Rate limit usage and context window usage are read straight from the hook JSON on stdin (`.rate_limits.five_hour` / `.seven_day`, `.context_window.used_percentage`), which is what recent Claude Code versions send. If a Claude Code version doesn't send rate limits yet, that segment is just omitted — no API calls, no OAuth token needed.

## Requirements

`jq`. `git` is optional, for the branch/dirty/ahead-behind indicator.
