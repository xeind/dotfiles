# Static output of `brew shellenv` (~10 ms per login); re-check it after a Homebrew move.
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
export FPATH
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
[ -z "${MANPATH-}" ] || { export MANPATH="${MANPATH%"${MANPATH##*[!:]}"}"; export MANPATH=":${MANPATH#"${MANPATH%%[!:]*}"}"; }
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# PATH lives here: this runs after /etc/zprofile's path_helper, so the
# order holds, and only once per login instead of in every nested shell.
path=(
  $HOME/.local/share/mise/shims  # mise shims: non-interactive shells, IDEs, agents
  $HOME/.local/bin     # own scripts, agent CLIs
  $HOME/.cargo/bin     # rustup, cargo install
  $HOME/.go/bin        # go install
  /Applications/Ghostty.app/Contents/MacOS(N)  # ghostty CLI; shell integration is off
  $path
)
