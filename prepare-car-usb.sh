#!/usr/bin/env bash
# prepare-car-usb — Prepare a USB music library for car stereos
# https://github.com/vchebon/car-usb-prep
#
# Compatible with Bash >= 3.2 (macOS), GNU/Linux, and BSD utilities.

set -euo pipefail

VERSION="2.0.0"
PROG="$(basename "$0")"

# ── Defaults ──────────────────────────────────────────────────────────

DEFAULT_MAXLEN=35
DEFAULT_EXTENSIONS="mp3,wma,flac,m4a,wav,aac,ogg"

# ── Global state ──────────────────────────────────────────────────────

DRY_RUN=0
ADD_PREFIX=1
ALBUM_FOLDERS=0
VERBOSE=0
QUIET=0
USE_COLOR=1
MAXLEN="$DEFAULT_MAXLEN"
EXTENSIONS="$DEFAULT_EXTENSIONS"
TARGET_DIR=""

# ── Counters ──────────────────────────────────────────────────────────

COUNT_JUNK=0
COUNT_RENAMED=0
COUNT_PREFIXED=0
COUNT_GROUPED=0
COUNT_SKIPPED=0

# ── Step tracking ────────────────────────────────────────────────────

CURRENT_STEP=0
TOTAL_STEPS=0

# ── Colors ────────────────────────────────────────────────────────────

C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""

