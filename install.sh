#!/bin/bash
# Install or reinstall flatten-files from a local checkout or GitHub on macOS.
set -euo pipefail

remote=0
case "${1:-}" in
  --remote) remote=1 ;;
  '') ;;
  *) printf 'Usage: bash install.sh [--remote]\n' >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then
  printf 'Usage: bash install.sh [--remote]\n' >&2
  exit 2
fi

bin_dir="$HOME/.local/bin"
target="$bin_dir/flatten-files"

if [[ "$remote" -eq 0 ]]; then
  repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
  source_file="$repo_dir/bin/flatten-files"
  if [[ ! -f "$source_file" ]]; then
    printf 'Error: missing %s. Use --remote to download from GitHub.\n' "$source_file" >&2
    exit 1
  fi
fi

if [[ -L "$target" || -d "$target" ]]; then
  printf 'Error: %s is a symlink or directory; refusing to replace it.\n' "$target" >&2
  exit 1
fi

mkdir -p "$bin_dir"
staging=$(mktemp "$bin_dir/.flatten-files.XXXXXXXX")
trap 'rm -f "$staging"' EXIT
if [[ "$remote" -eq 1 ]]; then
  curl --fail --silent --show-error --location \
    'https://raw.githubusercontent.com/libsrcdev/flatten-files/main/bin/flatten-files' \
    --output "$staging"
else
  cp "$source_file" "$staging"
fi
if [[ ! -s "$staging" ]]; then
  printf 'Error: installation source is empty.\n' >&2
  exit 1
fi
bash -n "$staging"
chmod 755 "$staging"
mv -f "$staging" "$target"

# macOS normally uses zsh. Only add the PATH line if missing.
profile="$HOME/.zshrc"
path_line='export PATH="$HOME/.local/bin:$PATH"'
touch "$profile"
if ! grep -Fqx "$path_line" "$profile"; then
  printf '\n%s\n' "$path_line" >> "$profile"
fi

printf 'Installed/updated: %s\n' "$target"
printf 'In this terminal run: source ~/.zshrc\n'
printf 'Then run: flatten-files --help\n'
