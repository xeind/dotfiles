# Nushell, opened by new terminal tabs through a login zsh (terminal_shell),
# so it inherits PATH, keys and env from that zsh.
# Set up to feel like .zshrc: same aliases, keys, fzf widgets, and a
# starship prompt laid out like p10k (.config/starship.toml).

$env.config.show_banner = false
$env.config.buffer_editor = "nvim"
$env.config.history.file_format = "sqlite"

# Colors: nightingale, as in nvim, ghostty and tmux.
const theme = ($nu.default-config-dir | path join "nightingale.nu")
source $theme

# Aliases from .zshrc. `ls` stays nu's own table; `l` is the eza view.
alias l = ^eza -l --colour=always --icons=always
alias ll = ^eza -lah --colour=always --icons=always --group-directories-first
alias la = ^eza -a --colour=always --icons=always
alias vi = nvim
alias skim = ^/Applications/Skim.app/Contents/MacOS/Skim

# Open files' folders (or folders) in Cling.
def cling [...paths: path] {
  let folders = $paths | each {|p| if ($p | path type) == dir { $p } else { $p | path dirname } }
  ^open -a Cling ...$folders
}

# fzf widgets, as zsh's `fzf --zsh` binds them:
# Ctrl+T insert a file path, Alt+C cd into a folder.
# Ctrl+R belongs to atuin, loaded below.
def fzf-file [] {
  let picked = (^fzf --walker=file,follow,hidden --walker-skip=.git,node_modules --scheme=path --height=40% --reverse
    | complete | get stdout | str trim)
  if ($picked | is-not-empty) {
    commandline edit --insert (if ($picked =~ '\s') { $"`($picked)`" } else { $picked })
  }
}

def --env fzf-cd [] {
  let picked = (^fzf --walker=dir,follow,hidden --walker-skip=.git,node_modules --scheme=path --height=40% --reverse
    | complete | get stdout | str trim)
  if ($picked | is-not-empty) { cd $picked }
}

# Esc Esc toggles `sudo ` in front of the line, or of the last command
# when the line is empty: oh-my-zsh's sudo plugin. Reedline has no
# two-key sequences, so every Esc still does its usual job (close a
# menu) and records its time; a second Esc within 500ms toggles.
def --env sudo-escape [] {
  let now = (date now)
  let last = ($env.SUDO_ESCAPE_LAST? | default ($now - 1day))
  $env.SUDO_ESCAPE_LAST = $now
  if ($now - $last) > 500ms { return }
  $env.SUDO_ESCAPE_LAST = ($now - 1day)
  let line = (commandline)
  let line = if ($line | is-empty) { history | last | get command } else { $line }
  commandline edit --replace (if ($line | str starts-with "sudo ") { $line | str substring 5.. } else { $"sudo ($line)" })
}

$env.config.keybindings ++= [
  { name: sudo_escape modifier: none keycode: escape mode: emacs
    event: [ { send: esc } { send: executehostcommand cmd: "sudo-escape" } ] }
  { name: fzf_file modifier: control keycode: char_t mode: [emacs vi_insert vi_normal]
    event: { send: executehostcommand cmd: "fzf-file" } }
  { name: fzf_cd modifier: alt keycode: char_c mode: [emacs vi_insert vi_normal]
    event: { send: executehostcommand cmd: "fzf-cd" } }
  # Ctrl+N / Ctrl+P step through completions, as bound in .zshrc.
  { name: completion_next_ctrl_n modifier: control keycode: char_n mode: [emacs vi_insert]
    event: { until: [ { send: menu name: completion_menu } { send: menunext } ] } }
  { name: completion_previous_ctrl_p modifier: control keycode: char_p mode: [emacs vi_insert]
    event: { until: [ { send: menu name: completion_menu } { send: menuprevious } ] } }
]

# Completions for other CLIs (git, brew, mise...) through carapace,
# falling back to the zsh completions oh-my-zsh already has.
$env.CARAPACE_BRIDGES = "zsh,fish,bash"

# mise (per-folder versions), starship (prompt) and carapace each
# generate a nu script. They go in nu's autoload folder, outside this
# repo, and load after this file.
let autoload = ($nu.data-dir | path join "vendor" "autoload")
mkdir $autoload
if (which mise | is-not-empty) { ^mise activate nu | save --force ($autoload | path join "mise.nu") }
if (which starship | is-not-empty) { ^starship init nu | save --force ($autoload | path join "starship.nu") }
if (which carapace | is-not-empty) { ^carapace _carapace nushell | save --force ($autoload | path join "carapace.nu") }
# atuin: Ctrl+R history, shared with zsh. Up stays nu's own history.
if (which atuin | is-not-empty) { ^atuin init nu --disable-up-arrow | save --force ($autoload | path join "atuin.nu") }
# zoxide: `z <part of a path>` jumps to a folder visited before
if (which zoxide | is-not-empty) { ^zoxide init nushell | save --force ($autoload | path join "zoxide.nu") }