init_colors() {
    if [[ "$USE_COLOR" -eq 1 ]] && [[ -t 1 ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_CYAN=$'\033[36m'
    fi
}

# ── Logging ───────────────────────────────────────────────────────────

log()    { printf '%s\n' "$*"; }
detail() { [[ "$VERBOSE" -eq 0 ]] || printf '    %s\n' "$*"; }
warn()   { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()    { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf '\n%s[%d/%d]%s %s\n' \
        "$C_BOLD" "$CURRENT_STEP" "$TOTAL_STEPS" "$C_RESET" "$1"
}

# ── String utilities ─────────────────────────────────────────────────

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_extensions() {
    local raw="$1"
    printf '%s' "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | sed '/^$/d' \
        | sed 's/^\.//' \
        | sort -u \
        | tr '\n' ',' \
        | sed 's/,$//'
}

clean_name() {
    local input="$1"
    local output

    output="$(printf '%s' "$input" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/&/ and /g' \
        | sed "s/'//g" \
        | sed -E 's/[^[:alnum:][:space:]_-]/ /g' \
        | sed -E 's/[[:space:]]+/_/g' \
        | sed -E 's/_+/_/g' \
        | sed 's/^_//; s/_$//')"

    [[ -n "$output" ]] || output="track"

    output="$(printf '%s' "$output" | cut -c1-"$MAXLEN")"
    output="$(printf '%s' "$output" | sed 's/_$//')"

    [[ -n "$output" ]] || output="track"
    printf '%s' "$output"
}

clean_folder_name() {
    local input="$1"
    local output

    output="$(printf '%s' "$input" \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
        | sed -E 's/[^[:alnum:][:space:]_-]/ /g' \
        | sed -E 's/[[:space:]]+/_/g' \
        | sed -E 's/_+/_/g' \
        | sed 's/^_//; s/_$//')"

    [[ -n "$output" ]] || output="unknown"
    printf '%s' "$output"
}

# ── File utilities ────────────────────────────────────────────────────

is_audio_file() {
    local ext
    ext="$(to_lower "$1")"
    local allowed
    IFS=',' read -r -a ext_array <<< "$EXTENSIONS"
    for allowed in "${ext_array[@]}"; do
        [[ "$ext" = "$allowed" ]] && return 0
    done
    return 1
}

find_unique_path() {
    local dir="$1" base="$2" ext="$3"
    local candidate="${dir}/${base}.${ext}"

    if [[ ! -e "$candidate" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    local n=1
    while [[ -e "${dir}/${base}_${n}.${ext}" ]]; do
        n=$((n + 1))
    done
    printf '%s' "${dir}/${base}_${n}.${ext}"
}

safe_move() {
    local src="$1" dest="$2"

    [[ "$src" != "$dest" ]] || return 0

    if [[ -e "$dest" ]]; then
        warn "target exists, skipped: $(basename "$dest")"
        COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '    %s%s%s -> %s%s%s\n' \
            "$C_DIM" "$(basename "$src")" "$C_RESET" \
            "$C_GREEN" "$(basename "$dest")" "$C_RESET"
    else
        mv -- "$src" "$dest"
        detail "$(basename "$src") -> $(basename "$dest")"
    fi
    return 0
}

safe_mkdir() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '    %smkdir%s %s/\n' "$C_GREEN" "$C_RESET" "$(basename "$dir")"
    else
        mkdir -p -- "$dir"
        detail "created: $(basename "$dir")/"
    fi
}

# ── Pipeline steps ────────────────────────────────────────────────────

remove_junk_files() {
    step "Removing hidden and junk files"

    local found=0
    while IFS= read -r -d '' junk; do
        found=1
        COUNT_JUNK=$((COUNT_JUNK + 1))
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf '    %sdelete%s %s\n' "$C_RED" "$C_RESET" "$junk"
        else
            rm -f -- "$junk"
            detail "deleted: $junk"
        fi
    done < <(
        find "$TARGET_DIR" -type f \( \
            -name '.*' -o \
            -name 'Thumbs.db' -o \
            -name 'desktop.ini' \
        \) -print0
    )

    [[ "$found" -eq 1 ]] || log "    No junk files found."
}

organize_album_folders() {
    step "Organizing files into artist folders"

    local file filename base ext ext_lc artist track artist_dir dest

    for file in "$TARGET_DIR"/*; do
        [[ -f "$file" ]] || continue

        filename="$(basename "$file")"
        ext="${filename##*.}"
        base="${filename%.*}"
        ext_lc="$(to_lower "$ext")"

        is_audio_file "$ext_lc" || continue

        # Detect "Artist - Title" pattern (common in music filenames)
        # Skip if prefix before " - " is purely numeric (e.g., "01 - Song")
        case "$base" in
            *" - "*)
                artist="$(printf '%s' "$base" | sed 's/ - .*//')"
                # Skip track-number prefixes like "01 - Song.mp3"
                case "$artist" in
                    *[!0-9]*) ;;  # Contains non-digits — valid artist name
                    *) detail "numeric prefix, skipped: $filename"; continue ;;
                esac
                track="${base#* - }"
                artist_dir="$(clean_folder_name "$artist")"
                ;;
            *)
                detail "no pattern detected, skipped: $filename"
                continue
                ;;
        esac

        [[ -n "$artist_dir" ]] || continue

        safe_mkdir "${TARGET_DIR}/${artist_dir}"
        dest="$(find_unique_path "${TARGET_DIR}/${artist_dir}" "$track" "$ext")"
        if safe_move "$file" "$dest"; then
            COUNT_GROUPED=$((COUNT_GROUPED + 1))
        fi
    done

    [[ "$COUNT_GROUPED" -gt 0 ]] || log "    No files matched the 'Artist - Title' pattern."
}

clean_and_shorten_filenames() {
    step "Cleaning and shortening filenames"

    local found=0
    local file dir filename ext base ext_lc clean newpath

    while IFS= read -r -d '' file; do
        filename="$(basename "$file")"
        dir="$(dirname "$file")"
        ext="${filename##*.}"
        base="${filename%.*}"
        ext_lc="$(to_lower "$ext")"

        is_audio_file "$ext_lc" || continue

        found=1
        clean="$(clean_name "$base")"
        newpath="$(find_unique_path "$dir" "$clean" "$ext_lc")"

        if [[ "$file" != "$newpath" ]]; then
            if safe_move "$file" "$newpath"; then
                COUNT_RENAMED=$((COUNT_RENAMED + 1))
            fi
        fi
    done < <(find "$TARGET_DIR" -type f -print0)

    [[ "$found" -eq 1 ]] || warn "No supported audio files found."
}

