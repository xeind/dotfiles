#!/bin/bash
# Bind Rectangle actions to ⌃⌥⌘ + key. rectangle() in utils.ts sends these
# chords from the Hyper w layer. Keep the two lists in step.
# Usage: quit Rectangle, run this script, then open Rectangle.
set -euo pipefail

DOMAIN=com.knollsoft.Rectangle
MODIFIERS=1835008 # ⌃ 262144 + ⌥ 524288 + ⌘ 1048576

# Rectangle action, macOS virtual key code
BINDINGS=(
  "topLeftSixth 18"       # 1
  "topRightSixth 20"      # 3
  "previousDisplay 16"    # y
  "nextDisplay 31"        # o
  "topHalf 40"            # k
  "bottomHalf 38"         # j
  "leftHalf 4"            # h
  "rightHalf 37"          # l
  "maximize 3"            # f
  "topRight 14"           # e
  "topLeft 12"            # q
  "bottomLeft 0"          # a
  "bottomRight 2"         # d
  "center 1"              # s
  "specified 7"           # x
  "moveUp 126"            # up arrow
  "moveDown 125"          # down arrow
  "moveRight 124"         # right arrow
  "moveLeft 123"          # left arrow
  "bottomLeftSixth 6"     # z
  "bottomRightSixth 8"    # c
  "almostMaximize 36"     # return
  "restore 51"            # delete
  "larger 24"             # =
  "smaller 27"            # -
)

for binding in "${BINDINGS[@]}"; do
  read -r action key_code <<< "$binding"
  defaults write "$DOMAIN" "$action" -dict keyCode -int "$key_code" modifierFlags -int "$MODIFIERS"
done
