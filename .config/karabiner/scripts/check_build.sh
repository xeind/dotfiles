#!/bin/bash
# Build the Karabiner config in a temporary folder and check the result.
# Never writes to karabiner.json or hyperdash/bindings.json in this repo.
# Usage: bash scripts/check_build.sh   (or: yarn check:build)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/.local/state/karabiner"
HS=/opt/homebrew/bin/hs

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
die() { printf 'FAIL  %s\n' "$1"; exit 1; }

command -v jq >/dev/null || die "jq is not installed"
command -v yarn >/dev/null || die "yarn is not installed"

WORK="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$WORK"' EXIT

for file in rules.ts utils.ts types.ts package.json; do
  cp "$ROOT/$file" "$WORK/$file" || die "cannot copy $file from $ROOT"
done
ln -s "$ROOT/node_modules" "$WORK/node_modules"
mkdir "$WORK/hyperdash"

build() { # build <n>: run the build, keep the outputs as <name>.<n>
  (cd "$WORK" && yarn --silent build >"build.$1.log" 2>&1) || {
    cat "$WORK/build.$1.log"
    die "build $1 failed in $WORK"
  }
  cp "$WORK/karabiner.json" "$WORK/karabiner.$1.json"
  cp "$WORK/hyperdash/bindings.json" "$WORK/bindings.$1.json"
}

build 1
build 2
CONFIG="$WORK/karabiner.1.json"
BINDINGS="$WORK/bindings.1.json"

# 2. Repeatable output.
if cmp -s "$WORK/karabiner.1.json" "$WORK/karabiner.2.json" &&
  cmp -s "$WORK/bindings.1.json" "$WORK/bindings.2.json"; then
  pass "two builds are byte-identical"
else
  fail "two builds differ (karabiner.json or bindings.json is not repeatable)"
fi

# Sublayer manipulators: a "hyper_sublayer_*" condition set to 1 (same rule as
# listSubLayerBindings in utils.ts).
IS_LAYER='((.name // "") | startswith("hyper_sublayer_")) and .value == 1'
SUBLAYER=".profiles[0].complex_modifications.rules[].manipulators[] | select(any(.conditions[]?; $IS_LAYER))"

# 3. to[0] of every sublayer manipulator starts with the usage-log command. A shell-command action is
# merged into that same shell_command after "; " (see withUsageLog in utils.ts).
template="printf '%s\\t@L\\t@K\\n' \"\$(date +%FT%T)\" >> $LOG_DIR/usage.log"
total="$(jq "[$SUBLAYER] | length" "$CONFIG")"
bad="$(jq -r --arg tmpl "$template" "
  $SUBLAYER
  | (first(.conditions[] | select($IS_LAYER)).name | ltrimstr(\"hyper_sublayer_\")) as \$l
  | .from.key_code as \$k
  | (\$tmpl | sub(\"@L\"; \$l) | sub(\"@K\"; \$k)) as \$expected
  | select((.to[0].shell_command // \"\") | (. == \$expected or startswith(\$expected + \"; \")) | not)
  | \"\(\$l)/\(\$k)\"" "$CONFIG")"
if [ "$total" -eq 0 ]; then
  fail "no sublayer manipulators found in karabiner.json"
elif [ -n "$bad" ]; then
  fail "to[0] is not the usage-log command for: $(echo "$bad" | head -5 | tr '\n' ' ')($(echo "$bad" | wc -l | tr -d ' ') of $total)"
else
  pass "all $total sublayer manipulators log usage in to[0]"
fi

# 3b. Karabiner keeps one process slot for shell commands and kills the running one when the next
# starts, so a log shell_command followed by another shell_command in the same "to" loses the log line.
split="$(jq -r "
  $SUBLAYER
  | select((.to | map(select((.shell_command // \"\") | contains(\"usage.log\"))) | length) > 0
      and (.to | map(select(.shell_command != null)) | length) > 1)
  | \"\(first(.conditions[] | select($IS_LAYER)).name | ltrimstr(\"hyper_sublayer_\"))/\(.from.key_code)\"" "$CONFIG")"
if [ -n "$split" ]; then
  fail "usage log and another shell_command share one to array (the log line is lost): $(echo "$split" | head -5 | tr '\n' ' ')($(echo "$split" | wc -l | tr -d ' ') of $total)"
else
  pass "no sublayer manipulator has the usage log plus another shell_command in one to array"
fi

# 4. One binding per sublayer manipulator.
bound="$(jq length "$BINDINGS")"
if [ "$bound" -eq "$total" ]; then
  pass "bindings.json has $bound entries, one per sublayer manipulator"
else
  fail "bindings.json has $bound entries but karabiner.json has $total sublayer manipulators"
fi

# 5. The profile setting that earlier builds lost.
keyboard="$(jq -r '.profiles[0].virtual_hid_keyboard.keyboard_type_v2 // empty' "$CONFIG")"
if [ -n "$keyboard" ]; then
  pass "profiles[0].virtual_hid_keyboard.keyboard_type_v2 = $keyboard"
else
  fail "profiles[0].virtual_hid_keyboard.keyboard_type_v2 is missing"
fi

# 6. Each generated file matches the live one, apart from formatting.
compare_live() { # compare_live <name> <live path> <built path>
  local name="$1" live="$2" built="$3"
  if [ ! -f "$live" ]; then
    fail "live $name not found at $live"
    return
  fi
  if ! jq -S . "$live" >"$WORK/$name.live.json" 2>/dev/null; then
    fail "live $name is not valid JSON"
    return
  fi
  jq -S . "$built" >"$WORK/$name.built.json"
  if diff -q "$WORK/$name.live.json" "$WORK/$name.built.json" >/dev/null; then
    pass "built $name matches the live file (ignoring formatting)"
  else
    changed="$(diff "$WORK/$name.live.json" "$WORK/$name.built.json" | grep -c '^[<>]')"
    fail "built $name differs from the live file ($changed lines; < live, > built). First differences:"
    diff "$WORK/$name.live.json" "$WORK/$name.built.json" | head -20
  fi
}
compare_live karabiner.json "$ROOT/karabiner.json" "$CONFIG"
compare_live bindings.json "$ROOT/hyperdash/bindings.json" "$BINDINGS"

# 7. The Hammerspoon CLI that Hyper+S+Q calls.
if [ ! -x "$HS" ]; then
  fail "$HS does not exist or is not executable"
else
  run=()
  command -v gtimeout >/dev/null && run=(gtimeout 5)
  if reply="$(${run[@]+"${run[@]}"} "$HS" -c 'return type(hyperdash.toggle)' 2>&1)" && [ "$reply" = function ]; then
    pass "$HS runs and hyperdash.toggle is a function"
  else
    fail "$HS -c 'return type(hyperdash.toggle)' did not return \"function\": ${reply:-no output}"
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%d check(s) failed. Nothing in %s was modified.\n' "$failures" "$ROOT"
  exit 1
fi
printf '\nAll checks passed.\n'