add_numeric_prefixes() {
    step "Adding numeric prefixes for stable sort order"

    local found=0

    while IFS= read -r -d '' folder; do
        local i=1
        # Use glob for portable sorted listing (avoids BSD sort -z issue)
        for song in "$folder"/*; do
            [[ -f "$song" ]] || continue

            local filename ext base ext_lc stripped prefix newbase newpath
            filename="$(basename "$song")"
            ext="${filename##*.}"
            base="${filename%.*}"
            ext_lc="$(to_lower "$ext")"

            is_audio_file "$ext_lc" || continue

            found=1

            # Strip existing 2-4 digit numeric prefix
            stripped="$(printf '%s' "$base" | sed -E 's/^[0-9]{2,4}_//')"
            prefix="$(printf '%03d' "$i")"
            newbase="${prefix}_${stripped}"
            newpath="$(find_unique_path "$folder" "$newbase" "$ext_lc")"

            if [[ "$song" != "$newpath" ]]; then
                if safe_move "$song" "$newpath"; then
                    COUNT_PREFIXED=$((COUNT_PREFIXED + 1))
                fi
            fi

            i=$((i + 1))
        done
    done < <(find "$TARGET_DIR" -type d -print0)

    [[ "$found" -eq 1 ]] || warn "No supported audio files found for prefixing."
}

sync_changes() {
    step "Syncing changes to disk"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "    Skipped (dry run)."
    else
        sync
        log "    Done."
    fi
}

# ── Summary ───────────────────────────────────────────────────────────

print_summary() {
    printf '\n%s── Summary ─────────────────────────────%s\n' "$C_BOLD" "$C_RESET"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  Mode:            %sdry run (no changes made)%s\n' "$C_YELLOW" "$C_RESET"
    fi

    local total=0

    if [[ "$COUNT_JUNK" -gt 0 ]]; then
        printf '  Junk removed:    %s\n' "$COUNT_JUNK"
        total=$((total + COUNT_JUNK))
    fi
    if [[ "$COUNT_GROUPED" -gt 0 ]]; then
        printf '  Files organized: %s\n' "$COUNT_GROUPED"
        total=$((total + COUNT_GROUPED))
    fi
    if [[ "$COUNT_RENAMED" -gt 0 ]]; then
        printf '  Files renamed:   %s\n' "$COUNT_RENAMED"
        total=$((total + COUNT_RENAMED))
    fi
    if [[ "$COUNT_PREFIXED" -gt 0 ]]; then
        printf '  Files prefixed:  %s\n' "$COUNT_PREFIXED"
        total=$((total + COUNT_PREFIXED))
    fi
    if [[ "$COUNT_SKIPPED" -gt 0 ]]; then
        printf '  Files skipped:   %s%s%s\n' "$C_YELLOW" "$COUNT_SKIPPED" "$C_RESET"
    fi

    if [[ "$total" -eq 0 ]]; then
        printf '  No changes needed.\n'
    fi

    printf '\n'
}

# ── CLI ───────────────────────────────────────────────────────────────

print_help() {
    cat <<EOF
${C_BOLD}prepare-car-usb${C_RESET} v${VERSION}

Prepare a USB music library for car stereos.

${C_BOLD}USAGE${C_RESET}
    $PROG [OPTIONS] <directory>

${C_BOLD}OPTIONS${C_RESET}
    --dry-run              Preview all changes without modifying files
    --max-length <n>       Max filename length after cleaning (default: $DEFAULT_MAXLEN)
    --no-prefix            Skip numeric prefix step
    --album-folders        Organize flat files into artist folders
    --extensions <list>    Comma-separated audio extensions
                           (default: $DEFAULT_EXTENSIONS)
    --no-color             Disable colored output
    -v, --verbose          Show detailed output
    -q, --quiet            Suppress non-essential output
    -h, --help             Show this help message
    --version              Show version

${C_BOLD}EXAMPLES${C_RESET}
    $PROG /run/media/\$USER/USB
    $PROG --dry-run /Volumes/MUSIC
    $PROG --album-folders --max-length 40 /mnt/usb
    $PROG --no-prefix --extensions mp3,flac /media/usb

${C_BOLD}PIPELINE${C_RESET}
    1. Remove junk files (.DS_Store, Thumbs.db, desktop.ini, dotfiles)
    2. Organize into artist folders (--album-folders)
    3. Clean and shorten filenames
    4. Add numeric prefixes (001_, 002_, ...) for stable playback
    5. Sync changes to disk
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1; shift ;;
            --max-length)
                [[ $# -ge 2 ]] || die "--max-length requires a value"
                [[ "$2" =~ ^[0-9]+$ ]] || die "--max-length must be a positive integer"
                [[ "$2" -gt 0 ]] || die "--max-length must be greater than 0"
                MAXLEN="$2"; shift 2 ;;
            --no-prefix)
                ADD_PREFIX=0; shift ;;
            --album-folders)
                ALBUM_FOLDERS=1; shift ;;
            --extensions)
                [[ $# -ge 2 ]] || die "--extensions requires a value"
                local trimmed
                trimmed="$(printf '%s' "$2" | sed 's/^[[:space:],]*//; s/[[:space:],]*$//')"
                EXTENSIONS="$(normalize_extensions "$trimmed")"
                [[ -n "$EXTENSIONS" ]] || die "--extensions: empty extension list"
                shift 2 ;;
            --no-color)
                USE_COLOR=0; shift ;;
            -v|--verbose)
                VERBOSE=1; shift ;;
            -q|--quiet)
                QUIET=1; shift ;;
            -h|--help)
                init_colors; print_help; exit 0 ;;
            --version)
                printf '%s\n' "$VERSION"; exit 0 ;;
            --)
                shift; break ;;
            -*)
                die "unknown option: $1 (see --help)" ;;
            *)
                [[ -z "$TARGET_DIR" ]] || die "only one target directory allowed"
                TARGET_DIR="$1"; shift ;;
        esac
    done

    # Positional arg after --
    if [[ -z "$TARGET_DIR" && $# -gt 0 ]]; then
        TARGET_DIR="$1"
    fi

    [[ -n "$TARGET_DIR" ]]                       || die "missing target directory (see --help)"
    [[ -d "$TARGET_DIR" ]]                       || die "not a directory: '$TARGET_DIR'"
    [[ -r "$TARGET_DIR" ]]                       || die "not readable: '$TARGET_DIR'"
    [[ -w "$TARGET_DIR" || "$DRY_RUN" -eq 1 ]]  || die "not writable: '$TARGET_DIR'"

    # Normalize: strip trailing slash
    TARGET_DIR="${TARGET_DIR%/}"
}

# ── Main ──────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    init_colors

    # Quiet wins over verbose
    [[ "$QUIET" -eq 0 ]] || VERBOSE=0

    # Compute total steps: junk + clean + sync = 3 (always)
    TOTAL_STEPS=3
    [[ "$ALBUM_FOLDERS" -eq 0 ]] || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$ADD_PREFIX" -eq 0 ]]    || TOTAL_STEPS=$((TOTAL_STEPS + 1))

    # Header
    if [[ "$QUIET" -eq 0 ]]; then
        printf '\n%s%sprepare-car-usb%s v%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$VERSION"
        printf '  Target:     %s\n' "$TARGET_DIR"
        printf '  Extensions: %s\n' "$EXTENSIONS"
        printf '  Max length: %s\n' "$MAXLEN"
        [[ "$DRY_RUN"       -eq 0 ]] || printf '  Mode:       %sdry run%s\n' "$C_YELLOW" "$C_RESET"
        [[ "$ADD_PREFIX"    -eq 1 ]] || printf '  Prefixes:   disabled\n'
        [[ "$ALBUM_FOLDERS" -eq 0 ]] || printf '  Albums:     enabled\n'
    fi

    # ── Pipeline ──

    remove_junk_files

    if [[ "$ALBUM_FOLDERS" -eq 1 ]]; then
        organize_album_folders
    fi

    clean_and_shorten_filenames

    if [[ "$ADD_PREFIX" -eq 1 ]]; then
        add_numeric_prefixes
    fi

    sync_changes
    print_summary
}

main "$@"
