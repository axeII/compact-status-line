#!/usr/bin/env bash
# Minimal single-line Claude Code status line.
# Reads the status line JSON payload from stdin and prints one compact line.
set -u
input="$(cat)"

get() {
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
}

CYAN='\033[36m'; GRAY='\033[37m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# Green under 70%, yellow 70-89%, red 90%+.
level_color() {
  pct="$1"
  if [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

cwd="$(get '.workspace.current_dir')"
[ -z "$cwd" ] && cwd="$(get '.cwd')"
[ -z "$cwd" ] && cwd="$PWD"

# ~-relative short path; collapse to ".../parent/leaf" if it's still deep.
home="${HOME%/}"
case "$cwd" in
  "$home"|"$home"/*) short_cwd="~${cwd#$home}" ;;
  *) short_cwd="$cwd" ;;
esac
IFS='/' read -ra __parts <<< "$short_cwd"
__n=${#__parts[@]}
if [ "$__n" -gt 3 ]; then
  short_cwd=".../${__parts[$((__n-2))]}/${__parts[$((__n-1))]}"
fi

# Git branch + cheap dirty/ahead-behind indicator (single git status call).
git_info=""
if command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)"
  [ -z "$branch" ] && branch="$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
  status_out="$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)"
  ahead="$(printf '%s\n' "$status_out" | awk '/^# branch.ab/ {gsub(/\+/,"",$3); print $3}')"
  behind="$(printf '%s\n' "$status_out" | awk '/^# branch.ab/ {gsub(/-/,"",$4); print $4}')"
  dirty=""
  if printf '%s\n' "$status_out" | grep -qv '^#'; then dirty="*"; fi
  ab=""
  [ -n "$ahead" ] && [ "$ahead" != "0" ] && ab="${ab}↑${ahead}"
  [ -n "$behind" ] && [ "$behind" != "0" ] && ab="${ab}↓${behind}"
  if [ -n "$branch" ]; then
    git_info=" · ${branch}${dirty}${ab:+ $ab}"
  fi
fi

model="$(get '.model.display_name')"
model_colored="${CYAN}${model}${RESET}"

# Reasoning effort, only shown when Claude Code actually exposes it.
effort="$(get '.effort.level')"
effort_part=""
[ -n "$effort" ] && effort_part=" ${GRAY}(${effort})${RESET}"

# Context window usage — filling "snake" bar (█ filled / ░ empty).
ctx_pct="$(get '.context_window.used_percentage')"
ctx_part=""
if [ -n "$ctx_pct" ]; then
  ctx_int="$(LC_ALL=C printf '%.0f' "$ctx_pct")"
  bar_width=10
  filled=$(( (ctx_int * bar_width + 50) / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$((bar_width - filled))
  bar=""
  [ "$filled" -gt 0 ] && printf -v fill "%${filled}s" && bar="${fill// /█}"
  [ "$empty" -gt 0 ] && printf -v pad "%${empty}s" && bar="${bar}${pad// /░}"
  ctx_color="$(level_color "$ctx_int")"
  ctx_part=" | ${ctx_color}${bar} ${ctx_int}%${RESET}"
fi

# 5h / 7-day rate-limit usage — only present for Claude.ai subscribers after
# the first API response of the session; omitted otherwise. Percent first.
five="$(get '.rate_limits.five_hour.used_percentage')"
week="$(get '.rate_limits.seven_day.used_percentage')"
limits_part=""
lp=""
if [ -n "$five" ]; then
  five_int="$(LC_ALL=C printf '%.0f' "$five")"
  lp="$(level_color "$five_int")${five_int}%${RESET} ${GRAY}5h${RESET}"
fi
if [ -n "$week" ]; then
  week_int="$(LC_ALL=C printf '%.0f' "$week")"
  w="$(level_color "$week_int")${week_int}%${RESET} ${GRAY}7d${RESET}"
  lp="${lp:+$lp }$w"
fi
[ -n "$lp" ] && limits_part=" | $lp"

printf '%s%s | %b%b%b%b\n' "$short_cwd" "$git_info" "$model_colored" "$effort_part" "$ctx_part" "$limits_part"
exit 0
