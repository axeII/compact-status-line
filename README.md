# compact-status-line

A compact, single-line status line for [Claude Code](https://claude.com/claude-code).

<img width="1701" height="146" alt="image" src="https://github.com/user-attachments/assets/4f5a9d12-90a3-4059-a23c-f000389fa390" />


One line: directory (`~`-relative, collapsed if deep) · git branch with dirty/ahead-behind markers, then `[model (context size)]` (+ effort), a filling context-usage bar, and 5-hour/weekly rate limit usage with time-to-reset (e.g. `Usage ▓▓░░░░░░ 30% (1h 46m / 5h)`). Each rate-limit/context segment is colored green/yellow/red by percentage, and omitted entirely if the data isn't available.

Colors are chosen to stay legible in both light and dark terminal themes: level colors (green/yellow/red) and the model/usage accents use standard ANSI hues rather than a fixed light- or dark-only palette, and muted text (labels, effort, reset countdowns) uses the terminal's own dim attribute instead of a hard-coded gray — so nothing washes out on either background.

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
