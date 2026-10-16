#!/bin/bash
# Check that Hyper shortcuts reach usage.log, with a count you control.
# For each of four classes it records the log count, asks you to press the shortcut N times,
# waits for Enter, then prints expected and recorded counts. It only reads the log.
#
# Usage: bash scripts/verify_logging.sh [-n N] [--log PATH]
#   -n N       presses per class (default 10)
#   --log PATH log to read (default ~/.local/state/karabiner/usage.log)
# Test mode, for a COPY of the log only (refused for the real log):
#   --simulate           append N lines per class to the copy instead of waiting for key presses
#   --simulate-drop L K=M  append only N-M lines for layer L key K (shows the FAIL path); may repeat

set -uo pipefail

REAL_LOG="$HOME/.local/state/karabiner/usage.log"
LOG="$REAL_LOG"
N=10
SIMULATE=0
declare -a DROPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="${2:-}"; shift 2 ;;
    --log) LOG="${2:-}"; shift 2 ;;
    --simulate) SIMULATE=1; shift ;;
    --simulate-drop) DROPS+=("${2:-} ${3:-}"); shift 3 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$N" in '' | *[!0-9]*) echo "-n needs a whole number" >&2; exit 2 ;; esac
[ "$N" -ge 1 ] || { echo "-n must be at least 1" >&2; exit 2; }
[ -f "$LOG" ] || { echo "log not found: $LOG" >&2; exit 2; }

real_path() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
if [ "$SIMULATE" -eq 1 ] && [ "$(real_path "$LOG")" = "$(real_path "$REAL_LOG")" ]; then
  echo "refusing --simulate on the real log; pass --log with a copy" >&2
  exit 2
fi

# class label | layer | key | what to press | side effect
CLASSES=(
  "key action|v|j|Hyper + V + J|moves the cursor down"
  "app launch|o|t|Hyper + O + T|opens or focuses Ghostty"
  "window action|w|h|Hyper + W + H|snaps the focused window to the left half"
  "dashboard|s|q|Hyper + S + Q|opens or closes the dashboard (use an even N to leave it closed)"
)

count() { # count <layer> <key>: lines whose 2nd and 3rd tab fields match
  awk -F'\t' -v l="$1" -v k="$2" '$2 == l && $3 == k { n++ } END { print n + 0 }' "$LOG"
}

append_simulated() { # append_simulated <layer> <key>
  local layer="$1" key="$2" times="$N" drop
  for drop in ${DROPS[@]+"${DROPS[@]}"}; do
    set -- $drop
    if [ "$1" = "$layer" ] && [ "${2%%=*}" = "$key" ]; then times=$((N - ${2#*=})); fi
  done
  local i
  for ((i = 0; i < times; i++)); do
    printf '%s\t%s\t%s\n' "$(date +%FT%T)" "$layer" "$key" >>"$LOG"
  done
}

failures=0
results=()
echo "Log: $LOG   Presses per class: $N"
[ "$SIMULATE" -eq 1 ] && echo "(simulation: lines are appended to this copy, nothing is pressed)"
echo "Press each shortcut one tap at a time, about one per second. Do not hold keys."
echo

for entry in "${CLASSES[@]}"; do
  IFS='|' read -r label layer key press effect <<<"$entry"
  before="$(count "$layer" "$key")"
  echo "[$label] Press $press exactly $N times ($effect)."
  if [ "$SIMULATE" -eq 1 ]; then
    append_simulated "$layer" "$key"
  else
    printf 'Press Enter when you have pressed it %s times: ' "$N"
    read -r _ || { echo; echo "no input; stopping" >&2; exit 2; }
    sleep 1 # the log line is written a few milliseconds after the press
  fi
  after="$(count "$layer" "$key")"
  got=$((after - before))
  if [ "$got" -eq "$N" ]; then verdict=PASS
  elif [ "$got" -gt "$N" ]; then verdict="FAIL (more lines than presses: extra or repeated presses?)"; failures=$((failures + 1))
  else verdict="FAIL ($((N - got)) missing)"; failures=$((failures + 1)); fi
  printf '  expected %s, recorded %s: %s\n\n' "$N" "$got" "$verdict"
  results+=("$(printf '%-14s %s %s expected %s recorded %s %s' "$label" "$layer" "$key" "$N" "$got" "$verdict")")
done

echo "Summary"
printf '  %s\n' "${results[@]}"
if [ "$failures" -gt 0 ]; then
  echo "$failures of ${#CLASSES[@]} classes failed."
  exit 1
fi
echo "All ${#CLASSES[@]} classes recorded every press."
