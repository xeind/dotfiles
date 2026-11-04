# Folder action sounds

`folder_action.sh` plays these after Hyper F P, F O and F R. Each
action has its own family, and every press picks a random file from it.

| Folder | Action | Sound |
| --- | --- | --- |
| `copy/` (6) | Hyper F P, copy path | soft 22 ms key |
| `open/` (7) | Hyper F O, open in Finder | short 13 ms tick |
| `reveal/` (8) | Hyper F R, reveal copied path | bright 28 ms click |
| `fail.wav` | any miss | deeper key, played twice |

All come from the key sounds embedded in Hex 3.3.0
(`/Applications/Hex.app`, by Christopher Langton), under the MIT
license in `LICENSE-hex.txt`. They were extracted from the app binary
because Hex ships no separate sound files.
