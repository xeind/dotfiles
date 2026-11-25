import fs from "fs";
import { KarabinerRules } from "./types";
import {
  createHyperSubLayers,
  app,
  open,
  rectangle,
  tinycast,
  listSubLayerBindings,
  USAGE_LOG_DIR,
} from "./utils";

const rules: KarabinerRules[] = [
  // Define the Hyper key itself
  {
    description: "Hyper Key (⌃⌥⇧⌘)",
    manipulators: [
      {
        description: "Caps Lock -> Hyper Key",
        from: {
          key_code: "caps_lock",
          modifiers: {
            optional: ["any"],
          },
        },
        to: [
          {
            set_variable: {
              name: "hyper",
              value: 1,
            },
          },
        ],
        to_after_key_up: [
          {
            set_variable: {
              name: "hyper",
              value: 0,
            },
          },
        ],
        to_if_alone: [
          {
            key_code: "escape",
          },
        ],
        type: "basic",
      },
    ],
  },

  ...createHyperSubLayers({
    // spacebar: {
    //   to: [{ key_code: "f1", modifiers: ["left_control", "left_command"] }],
    // },

    // b = "B"rowse
    b: {
      x: open("https://x.com"),
      y: open("https://youtube.com"),
      f: open("https://facebook.com"),
      g: open("https://github.com"),
      r: open("https://reddit.com"),
      c: open("https://chatgpt.com"),
      m: open("https://mail.google.com/mail/u/0/#inbox"),
      p: open("https://photos.google.com/u/3/"),
      l: open("https://linkedin.com"),
      // d: open("https://chat.deepseek.com"),
      // t: open("https://monkeytype.com"),
      // k: open("https://keybr.com"),
    },

    // o = "Open" applications
    o: {
      1: app("Bitwarden"),
      b: app("Firefox"),
      z: app("Zen Browser"),
      d: app("Discord"),
      t: app("Ghostty"),
      r: app("Rex"),
      m: app("Obsidian"),
      f: app("Finder"),
      n: app("Things3"),
      p: app("Skim"),
      h: app("Helium"),
      // v: app("Visual Studio Code"),
      c: app("Zed"),
    },

    // w = "Window" via Rectangle.app
    w: {
      spacebar: { to: [{ key_code: "mission_control" }], description: "Mission Control" },
      // Rectangle chords; keep in step with scripts/configure_rectangle_shortcuts.sh
      1: rectangle("1", "top-left-sixth"),
      3: rectangle("3", "top-right-sixth"),
      y: rectangle("y", "previous-display"),
      o: rectangle("o", "next-display"),
      k: rectangle("k", "top-half"),
      j: rectangle("j", "bottom-half"),
      h: rectangle("h", "left-half"),
      l: rectangle("l", "right-half"),
      f: rectangle("f", "maximize"),
      e: rectangle("e", "top-right"),
      q: rectangle("q", "top-left"),
      a: rectangle("a", "bottom-left"),
      d: rectangle("d", "bottom-right"),
      s: rectangle("s", "center"),
      x: rectangle("x", "specified"),
      up_arrow: rectangle("up_arrow", "move-up"),
      down_arrow: rectangle("down_arrow", "move-down"),
      right_arrow: rectangle("right_arrow", "move-right"),
      left_arrow: rectangle("left_arrow", "move-left"),
      z: rectangle("z", "bottom-left-sixth"),
      c: rectangle("c", "bottom-right-sixth"),
      return_or_enter: rectangle("return_or_enter", "almost-maximize"),
      delete_or_backspace: rectangle("delete_or_backspace", "restore"),
      equal_sign: rectangle("equal_sign", "larger"),
      hyphen: rectangle("hyphen", "smaller"),
      semicolon: {
        description: "Window: Hide",
        to: [
          {
            key_code: "h",
            modifiers: ["right_command"],
          },
        ],
      },
      u: {
        description: "Window: Previous Tab",
        to: [
          {
            key_code: "tab",
            modifiers: ["right_control", "right_shift"],
          },
        ],
      },
      i: {
        description: "Window: Next Tab",
        to: [
          {
            key_code: "tab",
            modifiers: ["right_control"],
          },
        ],
      },
      n: {
        description: "Window: Next Window",
        to: [
          {
            key_code: "grave_accent_and_tilde",
            modifiers: ["right_command"],
          },
        ],
      },
      b: {
        description: "Window: Back",
        to: [
          {
            key_code: "open_bracket",
            modifiers: ["right_command"],
          },
        ],
      },
      m: {
        description: "Window: Forward",
        to: [
          {
            key_code: "close_bracket",
            modifiers: ["right_command"],
          },
        ],
      },
    },

    // Clipboard/ Screenshot
    c: {
      a: {
        description: "Screenshot all-purpose",
        to: [
          {
            key_code: "f12",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      w: {
        description: "Screenshot area",
        to: [
          {
            key_code: "f11",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      e: {
        description: "Screenshot window",
        to: [
          {
            key_code: "f10",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      q: {
        description: "Screenshot screen",
        to: [
          {
            key_code: "f9",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      d: {
        description: "Scrollshot",
        to: [
          {
            key_code: "f8",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      s: {
        description: "OCR Text",
        to: [
          {
            key_code: "f7",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      k: {
        description: "Open Clipboard",
        to: [
          {
            key_code: "f6",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      z: {
        description: "Close all Overlays",
        to: [
          {
            key_code: "f5",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
      delete_or_backspace: {
        description: "Open Clipboard History",
        to: [
          {
            key_code: "f4",
            modifiers: ["left_control", "left_command"],
          },
        ],
      },
    },

    // f = "Finder"
    f: {
      p: tinycast("p", "Copy Path"),
      o: tinycast("o", "Open in Finder"),
      r: tinycast("r", "Reveal Copied Path"),
    },

    // s = "System"
    s: {
      u: {
        to: [
          {
            key_code: "volume_increment",
          },
        ],
      },
      j: {
        to: [
          {
            key_code: "volume_decrement",
          },
        ],
      },
      i: {
        to: [
          {
            key_code: "display_brightness_increment",
          },
        ],
      },
      k: {
        to: [
          {
            key_code: "display_brightness_decrement",
          },
        ],
      },
      l: {
        to: [
          {
            key_code: "q",
            modifiers: ["right_control", "right_command"],
          },
        ],
        description: "Lock Screen",
      },
      n: {
        to: [{ shell_command: "if pgrep -qx MenuBarAgent; then osascript -e 'tell application \"System Events\" to tell process \"MenuBarAgent\"' -e 'repeat with g in every group of menu bar 1' -e 'set mi to menu bar item 1 of g' -e 'if (value of attribute \"AXIdentifier\" of mi) is \"com.apple.menuextra.clock\" then perform action \"AXPress\" of mi' -e 'end repeat' -e 'end tell'; else osascript -e 'tell application \"System Events\" to tell process \"ControlCenter\"' -e 'repeat with mi in every menu bar item of menu bar 1' -e 'if (value of attribute \"AXIdentifier\" of mi) is \"com.apple.menuextra.clock\" then perform action \"AXPress\" of mi' -e 'end repeat' -e 'end tell'; fi" }],
        description: "Open Notification Center",
      },
      m: {
        to: [{ shell_command: "osascript ~/.config/karabiner/scripts/dismiss_notifications.applescript" }],
        description: "Dismiss Notifications",
      },
      p: { ...app("System Settings"), description: "System Settings" },
      d: {
        // F19 is bound to "Turn Do Not Disturb On/Off" in System Settings
        to: [{ key_code: "f19" }],
        description: "Toggle Do Not Disturb",
      },
      c: tinycast("c", "Open Camera"),
      // Audio Hijack's "Clean Mic" session; the script starts or stops it while the app stays open
      v: {
        to: [{ shell_command: "~/.config/karabiner/scripts/toggle_clean_mic.sh" }],
        description: "Toggle Audio Hijack (Clean Mic)",
      },
      a: tinycast("a", "Toggle Awake"),
      h: tinycast("h", "Hold Screen On"),
      x: tinycast("x", "Screen Off"),
      r: {
        to: [{ shell_command: "osascript ~/.config/raycast/scripts/recording-mode.applescript" }],
        description: "Recording Mode (hide menu bar)",
      },
      t: {
        to: [{ shell_command: "osascript ~/.config/raycast/scripts/undo-recording-mode.applescript" }],
        description: "Undo Recording Mode (show menu bar)",
      },
      // hyperdash: shortcut usage dashboard (hammerspoon/hyperdash.lua)
      q: {
        to: [{ shell_command: "/opt/homebrew/bin/hs -c 'hyperdash.toggle()'" }],
        description: "hyperdash",
      },
    },

    // v = "moVe" which isn't "m" because we want it to be on the left hand
    // so that hjkl work like they do in vim
    v: {
      h: {
        to: [{ key_code: "left_arrow" }],
      },
      j: {
        to: [{ key_code: "down_arrow" }],
      },
      k: {
        to: [{ key_code: "up_arrow" }],
      },
      l: {
        to: [{ key_code: "right_arrow" }],
      },
      u: {
        to: [{ key_code: "page_down" }],
      },
      i: {
        to: [{ key_code: "page_up" }],
      },
      q: {
        to: [{ pointing_button: "button1" }],
      },
      e: {
        to: [{ pointing_button: "button2" }],
      },
      b: {
        description: "Move Word Left",
        to: [
          {
            key_code: "left_arrow",
            modifiers: ["left_option"],
          },
        ],
      },
      m: {
        description: "Move Word Right",
        to: [
          {
            key_code: "right_arrow",
            modifiers: ["left_option"],
          },
        ],
      },
      n: {
        description: "Delete Word",
        to: [
          {
            key_code: "delete_or_backspace",
            modifiers: ["left_option"],
          },
        ],
      },

      // Tockpad (mouseless control): its [hotkeys] in ~/.config/tockpad/config.toml bind
      // ctrl-cmd-f1 to click, f2 to scroll and f3 to search. Keep the two in step.
      spacebar: {
        description: "Tockpad: Click",
        to: [{ key_code: "f1", modifiers: ["left_control", "left_command"] }],
      },
      s: {
        description: "Tockpad: Scroll",
        to: [{ key_code: "f2", modifiers: ["left_control", "left_command"] }],
      },
      f: {
        description: "Tockpad: Search",
        to: [{ key_code: "f3", modifiers: ["left_control", "left_command"] }],
      },
    },

    // r = launcher (Tinycast)
    r: {
      e: tinycast("e", "Search Emoji"),
    },
  }),
];

fs.mkdirSync(USAGE_LOG_DIR, { recursive: true });
fs.writeFileSync(
  "hyperdash/bindings.json",
  JSON.stringify(listSubLayerBindings(rules), null, 2)
);

fs.writeFileSync(
  "karabiner.json",
  JSON.stringify(
    {
      global: {
        show_in_menu_bar: false,
      },
      profiles: [
        {
          name: "xein",
          complex_modifications: {
            rules,
          },
          virtual_hid_keyboard: {
            keyboard_type_v2: "ansi",
          },
        },
      ],
    },
    null,
    2
  )
);
