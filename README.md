# flatten-files

A small, dependency-free CLI for **macOS** that moves files from nested folders into your **current working directory**. It preserves existing filenames by adding numeric suffixes (` (1)`, ` (2)`, …), and it can clean up empty folders afterward.

**Preview first. Nothing moves or gets removed unless you pass `--apply`.**

## Install

Requires macOS and the system-provided Bash (3.2 or newer) and curl. No Homebrew or clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/libsrcdev/flatten-files/main/install.sh | bash -s -- --remote
source ~/.zshrc
```

This downloads and runs the installer, which fetches `flatten-files` from GitHub, places it in `~/.local/bin`, and adds that directory to your zsh PATH once. To **update or reinstall**, run the same command again.

The installer downloads from the `main` branch of `libsrcdev/flatten-files`.

### Install from a local checkout

```bash
git clone https://github.com/libsrcdev/flatten-files.git
cd flatten-files
bash install.sh
source ~/.zshrc
```

To update from your clone:

```bash
cd flatten-files
git pull
bash install.sh
```

Both installation methods replace the existing `~/.local/bin/flatten-files` file without duplicating the PATH entry. The installer checks the script's syntax before replacing the installed version and refuses to replace a symlink or directory at that destination. A failed download leaves an existing installation intact.

## Usage

Change into **the folder you want to flatten**, then run:

```bash
cd ~/Downloads/MyPhotos

flatten-files                        # preview file moves
flatten-files --apply                # move files into this directory
flatten-files clean                  # preview currently empty folders
flatten-files clean --apply          # remove empty folders (recursively)
flatten-files --apply --clean-empty  # move, then remove empty folders
flatten-files --help                 # show help
```

The script always uses your **current working directory** (`pwd`), not the folder where the script or repository is installed.

### Example

Before:

```text
MyPhotos/
├── photo.jpg
├── 2024/
│   ├── photo.jpg
│   └── vacation.png
└── 2025/
    └── photo.jpg
```

After `flatten-files --apply --clean-empty`:

```text
MyPhotos/
├── photo.jpg
├── photo (1).jpg
├── photo (2).jpg
└── vacation.png
```

Which nested file gets a particular suffix depends on filesystem traversal order. Contents are moved, not converted.

## Safety behavior

- **Dry-run by default.** `--apply` is required for all changes.
- **No intentional overwrites.** Existing destinations are checked, then `mv -n` adds another no-clobber safeguard.
- **Handles spaces and unusual filenames** through NUL-separated file lists and quoted paths.
- **Doesn't follow or move symbolic links.** Symlinks left in subfolders also keep those folders nonempty.
- **Skips hidden directory trees** such as `.git`, `.venv`, and `.config`. Hidden files inside visible directories are still included.
- **Doesn't descend into other mounted filesystems** (uses `find -xdev`).
- **Only removes genuinely empty folders** using `rmdir`; no `rm -rf` is used for folder cleanup.
- **Refuses changes directly within your home directory or `/`.** Subfolders of your home directory work normally.
- **Does not remove the current directory.** Empty-folder cleanup only affects descendants.
- If any file move fails, `--clean-empty` will **skip cleanup** and exit with an error.

### Important limitations

Flattening **destroys the original folder organization** and can break relative references, build structures, or projects. No undo log or automatic rollback is provided. Make a backup for important files and always review a dry run.

`flatten-files clean` previews folders that are **already empty**; additional parent folders may become empty and be removed after their children are removed. Similarly, `flatten-files --clean-empty` previews files and folders in their **current state**, not the exact future cleanup list.

Avoid running it in a repository, `node_modules` tree, or application folder: visible directories **are traversed**, including `node_modules` if present. The hidden-directory exclusion is not a general project-directory detector.

Concurrent filesystem changes, permission errors, very long filenames, or unusual filesystem behavior can prevent moves. No shell command is guaranteed risk-free.

## Test

From the repository root:

```bash
bash tests/test.sh
```

The test suite creates isolated temporary folders and covers dry-run behavior, duplicate names, hidden directories, symlinks, empty-folder cleanup, reinstall, and the home-directory guard. macOS-specific behavior should be verified on your own Mac before use with valuable files.

## Uninstall

```bash
rm "$HOME/.local/bin/flatten-files"
```

Optionally remove the `export PATH="$HOME/.local/bin:$PATH"` line from `~/.zshrc` if you no longer use `~/.local/bin` for any other tools.
