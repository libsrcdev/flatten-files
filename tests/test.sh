#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$repo_dir/bin/flatten-files"

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/flatten-files-test.XXXXXXXX")
trap 'rm -rf "$sandbox"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "expected file: $1"; }
assert_missing() { [[ ! -e "$1" && ! -L "$1" ]] || fail "expected missing: $1"; }
assert_content() { [[ "$(cat "$1")" == "$2" ]] || fail "wrong content in: $1"; }

bash -n "$script" || fail 'script syntax'
bash -n "$repo_dir/install.sh" || fail 'installer syntax'

# Installation should be repeatable and avoid duplicate PATH lines.
mkdir -p "$sandbox/home"
HOME="$sandbox/home" bash "$repo_dir/install.sh" > /dev/null
assert_file "$sandbox/home/.local/bin/flatten-files"
cmp -s "$script" "$sandbox/home/.local/bin/flatten-files" || fail 'installer did not copy script'
HOME="$sandbox/home" bash "$repo_dir/install.sh" > /dev/null
[[ "$(grep -Fc 'export PATH="$HOME/.local/bin:$PATH"' "$sandbox/home/.zshrc")" == 1 ]] || fail 'PATH line duplicated'
printf 'PASS: install and reinstall\n'

# Exercise the documented stdin installer without requiring a published repo.
mkdir -p "$sandbox/mock-bin" "$sandbox/remote-home" "$sandbox/unrelated"
cat > "$sandbox/mock-bin/curl" <<'MOCK'
#!/bin/bash
set -eu
[[ "$*" == *https://raw.githubusercontent.com/libsrcdev/flatten-files/main/bin/flatten-files* ]]
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --output ]]; then
    shift
    case "${DOWNLOAD_MODE:-success}" in
      failure) printf partial > "$1"; exit 22 ;;
      empty) : > "$1" ;;
      invalid) printf 'if\n' > "$1" ;;
      success) cp "$DOWNLOAD_SOURCE" "$1" ;;
    esac
    exit 0
  fi
  shift
done
exit 2
MOCK
chmod +x "$sandbox/mock-bin/curl"
remote_install() {
  (cd "$sandbox/unrelated" &&
    HOME="$sandbox/remote-home" PATH="$sandbox/mock-bin:$PATH" \
      DOWNLOAD_SOURCE="$script" DOWNLOAD_MODE="$1" \
      bash -s -- --remote < "$repo_dir/install.sh")
}
remote_install success > /dev/null
cmp -s "$script" "$sandbox/remote-home/.local/bin/flatten-files" || fail 'remote install content'
[[ -x "$sandbox/remote-home/.local/bin/flatten-files" ]] || fail 'remote install not executable'
remote_install success > /dev/null
[[ "$(grep -Fc 'export PATH="$HOME/.local/bin:$PATH"' "$sandbox/remote-home/.zshrc")" == 1 ]] || fail 'remote PATH line duplicated'
for mode in failure empty invalid; do
  if remote_install "$mode" > /dev/null 2>&1; then
    fail "remote install accepted $mode download"
  fi
  cmp -s "$script" "$sandbox/remote-home/.local/bin/flatten-files" || fail 'failed download replaced installed script'
done
[[ -z "$(find "$sandbox/remote-home/.local/bin" -name '.flatten-files.*' -print)" ]] || fail 'staging file leaked'
rm "$sandbox/remote-home/.local/bin/flatten-files"
ln -s "$script" "$sandbox/remote-home/.local/bin/flatten-files"
if remote_install success > /dev/null 2>&1; then
  fail 'remote install replaced symlink'
fi
[[ -L "$sandbox/remote-home/.local/bin/flatten-files" ]] || fail 'remote install removed symlink'
printf 'PASS: remote install, reinstall, download failures, and symlink guard\n'

root="$sandbox/fixture"
mkdir -p "$root/a" "$root/b/deep" "$root/.git" "$root/b/.venv" "$root/empty/child" "$sandbox/external"
printf original > "$root/photo.jpg"
printf from_a > "$root/a/photo.jpg"
printf from_b > "$root/b/deep/photo.jpg"
printf special > "$root/a/space name.txt"
printf dotfile > "$root/a/.env"
printf newline > "$root/a/line"$'\n'"break.txt"
printf project > "$root/.git/config"
printf hidden > "$root/b/.venv/do-not-touch"
printf outside > "$sandbox/external/outside.txt"
ln -s "$sandbox/external/outside.txt" "$root/a/shortcut.txt"

# Pure preview must never touch the fixture.
(cd "$root" && "$script" > "$sandbox/preview.txt")
grep -q 'Would move' "$sandbox/preview.txt" || fail 'dry run did not show file moves'
assert_file "$root/a/photo.jpg"
assert_file "$root/b/deep/photo.jpg"
assert_missing "$root/photo (1).jpg"
printf 'PASS: dry run\n'

# Move, handle collisions, and remove newly emptied visible directories.
(cd "$root" && "$script" --apply --clean-empty > "$sandbox/apply.txt")
assert_content "$root/photo.jpg" original
assert_file "$root/photo (1).jpg"
assert_file "$root/photo (2).jpg"
[[ "$(cat "$root/photo (1).jpg")$(cat "$root/photo (2).jpg")" == from_afrom_b || "$(cat "$root/photo (1).jpg")$(cat "$root/photo (2).jpg")" == from_bfrom_a ]] || fail 'collisions lost content'
assert_content "$root/space name.txt" special
assert_content "$root/.env" dotfile
assert_content "$root/line"$'\n'"break.txt" newline
assert_missing "$root/a/photo.jpg"
assert_missing "$root/empty"
assert_missing "$root/b/deep"
assert_file "$root/.git/config"
assert_file "$root/b/.venv/do-not-touch"
[[ -L "$root/a/shortcut.txt" ]] || fail 'symlink was moved or deleted'
assert_content "$sandbox/external/outside.txt" outside
printf 'PASS: flatten, collision suffixes, cleanup, hidden dirs, symlinks\n'

# Repeated execution is idempotent.
(cd "$root" && "$script" --apply > "$sandbox/again.txt")
grep -q 'Finished: 0 moved, 0 failed' "$sandbox/again.txt" || fail 'second flatten changed files'
printf 'PASS: idempotent flatten\n'

# Independent cleanup command: preview should not remove anything.
mkdir -p "$sandbox/clean/x/y" "$sandbox/clean/keep"
printf keep > "$sandbox/clean/keep/data"
(cd "$sandbox/clean" && "$script" clean > "$sandbox/clean-preview.txt")
[[ -d "$sandbox/clean/x/y" ]] || fail 'clean preview removed directory'
(cd "$sandbox/clean" && "$script" clean --apply > "$sandbox/clean-apply.txt")
assert_missing "$sandbox/clean/x"
assert_file "$sandbox/clean/keep/data"
printf 'PASS: clean preview and apply\n'

# Prevent accidental operation directly in $HOME.
mkdir -p "$sandbox/home/nested"
printf keep > "$sandbox/home/nested/homefile.txt"
if (cd "$sandbox/home" && HOME="$sandbox/home" "$script" --apply > /dev/null 2>&1); then
  fail 'home guard should refuse modification'
fi
assert_file "$sandbox/home/nested/homefile.txt"
printf 'PASS: home-directory guard\n'

printf '\nAll tests passed.\n'
