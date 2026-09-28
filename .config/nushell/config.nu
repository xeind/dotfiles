# Nushell, on trial beside zsh. zsh stays the login shell: start nu by
# typing `nu`, and it inherits PATH, keys and env from that zsh.

$env.config.show_banner = false
$env.config.buffer_editor = "nvim"
$env.config.history.file_format = "sqlite"

alias vi = nvim

# mise: per-directory tool versions, as in zsh. The generated file sits
# in nu's autoload folder, outside this repo, and loads after this file.
if (which mise | is-not-empty) {
  let mise_autoload = ($nu.data-dir | path join "vendor" "autoload")
  mkdir $mise_autoload
  ^mise activate nu | save --force ($mise_autoload | path join "mise.nu")
}
