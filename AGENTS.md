# dotfiles

Live configuration for one Mac, managed with GNU stow. This repo is the
source; the files in `~` are links into it. The repo is **public**.

## Never

- Commit a secret. Keys come from the macOS Keychain at runtime
  (`.zshenv`) or through `{env:NAME}` references (opencode). Scan the
  staged diff for key-shaped strings before every commit.
- Stage by directory from `~`. Stage by path, inside this repo.
- Run `stow` for real before its dry run (`stow -n -v .`) shows no
  conflicts.

## Ask first

Commit and push only with the user's approval, one logical change per
commit. Subjects follow the repo history: `chore: ...` or `feat: ...`.

## Layout

The tree mirrors `~`: `.zshrc` links to `~/.zshrc`,
`.config/nvim/init.lua` to `~/.config/nvim/init.lua`. `stow .` run here
links into the parent folder, `~`. `.stow-local-ignore` keeps repo-only
files (this one included) out of `~`; `.gitignore` keeps app state out
of git.

**Folder links.** atuin, Karabiner, LinearMouse, mise, nushell,
OpenLogi and Zed are linked as whole folders (`~/.config/<app>`)
because each rewrites its own files, which turns a file link back into
a plain file. Their state (backups, history, sockets, conversations)
lives in the repo folder and is gitignored. clangd's config sits at
`Library/Preferences/clangd`, the only path clangd reads on macOS.

## Adding a config

1. Move the file to the same path inside this repo.
2. `stow -n -v .`, then `stow -v .`.
3. `git status` shows the new file; commit it by path.

For an app that rewrites its own config, move the whole folder and
link it the same way. Quit the app first and stow in the same command:
a running app recreates a default folder within seconds, and
`stow --adopt` would then pull that default over the real config.

## New Mac

```sh
git clone https://github.com/xeind/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && brew bundle && stow -v .
mise trust ~/.dotfiles && mise install
# zsh prompt: oh-my-zsh loads powerlevel10k from its custom themes
RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
# herdr agent-state hooks: prefix+a and the tab bar's blocked count need them
herdr integration install claude && herdr integration install codex && herdr integration install pi
```

## Recovery

- **Link turned into a plain file**: `stow -n -v .` reports the
  conflict. Copy the plain file over the repo copy if it is newer,
  remove it, and stow again.
- **Karabiner running the wrong config** after its folder changed:
  `launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server`,
  then check `~/.local/share/karabiner/log/console_user_server.log`
  for a fresh `Load ... karabiner.json`.
- `stow -D .` removes every link and leaves the repo intact.

## Gotchas

- `.zshenv` sets `XDG_CONFIG_HOME=~/.config`; without it lazygit and
  nushell read `~/Library/Application Support` and ignore this repo.
- New Ghostty tabs and herdr panes run `.local/bin/terminal_shell`:
  a login zsh (PATH, XDG, keys) that execs nu, so `.zshrc` never runs
  there. Put env vars every shell needs in `.zshenv`. zsh stays the
  login shell and the shell agents run commands in.
- nu writes its tool init scripts (mise, starship, carapace, atuin,
  zoxide) to `~/Library/Application Support/nushell/vendor/autoload`
  only when missing; `update_tools` deletes them after upgrades. Its
  config folder also holds `history.sqlite3*`, gitignored: keep it so.
- Headless nvim loads lazy.nvim, which can update plugins and rewrite
  `lazy-lock.json`. Copy the lockfile before any nvim run and compare
  after.
- `.config/starship.toml` is nushell's prompt only; zsh uses p10k
  (`.p10k.zsh`). The starship config copies p10k's layout and colors.
- Zed's Context7 key is optional and stored in the Keychain as
  `context7-api-key-zed`; `settings.json` carries no key.
- mise resolves `~/.config/mise` to its path in this repo and refuses
  an untrusted config, so node, go and bun vanish. On a new Mac run
  `mise trust ~/.dotfiles` after the first stow.
- Git's global config is `.config/git/config`; `~/.gitconfig` must not
  exist, or git writes there instead.
- Karabiner's `karabiner.json` is built from `rules.ts` (`yarn build`
  in `.config/karabiner`). Edit the TypeScript, then rebuild.

## Installing tools

Runtimes and CLIs go through mise (`mise use -g <tool>`, or the
`github:`, `npm:`, `cargo:`, `go:` backends), Python tools through
`uv tool install`, GUI apps through Homebrew, recorded in `Brewfile`
(`brew bundle dump --force --tap --formula --cask --mas`). Agent CLIs (Claude Code,
Codex, opencode, pi) keep their own installers and
updaters. A tool that asks for a PATH line gets a symlink in
`~/.local/bin` instead. PATH is set only in `.zprofile`.
`update_tools` (`.local/bin/update_tools`) runs every updater.

Exceptions in `.config/mise/config.toml`, each on purpose:
- `neovim = "0.12.2"`: held back on purpose; bump by hand.
- `@typescript/native-preview` is pinned because it publishes only dev
  builds, which mise skips; bump the pin by hand.
- deno comes from Homebrew because yt-dlp depends on it.

Agent instructions and skills live in `~/.agents`, outside this repo.
