#!/bin/sh
# Sets up Stefan's Mac from empty: Homebrew, GitHub sign-in, Claude Code, then this repo through
# chezmoi (Terminal settings, Node, the media assistant, phone access, daily updates). Safe to
# rerun: every step checks before acting, and steps that need a person say what to do and wait.
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ndaversa/bootstrap/main/stefan.sh)"
#
# This repo is private, so a new Mac cannot read it before GitHub is signed in. bin/publish-bootstrap
# copies this file to the public ndaversa/bootstrap repo as stefan.sh; run it after changing
# anything here, and keep secrets and private details out of this file.
set -eu
say()  { printf '\n\033[1m[setup] %s\033[0m\n' "$*"; }
todo() { printf '\n\033[1;33m[setup] YOUR TURN: %s\033[0m\n' "$*"; }
src="$HOME/dev/chez-stefan"

say "Hi Stefan! This sets up your Mac. It takes 10-20 minutes."
printf '  When it asks for a password, type your Mac login password and press Return.\n'
printf '  Nothing shows while you type it; that is normal.\n'

say "1/6 Homebrew (the standard way to install Mac tools; also installs Apple's developer tools)"
if [ ! -x /opt/homebrew/bin/brew ]; then
  printf '  It will ask for your password, then to press Return.\n'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
command -v gh      >/dev/null 2>&1 || brew install --quiet gh
command -v chezmoi >/dev/null 2>&1 || brew install --quiet chezmoi

say "2/6 Google Chrome and your sign-ins"
[ -d "/Applications/Google Chrome.app" ] || brew install --cask --quiet google-chrome
# Offers the Claude extension (Chrome asks once before turning it on; see run_after_50-apps.sh).
ext_dir="$HOME/Library/Application Support/Google/Chrome/External Extensions"
mkdir -p "$ext_dir"
[ -f "$ext_dir/fcoeoabgfenejglbffodgkkbkcdhcgfn.json" ] ||
  printf '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }\n' > "$ext_dir/fcoeoabgfenejglbffodgkkbkcdhcgfn.json"
# Every sign-in below opens in Chrome, so being signed in there first makes each one a click.
export GH_BROWSER="open -a '/Applications/Google Chrome.app'"
# By path: a Chrome installed a moment ago is not yet known to macOS by name.
open -a "/Applications/Google Chrome.app" https://claude.ai https://github.com/login https://dognzb.cr || true
todo "In Chrome, sign in on the three tabs that just opened: Claude, GitHub and DOGnzb (skip any you're already signed in to).
  Then open Chrome's ⋮ menu (top right), click 'New extension added (Claude)', then Enable extension.
  (Not there? Quit Chrome with ⌘Q, open it again and look once more.) Press Return when done."
read -r _ </dev/tty

say "3/6 Sign in to GitHub (where your setup is stored)"
if ! gh auth status >/dev/null 2>&1; then
  printf '  Press Return twice to open GitHub in Chrome, then paste the code there (it is already copied).\n'
  gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key --clipboard </dev/tty
fi
gh auth setup-git --hostname github.com
# Accepts Nino's invitations to the setup repos (if any are waiting), then checks access to both.
have_access() {
  for id in $(gh api user/repository_invitations --jq '.[] | select(.repository.full_name ==
      "ndaversa/chez-stefan" or .repository.full_name == "ndaversa/media-assistant") | .id' 2>/dev/null); do
    gh api --method PATCH "user/repository_invitations/$id" >/dev/null 2>&1 && printf '  Accepted an invitation from Nino.\n'
  done
  gh repo view ndaversa/chez-stefan >/dev/null 2>&1 && gh repo view ndaversa/media-assistant >/dev/null 2>&1
}
until have_access; do
  todo "Your GitHub account ($(gh api user --jq .login 2>/dev/null)) can't see your setup yet. Ask Nino to give it access, then press Return."
  read -r _ </dev/tty
done

say "4/6 Claude Code"
[ -x "$HOME/.local/bin/claude" ] || curl -fsSL https://claude.ai/install.sh | bash
if [ ! -x "$HOME/.local/bin/claude" ]; then
  todo "Claude Code didn't install (internet hiccup?). Paste the same line into Terminal again."; exit 1
fi

say "5/6 Your setup (Terminal settings, Node, the media assistant, phone access, daily updates)"
[ -e "$src" ] && [ ! -d "$src/.git" ] && mv "$src" "$src.incomplete-$(date +%s)"  # an interrupted clone
if [ -d "$src/.git" ]; then
  git -C "$src" pull --ff-only --quiet || true
else
  mkdir -p "$HOME/dev"
  gh repo clone ndaversa/chez-stefan "$src" -- --quiet
fi
# chezmoi replaces these; keep any earlier copy just in case.
for f in .zshrc .zprofile; do
  if [ -f "$HOME/$f" ] && ! grep -q chez-stefan "$HOME/$f" && [ ! -e "$HOME/$f.before-chez-stefan" ]; then
    cp "$HOME/$f" "$HOME/$f.before-chez-stefan"
  fi
done
if ! chezmoi init --source "$src" --apply --force; then
  todo "A few parts didn't finish (see above). That's OK: Claude will sort them out next."
fi

say "6/6 Done with the installing. Now Claude takes over."
printf '  Chrome opens once to sign in to Claude. Then Claude finishes the setup with you\n'
printf '  and tells you the few things only you can do. You can stop any time and come back:\n'
printf '  open Terminal, type  setup  and press Return.\n'
# A fresh login shell loads the new Terminal settings (Homebrew, Node, the media/setup shortcuts),
# which the window this ran in has not; he stays in it once Claude exits.
# Not </dev/tty: Claude cannot watch /dev/tty itself (kqueue EINVAL); stdin already is the terminal.
exec /bin/zsh -lic 'cd ~/dev/chez-stefan && claude "get me set up"; exec /bin/zsh -l'
