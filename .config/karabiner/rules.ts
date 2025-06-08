import fs from "fs";
import { KarabinerRules } from "./types";
import {
  createHyperSubLayers,
  app,
  open,
  rectangle,
  shell,
  raycastWindow,
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
    // b = "B"rowse
    b: {
      x: open("https://x.com"),
      y: open("https://youtube.com"),
      f: open("https://facebook.com"),
      g: open("https://github.com"),
      r: open("https://reddit.com"),
      c: open("https://chatgpt.com"),
      d: open("https://chat.deepseek.com"),
      t: open("https://monkeytype.com"),
      m: open("https://mail.google.com/mail/u/0/#inbox"),
      p: open("https://photos.google.com/u/3/"),
      k: open("https://keybr.com"),
    },

    // o = "Open" applications
    o: {
      1: app("Bitwarden"),
      c: app("Google Chrome"),
      b: app("Firefox"),
      z: app("Zen Browser"),
      v: app("Visual Studio Code"),
      d: app("Discord"),
      t: app("Ghostty"),
      m: app("Obsidian"),
      f: app("Finder"),
    },

    // w = "Window" via raycast.app
    w: {
      1: raycastWindow("top-left-sixth"),
      3: raycastWindow("top-right-sixth"),
      y: raycastWindow("previous-display"),
      o: raycastWindow("next-display"),
      k: raycastWindow("top-half"),
      j: raycastWindow("bottom-half"),
      h: raycastWindow("left-half"),
      l: raycastWindow("right-half"),
      f: raycastWindow("maximize"),
      e: raycastWindow("top-right-quarter"),
      q: raycastWindow("top-left-quarter"),
      a: raycastWindow("bottom-left-quarter"),
      d: raycastWindow("bottom-right-quarter"),
      s: raycastWindow("center"),
      x: raycastWindow("reasonable-size"),
      up_arrow: raycastWindow("move-up"),
      down_arrow: raycastWindow("move-down"),
      right_arrow: raycastWindow("move-right"),
      left_arrow: raycastWindow("move-left"),
      z: raycastWindow("bottom-left-sixth"),
      c: raycastWindow("bottom-right-sixth"),
      return_or_enter: raycastWindow("almost-maximize"),
      delete_or_backspace: raycastWindow("restore"),
      equal_sign: raycastWindow("make-larger"),
      hyphen: raycastWindow("make-smaller"),
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
      },
      d: open(
        `raycast://extensions/yakitrak/do-not-disturb/toggle?launchType=background`
      ),
      c: open("raycast://extensions/raycast/system/open-camera"),
      r: open(`raycast://script-commands/recording-mode`),
      t: open("raycast://script-commands/undo-recording-mode"),
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

      // Magicmove via homerow.app
      spacebar: {
        to: [{ key_code: "f1", modifiers: ["left_control", "left_command"] }],
      },
      s: {
        to: [{ key_code: "f2", modifiers: ["left_control", "left_command"] }],
      },
      f: {
        to: [{ key_code: "f3", modifiers: ["left_control", "left_command"] }],
      },
    },

    // r = "Raycast"
    r: {
      c: open("raycast://extensions/thomas/color-picker/pick-color"),
      j: open("raycast://script-commands/dismiss-notifications"),
      e: open(
        "raycast://extensions/raycast/emoji-symbols/search-emoji-symbols"
      ),
    },
  }),
];

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
        },
      ],
    },
    null,
    2
  )
);
