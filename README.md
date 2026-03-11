# prepare-car-usb

![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/language-bash-blue)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey)
![Stars](https://img.shields.io/github/stars/vchebon/car-usb-prep?style=social)

A portable Bash CLI tool that prepares a USB music library for **car stereos**.

## The Problem

Most car stereos have limited filename support. Long filenames get truncated unpredictably, special characters cause display issues, and playback order depends on filesystem order rather than track names. Hidden junk files (`.DS_Store`, `Thumbs.db`) waste space and can confuse simple media players.

**prepare-car-usb** fixes all of this in one command.

## Features

- Removes hidden junk files (`.DS_Store`, `Thumbs.db`, `desktop.ini`, dotfiles)
- Cleans filenames: lowercases, strips special characters, normalizes separators
- Shortens filenames to a configurable max length
- Adds numeric prefixes (`001_`, `002_`, ...) for stable, predictable playback order
- Organizes flat file dumps into artist folders (`--album-folders`)
- Safe dry-run mode to preview all changes before applying
- Collision protection — never overwrites existing files
- Works on **Linux** (Fedora, Ubuntu, Debian, Arch, openSUSE) and **macOS**
- Single portable script, no dependencies beyond standard Unix tools

## Demo

```
$ prepare-car-usb --dry-run /run/media/$USER/USB

prepare-car-usb v2.0.0
  Target:     /run/media/user/USB
  Extensions: mp3,wma,flac,m4a,wav,aac,ogg
  Max length: 35
  Mode:       dry run

[1/4] Removing hidden and junk files
    delete /run/media/user/USB/.DS_Store
    delete /run/media/user/USB/Thumbs.db

[2/4] Cleaning and shortening filenames
    Burna Boy – Last Last (Official Audio 2024 Remix).mp3 -> burna_boy_last_last_official_audi.mp3
    01 - Regular Track.flac -> 01_-_regular_track.flac

[3/4] Adding numeric prefixes for stable sort order
    01_-_regular_track.flac -> 001_-_regular_track.flac
    burna_boy_last_last_official_audi.mp3 -> 002_burna_boy_last_last_official_audi.mp3

[4/4] Syncing changes to disk
    Skipped (dry run).

── Summary ─────────────────────────────
  Mode:            dry run (no changes made)
  Junk removed:    2
  Files renamed:   2
  Files prefixed:  2
```

## Installation

```bash
git clone https://github.com/vchebon/car-usb-prep.git
cd car-usb-prep
chmod +x prepare-car-usb.sh
```

To install globally:

```bash
sudo cp prepare-car-usb.sh /usr/local/bin/prepare-car-usb
```

## Usage

```bash
prepare-car-usb [OPTIONS] <directory>
```

Always preview changes first:

```bash
./prepare-car-usb.sh --dry-run /path/to/usb
```

Then apply:

```bash
./prepare-car-usb.sh /path/to/usb
```

## CLI Options

| Option               | Description                                              |
| -------------------- | -------------------------------------------------------- |
| `--dry-run`          | Preview all changes without modifying files              |
| `--max-length <n>`   | Max filename length after cleaning (default: 35)         |
| `--no-prefix`        | Skip numeric prefix step                                 |
| `--album-folders`    | Organize flat files into artist folders                  |
| `--extensions <list>`| Comma-separated audio extensions to process              |
| `--no-color`         | Disable colored output                                   |
| `-v, --verbose`      | Show detailed output                                     |
| `-q, --quiet`        | Suppress non-essential output                            |
| `-h, --help`         | Show help message                                        |
| `--version`          | Show version                                             |

## Examples

```bash
# Basic cleanup
./prepare-car-usb.sh /run/media/$USER/SONYUSB

# Preview only
./prepare-car-usb.sh --dry-run /Volumes/MUSIC

# Longer filenames, no prefixes
./prepare-car-usb.sh --max-length 50 --no-prefix /mnt/usb

# Only process MP3 and FLAC files
./prepare-car-usb.sh --extensions mp3,flac /media/usb

# Organize flat files into artist folders
./prepare-car-usb.sh --album-folders /run/media/$USER/USB
```

## Album Folders Mode

When you have a flat directory of files named like `Artist - Song.mp3`, the `--album-folders` flag organizes them into artist directories:

**Before:**

```
/usb/
  Burna Boy - Last Last.mp3
  Burna Boy - Ye.mp3
  Wizkid - Essence.mp3
  01 - Regular Track.flac
```

**After:**

```
/usb/
  Burna_Boy/
    001_last_last.mp3
    002_ye.mp3
  Wizkid/
    001_essence.mp3
  001_regular_track.flac
```

The tool detects the `Artist - Title` pattern using the ` - ` separator. Files with numeric prefixes (like `01 - Song`) are left in place since those are track numbers, not artist names.

Album folder organization runs before filename cleaning and prefix steps, so all files get the full cleanup pipeline regardless of whether they were moved.

## Pipeline

The tool runs these steps in order:

1. **Remove junk** — delete `.DS_Store`, `Thumbs.db`, `desktop.ini`, and dotfiles
2. **Organize albums** — move files into artist folders (only with `--album-folders`)
3. **Clean filenames** — lowercase, strip special characters, shorten
4. **Add prefixes** — add `001_`, `002_`, ... for stable sort order (skip with `--no-prefix`)
5. **Sync** — flush changes to disk

## Requirements

Only standard Unix utilities (present by default on Linux and macOS):

`bash` (>= 3.2) · `find` · `sed` · `tr` · `cut` · `sort` · `mv` · `sync` · `mkdir`

## Code Quality

Lint with [ShellCheck](https://www.shellcheck.net/):

```bash
shellcheck prepare-car-usb.sh
```

## Contributing

Contributions are welcome. Open an issue or submit a pull request.

## License

MIT License — Copyright (c) 2026 Vincent Chebon
