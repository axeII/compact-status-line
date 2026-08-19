#!/usr/bin/env bash
# Minimal single-line Claude Code status line.
# Reads the status line JSON payload from stdin and prints one compact line.
set -u
input="$(cat)"

get() {
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
}

CYAN='\033[36m'; DIM='\033[2m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; PURPLE='\033[35m'; RESET='\033[0m'
# DIM (SGR 2) rather than a hard-coded gray: it dims whatever the terminal's
# own foreground already is, so it stays legible on both light and dark
# backgrounds instead of washing out on one of them.

# Green under 70%, yellow 70-89%, red 90%+.
level_color() {
  pct="$1"
  if [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# Renders a "snake" bar: filled block cells up to pct of width, faint
# block cells for the rest. Any nonzero pct shows at least one filled
# cell, since a bar's width is often too coarse to round it up on its
# own (e.g. 5% on an 8-cell bar rounds to zero otherwise).
build_bar() {
  local pct=$1 width=$2
  local filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -eq 0 ] && [ "$pct" -gt 0 ] && filled=1
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$((width - filled))
  local bar="" i
  for (( i = 0; i < filled; i++ )); do bar+="█"; done
  for (( i = 0; i < empty; i++ )); do bar+="░"; done
  printf '%s' "$bar"
}

# Formats a countdown in seconds as "Xd" once a day or more remains, else
# "Xh Ym" (or "Ym" under an hour).
format_remaining() {
  local secs=$1
  [ "$secs" -lt 0 ] && secs=0
  local days=$(( secs / 86400 ))
  if [ "$days" -ge 1 ]; then
    printf '%dd' "$days"
  else
    local hours=$(( secs / 3600 )) mins=$(( (secs % 3600) / 60 ))
    if [ "$hours" -ge 1 ]; then printf '%dh %dm' "$hours" "$mins"
    else printf '%dm' "$mins"; fi
  fi
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

# Extended-context models (e.g. 1M-token Sonnet/Opus) get a "(1M context)"
# annotation; the default 200K window isn't worth calling out.
ctx_size="$(get '.context_window.context_window_size')"
ctx_annotation=""
if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 200000 ] 2>/dev/null; then
  ctx_m=$(( ctx_size / 1000000 ))
  [ "$ctx_m" -ge 1 ] && ctx_annotation=" (${ctx_m}M context)"
fi
model_colored="${CYAN}[${model}${ctx_annotation}]${RESET}"

# Reasoning effort, only shown when Claude Code actually exposes it.
effort="$(get '.effort.level')"
effort_part=""
[ -n "$effort" ] && effort_part=" ${DIM}(${effort})${RESET}"

# Context window usage — filling "snake" bar (█ filled / ░ empty).
ctx_pct="$(get '.context_window.used_percentage')"
ctx_part=""
if [ -n "$ctx_pct" ]; then
  ctx_int="$(LC_ALL=C printf '%.0f' "$ctx_pct")"
  ctx_color="$(level_color "$ctx_int")"
  ctx_bar="$(build_bar "$ctx_int" 10)"
  ctx_part=" ${ctx_color}${ctx_bar} ${ctx_int}%${RESET}"
fi

# 5h / 7-day rate-limit usage — only present for Claude.ai subscribers after
# the first API response of the session; omitted otherwise. Purple snake
# bars regardless of level, so they read as "usage" rather than "alert".
# Each is labeled with the time left until that window resets.
now="$(date +%s)"
five="$(get '.rate_limits.five_hour.used_percentage')"
five_resets="$(get '.rate_limits.five_hour.resets_at')"
week="$(get '.rate_limits.seven_day.used_percentage')"
week_resets="$(get '.rate_limits.seven_day.resets_at')"
limits_part=""
lp=""
if [ -n "$five" ]; then
  five_int="$(LC_ALL=C printf '%.0f' "$five")"
  five_bar="$(build_bar "$five_int" 8)"
  five_left=""
  case "$five_resets" in ''|*[!0-9]*) ;; *) five_left="$(format_remaining $(( five_resets - now )))" ;; esac
  lp="${DIM}Usage${RESET} ${PURPLE}${five_bar}${RESET} ${five_int}%"
  [ -n "$five_left" ] && lp="${lp} ${DIM}(${five_left} / 5h)${RESET}"
fi
if [ -n "$week" ]; then
  week_int="$(LC_ALL=C printf '%.0f' "$week")"
  week_bar="$(build_bar "$week_int" 8)"
  week_left=""
  case "$week_resets" in ''|*[!0-9]*) ;; *) week_left="$(format_remaining $(( week_resets - now )))" ;; esac
  w="${DIM}Weekly${RESET} ${PURPLE}${week_bar}${RESET} ${week_int}%"
  [ -n "$week_left" ] && w="${w} ${DIM}(${week_left} / Weekly)${RESET}"
  lp="${lp:+$lp | }$w"
fi
[ -n "$lp" ] && limits_part=" | $lp"

printf '%s%s | %b%b%b%b\n' "$short_cwd" "$git_info" "$model_colored" "$effort_part" "$ctx_part" "$limits_part"
exit 0
