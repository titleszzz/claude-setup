#!/bin/bash
# Claude Code status line
# Shows model, current dir, context-window usage, and 5h/7d rate limit bars.
#
# Dependency-free JSON parsing (no jq): uses grep -oP + sed, which are
# always available in the bundled Cygwin/Git-Bash shell on Windows.

input=$(cat)

RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[36m'
GRAY='\033[90m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
MAGENTA='\033[35m'

# --- tiny JSON helpers (no jq) ---------------------------------------------

json_str() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\"\\K[^\"]*" | head -1
}

json_obj() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\\{[^}]*\\}" | head -1
}

json_num() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\\K[0-9]+(\\.[0-9]+)?" | head -1
}

json_reset() {
  printf '%s' "$1" | grep -oP "\"resets_at\"\\s*:\\s*\"?\\K[^\",}]+" | head -1
}

model=$(json_str "$input" "display_name")
[ -z "$model" ] && model="Claude"

dir=$(json_str "$input" "current_dir")
[ -z "$dir" ] && dir=$(json_str "$input" "cwd")
dir_name=$(printf '%s' "$dir" | sed -E 's#[/\\]+$##; s#.*[/\\]##')

# Tight bar: 10 blocks, no trailing space before the %.
make_bar() {
  local pct="$1"
  local width=10
  local int_pct
  int_pct=$(awk "BEGIN{p=$pct; if (p<0) p=0; if (p>100) p=100; printf \"%d\", p}")
  local filled=$(( (int_pct * width + 50) / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local empty=$(( width - filled ))

  local color=$GREEN
  (( int_pct >= 70 )) && color=$YELLOW
  (( int_pct >= 90 )) && color=$RED

  local bar="" gap="" i
  for (( i = 0; i < filled; i++ )); do bar="${bar}█"; done
  for (( i = 0; i < empty; i++ )); do gap="${gap}░"; done

  printf "%b%s%b%b%s%b%b%d%%%b" \
    "$color" "$bar" "$RESET" \
    "$GRAY" "$gap" "$RESET" \
    "$BOLD$color" "$int_pct" "$RESET"
}

# Format resets_at (epoch or ISO-8601) as "XhYYm" / "XdYh", no inner space.
format_countdown() {
  local resets_at="$1"
  local epoch now
  if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
    epoch="$resets_at"
  else
    epoch=$(date -d "$resets_at" +%s 2>/dev/null)
  fi
  [ -z "$epoch" ] && return
  now=$(date +%s)
  local diff=$(( epoch - now ))
  (( diff < 0 )) && diff=0
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if (( days > 0 )); then
    printf "%dd%dh" "$days" "$hours"
  else
    printf "%dh%02dm" "$hours" "$mins"
  fi
}

sep="$(printf "%b│%b" "$GRAY" "$RESET")"

segments=()
segments+=("$(printf "%b🤖 %s%b" "$CYAN$BOLD" "$model" "$RESET")")
[ -n "$dir_name" ] && segments+=("$(printf "%b📂 %s%b" "$BLUE" "$dir_name" "$RESET")")

# context_window's used_percentage is a nested field (json_obj can't isolate
# it since context_window itself contains a nested {} block), but it's always
# the first "used_percentage" in the payload, ahead of rate_limits.
ctx_pct=$(json_num "$input" "used_percentage")
if [ -n "$ctx_pct" ]; then
  segments+=("$(printf "📊%bcontext:%b%s" "$BOLD" "$RESET" "$(make_bar "$ctx_pct")")")
fi

five_obj=$(json_obj "$input" "five_hour")
week_obj=$(json_obj "$input" "seven_day")
five_pct=$(json_num "$five_obj" "used_percentage")
five_reset=$(json_reset "$five_obj")
week_pct=$(json_num "$week_obj" "used_percentage")
week_reset=$(json_reset "$week_obj")

if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
  rl=""
  if [ -n "$five_pct" ]; then
    cd_str=""
    [ -n "$five_reset" ] && cd_str="$(printf "%b⏱️%s%b" "$GRAY" "$(format_countdown "$five_reset")" "$RESET")"
    rl="$(printf "⚡%b5h:%b%s%s" "$MAGENTA$BOLD" "$RESET" "$(make_bar "$five_pct")" "$cd_str")"
  fi
  if [ -n "$week_pct" ]; then
    cd_str=""
    [ -n "$week_reset" ] && cd_str="$(printf "%b⏱️%s%b" "$GRAY" "$(format_countdown "$week_reset")" "$RESET")"
    wk="$(printf "📅%b7d:%b%s%s" "$MAGENTA$BOLD" "$RESET" "$(make_bar "$week_pct")" "$cd_str")"
    rl="${rl}${wk}"
  fi
  segments+=("$rl")
fi

out=""
first=1
for seg in "${segments[@]}"; do
  if [ "$first" -eq 1 ]; then
    out="$seg"
    first=0
  else
    out="${out}${sep}${seg}"
  fi
done

printf "%s" "$out"
