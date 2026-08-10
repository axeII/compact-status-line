#!/bin/bash
# Compact status line for Claude Code.
# Reads the hook JSON payload on stdin, prints a two-line status line.
set -f

input=$(cat)
[ -z "$input" ] && { printf "Claude"; exit 0; }
command -v jq >/dev/null 2>&1 || { printf "Claude"; exit 0; }

# ── Colors ──────────────────────────────────────────────
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

# seconds -> "3h 51m" / "6d 2h" / "42m"
format_remaining() {
    local secs=$1
    [ -z "$secs" ] && return
    [ "$secs" -lt 0 ] && secs=0

    local days=$(( secs / 86400 ))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        printf "%dd %dh" "$days" "$hours"
    elif [ "$hours" -gt 0 ]; then
        printf "%dh %dm" "$hours" "$mins"
    else
        printf "%dm" "$mins"
    fi
}

iso_to_epoch() {
    local iso_str="$1"
    local epoch

    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"

    epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)

    [ -n "$epoch" ] && echo "$epoch"
}

# ── Model / effort ──────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

effort=""
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    effort=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
fi

# ── Directory / git branch ──────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ] && git_dirty="*"
fi

# ── Line 1: Model (effort) │ dir • branch ───────────────
line1="${orange}${model_name}"
[ -n "$effort" ] && [ "$effort" != "default" ] && line1+=" (${effort})"
line1+="${reset}"
line1+=" ${dim}|${reset} "
line1+="${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    line1+=" ${dim}•${reset} ${magenta}${git_branch}${red}${git_dirty}${reset}"
fi

# ── Context window usage ─────────────────────────────────
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# ── Rate limits: prefer the hook payload, fall back to the API ──
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -z "$five_pct" ]; then
    token="$CLAUDE_CODE_OAUTH_TOKEN"
    token_file="$HOME/.claude/statusline-token"
    [ -z "$token" ] && [ -f "$token_file" ] && token=$(tr -d '[:space:]' < "$token_file")

    if [ -n "$token" ]; then
        cache_file="/tmp/claude/statusline-cache.json"
        mkdir -p /tmp/claude
        cache_age=999999
        if [ -f "$cache_file" ]; then
            cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
            [ -n "$cache_mtime" ] && cache_age=$(( $(date +%s) - cache_mtime ))
        fi

        usage_data=""
        if [ "$cache_age" -lt 60 ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        else
            usage_data=$(curl -s --max-time 3 \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
                echo "$usage_data" > "$cache_file"
            else
                usage_data=$(cat "$cache_file" 2>/dev/null)
            fi
        fi

        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
            five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // empty' | awk '{printf "%.0f", $1}')
            five_reset=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
            seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // empty' | awk '{printf "%.0f", $1}')
            seven_reset=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        fi
    fi
fi

# ── Line 2: ctx usage • 5h usage • 7d usage ──────────────
line2=""
now_epoch=$(date +%s)

if [ -n "$ctx_pct" ]; then
    ctx_pct_i=$(printf "%.0f" "$ctx_pct" 2>/dev/null)
    ctx_color=$(color_for_pct "$ctx_pct_i")

    line2+="${white}ctx${reset} ${ctx_color}${ctx_pct_i}%${reset}"
fi

if [ -n "$five_pct" ]; then
    five_pct_i=$(printf "%.0f" "$five_pct" 2>/dev/null)
    five_color=$(color_for_pct "$five_pct_i")
    five_epoch=$(iso_to_epoch "$five_reset")
    five_left=$(format_remaining $(( five_epoch - now_epoch )))

    [ -n "$line2" ] && line2+=" ${dim}•${reset} "
    line2+="${white}5h${reset} ${five_color}${five_pct_i}%${reset}"
    [ -n "$five_left" ] && line2+=" ${dim}(${five_left})${reset}"
fi

if [ -n "$seven_pct" ]; then
    seven_pct_i=$(printf "%.0f" "$seven_pct" 2>/dev/null)
    seven_color=$(color_for_pct "$seven_pct_i")
    seven_epoch=$(iso_to_epoch "$seven_reset")
    seven_left=$(format_remaining $(( seven_epoch - now_epoch )))

    [ -n "$line2" ] && line2+=" ${dim}•${reset} "
    line2+="${white}7d${reset} ${seven_color}${seven_pct_i}%${reset}"
    [ -n "$seven_left" ] && line2+=" ${dim}(${seven_left})${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$line2" ] && printf "\n%b" "$line2"

exit 0
