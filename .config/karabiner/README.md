# Karabiner Hyper Key Layer Map
Based on @maxstbr's Karabiner setup, I built a personal system optimized around mnemonic layers, window navigation, productivty workflows, and minimal hand movement.

The *Hyper Key*, or `Ctrl+Opt+Shift+Cmd`, acts as a universal layer key, unlocking submaps for:
- *V*im-style Movement 
- *W*indow Control
- *O*pening Applications
- *B*rowser Sites
- *C*lipboard Actions 
- *S*ystem Settings
- *R*aycast Actions

## Controls

# Hyper + V (Vim-style)
| Key        | Action             | Mapping                                  |
|------------|--------------------|------------------------------------------|
| h          | Move Left          | ←                                        |
| j          | Move Down          | ↓                                        |
| k          | Move Up            | ↑                                        |
| l          | Move Right         | →                                        |
| u          | Page Down          | PageDown                                 |
| i          | Page Up            | PageUp                                   |
| q          | Mouse Button 1     | Left Click                               |
| e          | Mouse Button 2     | Right Click                              |
| spacebar   | [ Homerow ](https://homerow.app) Clicking  | Ctrl+Cmd+F1      |
| s          | [ Homerow ](https://homerow.app) Scroll   | Ctrl+Cmd+F2       |
| f          | [ Homerow ](https://homerow.app) Find     | Ctrl+Cmd+F3    |

# Hyper + B (Browser)
| Key | Destination            | URL                                           |
|-----|------------------------|-----------------------------------------------|
| x   | Open X (Twitter)       | https://x.com                                 |
| y   | Open YouTube           | https://youtube.com                           |
| f   | Open Facebook          | https://facebook.com                          |
| g   | Open GitHub            | https://github.com                            |
| r   | Open Reddit            | https://reddit.com                            |
| c   | Open ChatGPT           | https://chatgpt.com                           |
| d   | Open DeepSeek Chat     | https://chat.deepseek.com                     |
| t   | Open Monkeytype        | https://monkeytype.com                        |
| m   | Open Gmail             | https://mail.google.com/mail/u/0/#inbox       |
| p   | Open Google Photos     | https://photos.google.com/u/3/                |
| k   | Open Keybr             | https://keybr.com                             |

# Hyper + O (Open)
| Key | Application           | Function                     |
|-----|------------------------|------------------------------|
| 1   | Bitwarden             | Open password manager        |
| c   | Google Chrome         | Launch Chrome browser        |
| b   | Firefox               | Launch Firefox browser       |
| z   | Zen Browser           | Launch Zen                   |
| v   | VS Code               | Launch code editor           |
| d   | Discord               | Launch Discord client        |
| t   | Ghostty               | Open terminal emulator       |
| m   | Obsidian              | Launch knowledge base        |
| f   | Finder                | Open file manager            |

# Hyper + W (Window)
| Key             | Action                   | Description                                 |
|------------------|--------------------------|---------------------------------------------|
| 1               | Top-Left Sixth           | Snap window to top-left sixth               |
| 3               | Top-Right Sixth          | Snap window to top-right sixth              |
| y               | Previous Display         | Move to previous monitor                    |
| o               | Next Display             | Move to next monitor                        |
| k               | Top Half                 | Top half of screen                          |
| j               | Bottom Half              | Bottom half of screen                       |
| h               | Left Half                | Snap to left                                |
| l               | Right Half               | Snap to right                               |
| f               | Maximize                 | Fullscreen window                           |
| e               | Top-Right Quarter        | Snap to top-right quarter                   |
| q               | Top-Left Quarter         | Snap to top-left quarter                    |
| a               | Bottom-Left Quarter      | Snap to bottom-left quarter                 |
| d               | Bottom-Right Quarter     | Snap to bottom-right quarter                |
| s               | Reasonable Size          | Resizes to ideal central bounds             |
| up_arrow        | Move Up                  | Move window up                              |
| down_arrow      | Move Down                | Move window down                            |
| right_arrow     | Move Right               | Move window right                           |
| left_arrow      | Move Left                | Move window left                            |
| z               | Bottom-Left Sixth        | Snap to bottom-left sixth                   |
| c               | Bottom-Right Sixth       | Snap to bottom-right sixth                  |
| return_or_enter | Almost Maximize          | Large but not full screen                   |
| delete_or_backspace | Restore              | Undo size/location changes                  |
| equal_sign      | Make Larger              | Increase window size                        |
| hyphen          | Make Smaller             | Decrease window size                        |
| ; (semicolon)   | Hide Window              | Send Cmd+H to hide                          |
| u               | Previous Tab             | Cmd+Ctrl+Shift+Tab                          |
| i               | Next Tab                 | Cmd+Ctrl+Tab                                |
| n               | Next Window              | Cmd+Tilde (~)                               |
| b               | Back Navigation          | Cmd+[                                       |
| m               | Forward Navigation       | Cmd+]                                       |

# Hyper + C (Clipboard/CleanShot X)
| Key                   | Action                  | Mapping                                      |
|------------------------|-------------------------|----------------------------------------------|
| a                    | Screenshot (All-Purpose) | Ctrl+Cmd+F12                                 |
| w                    | Screenshot Area          | Ctrl+Cmd+F11                                 |
| e                    | Screenshot Window        | Ctrl+Cmd+F10                                 |
| q                    | Screenshot Screen        | Ctrl+Cmd+F9                                  |
| d                    | Scrollshot               | Ctrl+Cmd+F8                                  |
| s                    | OCR Text                 | Ctrl+Cmd+F7                                  |
| k                    | Open Clipboard           | Ctrl+Cmd+F6                                  |
| z                    | Close Overlays           | Ctrl+Cmd+F5                                  |
| delete_or_backspace  | Clipboard History        | Ctrl+Cmd+F4                                  |

# Hyper + S (System)
| Key | Action                     | Mapping / Command                                         |
|-----|-----------------------------|------------------------------------------------------------|
| u   | Volume Up                 | `volume_increment`                                        |
| j   | Volume Down               | `volume_decrement`                                        |
| i   | Brightness Up             | `display_brightness_increment`                            |
| k   | Brightness Down           | `display_brightness_decrement`                            |
| l   | Lock MacBook              | Cmd+Ctrl+Q                                                 |
| d   | Toggle DND                | Raycast Do-Not-Disturb extension                          |
| c   | Open Camera               | Raycast System → Camera                                   |
| r   | Recording Mode On         | `raycast://script-commands/recording-mode`                |
| t   | Recording Mode Off        | `raycast://script-commands/undo-recording-mode`           |

# Hyper + R (Raycast)
| Key | Action            | Command                                                      |
|-----|-------------------|--------------------------------------------------------------|
| c   | Color Picker      | Raycast: Color Picker Extension                              |
| j   | Dismiss All       | Raycast Script Command: Dismiss Notifications                |
| e   | Emoji Picker      | Raycast: Emoji & Symbols Extension                           |
