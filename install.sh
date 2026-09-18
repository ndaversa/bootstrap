#!/bin/sh
# Bootstrap a Mac from empty to the state described by this repo. Safe to rerun: every step checks
# before acting, and steps that need a human print what to do and wait.
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ndaversa/bootstrap/main/install.sh)"
#
# This repo is private, so a Mac with no credentials yet cannot read it. bin/publish-bootstrap
# copies this file to the public ndaversa/bootstrap repo; run it after changing anything here,
# and keep secrets and private details out of this file.
set -eu
say()  { printf '\n[chez-nino] %s\n' "$*"; }
todo() { printf '\n[chez-nino] ACTION NEEDED: %s\n' "$*"; }
# wait_for <what to do> <shell test>: nag until the test passes
wait_for() {
  until sh -c "$2" >/dev/null 2>&1; do
    todo "$1"; printf '  press return to check again... '; read -r _ </dev/tty
  done
}
AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

say "1/7 Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  wait_for "Finish the Command Line Tools installer window" "xcode-select -p"
fi
# Accept the Xcode license (needed for git, compilers, etc.)
if ! /usr/bin/xcrun clang --version >/dev/null 2>&1; then
  say "Accepting Xcode license (requires sudo)"
  sudo xcodebuild -license accept
fi

say "2/7 Homebrew"
if [ ! -x /opt/homebrew/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

say "3/7 Apps that everything else depends on"
[ -d /Applications/1Password.app ] || brew install --cask 1password
[ -d /Applications/iTerm.app ]     || brew install --cask iterm2
command -v op      >/dev/null 2>&1 || brew install --cask 1password-cli
command -v chezmoi >/dev/null 2>&1 || brew install chezmoi

say "4/7 1Password: SSH agent and CLI"
open -a 1Password
wait_for "In 1Password: sign in, then Settings > Developer: turn on 'Use the SSH agent' and 'Integrate with 1Password CLI'" \
  "SSH_AUTH_SOCK='$AGENT_SOCK' ssh-add -l"
export SSH_AUTH_SOCK="$AGENT_SOCK"
# 'op whoami' only reports a session; listing vaults is what makes 1Password raise its approval dialog
wait_for "Approve the '1Password CLI wants access' dialog that 1Password shows (Settings > Developer > 'Integrate with 1Password CLI' must be on)" "op vault list"
wait_for "Give the GitHub SSH key access to this app (1Password will ask on first use)" \
  "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q 'successfully authenticated'"

say "5/7 Sign in to the Mac App Store (mas installs need it)"
wait_for "Open the App Store app and sign in" "true"

say "6/7 chezmoi: clone ~/dev/chez-nino and apply (asks a few questions once; brew bundle takes a while)"
src="$HOME/dev/chez-nino"
if [ -d "$HOME/dev/dotfiles/.git" ] && [ ! -e "$src" ]; then
  # The repo used to be called dotfiles: move the checkout and point it at the new name.
  mv "$HOME/dev/dotfiles" "$src"
  git -C "$src" remote set-url origin git@github.com:ndaversa/chez-nino.git
  git -C "$src" worktree repair >/dev/null 2>&1 || true
fi
if [ -d "$src/.git" ]; then
  # Existing machine (including ones set up with the old bin/configure): pull, then converge.
  git -C "$src" pull --ff-only
  chezmoi init --source "$src" --apply
else
  chezmoi init --ssh --source "$src" --apply ndaversa/chez-nino
fi

say "7/7 Sign-ins that only a person can do"
command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1 && gh auth login -h github.com -p ssh -w
if command -v claude >/dev/null 2>&1; then todo "Run 'claude' once to sign in to Claude Code"; fi
if [ -d /Applications/Codex.app ] || command -v codex >/dev/null 2>&1; then todo "Run 'codex login' once"; fi
[ -x /usr/local/bin/1password-mcp ] || todo "1Password > Settings > Developer: install the MCP server (puts 1password-mcp in /usr/local/bin) for the Codex/Claude 1Password integration"
todo "Quit and reopen iTerm2 so it picks up the 'Nino' profile as default (then delete the old 'Default' profile if you like)"
say "Done. From now on: 'chezmoi update' pulls the repo and converges this machine."
