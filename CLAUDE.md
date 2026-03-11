# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Single-file Bash CLI tool (`prepare-car-usb.sh`) that prepares USB music libraries for car stereos. Cleans filenames, removes junk files, shortens names, adds numeric prefixes, and optionally organizes files into artist folders.

Must remain compatible with **Bash >= 3.2** (macOS) and work on both GNU and BSD utilities.

## Running

```bash
./prepare-car-usb.sh --dry-run /path/to/usb        # preview
./prepare-car-usb.sh /path/to/usb                   # apply
./prepare-car-usb.sh --album-folders /path/to/usb   # organize into artist dirs
./prepare-car-usb.sh --max-length 40 --no-prefix --extensions mp3,flac /path/to/usb
```

## Linting

```bash
shellcheck prepare-car-usb.sh
```

## Portability Constraints

- No `${var,,}` (Bash 4+) — use `tr '[:upper:]' '[:lower:]'` via `to_lower()`
- No `sort -z` (BSD incompatible) — use shell glob for sorted directory listings
- No `paste` — use `tr '\n' ','` with `sed 's/,$//'`
- No GNU-specific sed (`\+`, `-r`) — use `sed -E` for ERE, which works on both GNU and BSD
- No `rename`, `perl`, `python`, `jq` — only standard coreutils
- Use `n=$((n + 1))` instead of `((n++))` to avoid `set -e` edge cases

## Script Architecture

The script runs a configurable pipeline in `main()`:

1. **remove_junk_files** — deletes dotfiles, `Thumbs.db`, `desktop.ini`
2. **organize_album_folders** — (optional, `--album-folders`) groups flat "Artist - Title" files into artist directories; skips purely numeric prefixes like "01 - Song"
3. **clean_and_shorten_filenames** — lowercases, strips special chars, truncates to `--max-length`
4. **add_numeric_prefixes** — (optional, default on) adds `001_` style prefixes per directory
5. **sync_changes** — flushes to disk

Step numbering is dynamic — `TOTAL_STEPS` and `CURRENT_STEP` adapt to enabled features.

Key patterns:
- `DRY_RUN` global flag gates all destructive operations (`rm`, `mv`, `mkdir`)
- `safe_move()` handles collisions gracefully (warns + skips, never overwrites)
- `find_unique_path()` appends `_N` suffixes to avoid collisions
- `is_audio_file()` checks against the configurable `EXTENSIONS` list
- `clean_name()` pipeline: lowercase → expand `&` → strip special chars → underscores → truncate
- `to_lower()` wraps `tr` for portable case conversion (replaces Bash 4+ `${var,,}`)
- Uses `find ... -print0` with `read -d ''` for safe filename handling
- Uses shell globs (not `sort -z`) for sorted per-directory file iteration
- Color output auto-detected (TTY check), disabled with `--no-color`
- Counters track junk/renamed/prefixed/grouped/skipped for summary output
