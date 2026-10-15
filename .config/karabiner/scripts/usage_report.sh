#!/bin/sh
# Rank Hyper shortcuts by use for one month. Usage: usage_report.sh [YYYY-MM]
month="${1:-$(date +%Y-%m)}"
grep "^$month" "$HOME/.local/state/karabiner/usage.log" \
  | cut -f2,3 | sort | uniq -c | sort -rn | head -20 \
  | awk '{printf "%6d  hyper+%s+%s\n", $1, $2, $3}'
