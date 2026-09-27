eval "$(/opt/homebrew/bin/brew shellenv)"

# PATH lives here: this runs after /etc/zprofile's path_helper, so the
# order holds, and only once per login instead of in every nested shell.
path=(
  $HOME/.local/bin     # own scripts, agent CLIs
  $HOME/.cargo/bin     # rustup, cargo install
  $HOME/.go/bin        # go install
  $path
)
eval "$(mise activate zsh --shims)"   # non-interactive shells, IDEs, agents
