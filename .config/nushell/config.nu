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
alias l = eza -l --colour=always --icons=always
alias ll = eza -lah --colour=always --icons=always --group-directories-first
alias la = eza -a --colour=always --icons=always
alias vi = nvim
alias skim = ^/Applications/Skim.app/Contents/MacOS/Skim

# `ls` plus a git column in repos, in the prompt's symbols: + staged,
# ! modified, ? untracked, with counts on folders. --ignored adds gray !.
def ls-git [pattern: glob = ".", --all (-a), --ignored] {
  let files = (if $all { ls -a $pattern } else { ls $pattern })
  let top = (do -i { ^git rev-parse --show-toplevel } | complete)
  if $top.exit_code != 0 { return $files }
  let root = ($top.stdout | str trim)
  let changes = (^git status --porcelain=v1 --untracked-files=all ...(if $ignored { [--ignored] } else { [] }) -z
    | split row (char nul)
    | where {|l| ($l | str length) > 3 and ($l | str substring 2..2) == " " }
    | each {|l|
      let x = ($l | str substring 0..0)
      let y = ($l | str substring 1..1)
      {path: ($root | path join ($l | str substring 3.. | str trim --right --char "/"))
       staged: ($x not-in [" " "?" "!"]) modified: ($y in [M D]) untracked: ($x == "?") ignored: ($x == "!")}
    })
  let kinds = [[flag symbol color]; [staged "+" 178] [modified "!" 178] [untracked "?" 39] [ignored "!" 244]]
  $files | insert git {|f|
    let full = ($f.name | path expand --no-symlink)
    let mine = ($changes | where {|c| $c.path == $full or ($c.path | str starts-with $"($full)/") })
    $kinds | each {|k|
      let n = ($mine | where {|c| $c | get $k.flag } | length)
      if $n > 0 {
        let text = (if $f.type == dir and $k.flag != ignored { $"($k.symbol)($n)" } else { $k.symbol })
        $"(ansi -e $'38;5;($k.color)m')($text)(ansi reset)"
      }
    } | compact | str join " "
  } | reject type | metadata set --path-columns [name]
}
alias lg = ls-git

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
    commandline edit --insert ($picked | to nuon)
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
  if ($now - $last) <= 500ms {
    $env.SUDO_ESCAPE_LAST = ($now - 1day)
    let line = (commandline)
    let line = if ($line | is-empty) { history | last | get command? | default "" } else { $line }
    commandline edit --replace (if ($line | str starts-with "sudo ") { $line | str substring 5.. } else if $line == "sudo" { "" } else { $"sudo ($line)" })
  }
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

# Prompt path colored as p10k does it: `~`, the current folder and project
# roots (p10k's anchor files) bold tan, the rest teal. starship prints it.
const anchor_files = [.bzr .citc .git .hg .node-version .python-version .go-version .ruby-version .lua-version .java-version .perl-version .php-version .tool-versions .mise.toml .shorten_folder_marker .svn .terraform CVS Cargo.toml composer.json go.mod package.json stack.yaml]
$env.config.hooks.pre_prompt ++= [{||
  let home = ($env.PWD == $nu.home-dir or ($env.PWD | str starts-with $"($nu.home-dir)/"))
  let base = if $home { $nu.home-dir } else { "/" }
  let names = if $env.PWD == $base { [] } else { $env.PWD | path relative-to $base | path split }
  let tan = (ansi -e "1;38;5;11m")
  let teal = (ansi -e "38;5;14m")
  mut dir = $base
  mut out = if $home { $"($tan)~(ansi reset)" } else { "" }
  for i in 0..<($names | length) {
    $dir = ($dir | path join ($names | get $i))
    let d = $dir
    let anchor = ($i == ($names | length) - 1) or ($anchor_files | any {|f| $d | path join $f | path exists })
    $out += $"($teal)/(if $anchor { $tan } else { $teal })($names | get $i)(ansi reset)"
  }
  $env.PROMPT_DIR = if ($out | is-empty) { $"($tan)/(ansi reset)" } else { $out }
}]

# Completions for other CLIs (git, brew, mise...) through carapace,
# falling back to the zsh completions oh-my-zsh already has.
$env.CARAPACE_BRIDGES = "zsh,fish,bash"

# Tools generate nu init scripts into the autoload folder (outside this
# repo), loaded after this file. Only missing scripts are generated;
# update_tools deletes them after upgrades.
const autoload = ($nu.data-dir | path join "vendor" "autoload")
mkdir $autoload

def --wrapped init-script [file: string, tool: string, ...args: string] {
  if ($autoload | path join $file | path exists) or (which $tool | is-empty) { return null }
  let r = (run-external $tool ...$args | complete)
  if $r.exit_code == 0 { return $r.stdout }
  print -e $"($tool) init failed: ($r.stderr | str trim)"
  null
}

def save-init [file: string] {
  let script = $in
  if $script != null { $script | save --force ($autoload | path join $file) }
}

init-script mise.nu mise activate nu | save-init mise.nu
init-script starship.nu starship init nu | save-init starship.nu
# carapace 1.8 still passes spans positionally, which nu 0.116 deprecates.
let carapace = (init-script carapace.nu carapace _carapace nushell)
if $carapace != null { $carapace | str replace "{|spans|" "{|place| let spans = $place.command" | save-init carapace.nu }
# atuin: Ctrl+R history, shared with zsh. Up stays nu's own history.
init-script atuin.nu atuin init nu --disable-up-arrow | save-init atuin.nu
# zoxide: `z <part of a path>` jumps to a folder visited before
init-script zoxide.nu zoxide init nushell | save-init zoxide.nu
