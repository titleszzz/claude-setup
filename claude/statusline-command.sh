#!/bin/bash
# Claude Code status line
# Shows model, current dir, and (for Claude.ai subscribers) fancy colored
# progress bars + countdown timers for the 5-hour and 7-day rate limits.
#
# Dependency-free JSON parsing (no jq): uses grep -oP + sed, which are
# always available in the bundled Cygwin/Git-Bash shell on Windows.

input=$(cat)

RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'
CYAN='\033[36m'
GRAY='\033[90m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
MAGENTA='\033[35m'

# --- tiny JSON helpers (no jq) ---------------------------------------------

# Extract a string value for a top-level-ish key: "key":"value"
json_str() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\"\\K[^\"]*" | head -1
}

# Extract the {...} object that follows "key":
json_obj() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\\{[^}]*\\}" | head -1
}

# Extract a numeric value: "key": 12.3
json_num() {
  printf '%s' "$1" | grep -oP "\"$2\"\\s*:\\s*\\K[0-9]+(\\.[0-9]+)?" | head -1
}

# Extract "resets_at": either an epoch number or an ISO-8601 string.
json_reset() {
  printf '%s' "$1" | grep -oP "\"resets_at\"\\s*:\\s*\"?\\K[^\",}]+" | head -1
}

model=$(json_str "$input" "display_name")
[ -z "$model" ] && model="Antigravity"

dir=$(json_str "$input" "current_dir")
[ -z "$dir" ] && dir=$(json_str "$input" "cwd")
# Last path component, whether separated by / or \
dir_name=$(printf '%s' "$dir" | sed -E 's#[/\\]+$##; s#.*[/\\]##')

# Build a colored block-progress bar for a 0-100 percentage.
# Color ramps green -> yellow -> red as usage climbs.
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

  printf "%b%s%b%b%s%b %b%3d%%%b" \
    "$color" "$bar" "$RESET" \
    "$GRAY" "$gap" "$RESET" \
    "$BOLD$color" "$int_pct" "$RESET"
}

# Format a resets_at value (epoch OR ISO-8601) as "Xh Ym" / "Xd Yh".
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
    printf "%dd %dh" "$days" "$hours"
  else
    printf "%dh %02dm" "$hours" "$mins"
  fi
}

segments=()
segments+=("$(printf "%b%s%b" "$CYAN" "$model" "$RESET")")
[ -n "$dir_name" ] && segments+=("$(printf "%b%s%b" "$BLUE" "$dir_name" "$RESET")")

five_obj=$(json_obj "$input" "five_hour")
week_obj=$(json_obj "$input" "seven_day")
five_pct=$(json_num "$five_obj" "used_percentage")
five_reset=$(json_reset "$five_obj")
week_pct=$(json_num "$week_obj" "used_percentage")
week_reset=$(json_reset "$week_obj")

if [ -n "$five_pct" ]; then
  bar=$(make_bar "$five_pct")
  cd_str=""
  [ -n "$five_reset" ] && cd_str=" $(printf "%b⏳ %s%b" "$GRAY" "$(format_countdown "$five_reset")" "$RESET")"
  segments+=("$(printf "%b5h%b %s%s" "$MAGENTA$BOLD" "$RESET" "$bar" "$cd_str")")
fi

if [ -n "$week_pct" ]; then
  bar=$(make_bar "$week_pct")
  cd_str=""
  [ -n "$week_reset" ] && cd_str=" $(printf "%b⏳ %s%b" "$GRAY" "$(format_countdown "$week_reset")" "$RESET")"
  segments+=("$(printf "%b7d%b %s%s" "$MAGENTA$BOLD" "$RESET" "$bar" "$cd_str")")
fi

out=""
sep=" $(printf "%b|%b" "$GRAY" "$RESET") "
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
