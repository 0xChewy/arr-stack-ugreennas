#!/bin/bash
set -euo pipefail
#
# Mirror every audiobook as a .m4a hardlink, so the Jellyfin TV app can play it.
#
# ⚠️  This script was generated with LLM assistance and human-reviewed.
#     Read and understand it before running. Do not execute scripts you
#     don't understand on your system. It creates and removes hardlinks
#     under ONE directory (audiobooks-tv/) and touches nothing else.
#
# THE PROBLEM IT SOLVES
#
# Jellyfin classifies a .m4b file as an AudioBook item — in any library type,
# Books or Music alike — and the Android TV app cannot browse or play
# AudioBook items. It plays Audio. A .m4b is byte-for-byte a .m4a (the
# extension is only a "remember my position" hint to Apple players), so a
# hardlink under the .m4a name gives a Music-type library a plain audio track
# the TV plays, costs no disk, and leaves the original — and the web's Books
# library with its chapter list — untouched. Hardlinks need one filesystem;
# on this stack /data is one volume, which the TRaSH layout already relies on.
#
# Sources: media/audiobooks, and the two `other` download lanes. Target:
# media/audiobooks-tv/<book folder>/<name>.m4a. A link whose source has been
# deleted (link count 1) is pruned, and its folder removed if empty.
#
# Usage:
#   ./scripts/audiobooks-tv-mirror.sh [--dry-run] [DATA_ROOT]
#   DATA_ROOT defaults to $MEDIA_ROOT, then /volume1/data.
#
# Cron, on the NAS (Jellyfin's real-time monitor picks new links up itself):
#   */15 * * * * /volume1/docker/arr-stack/scripts/audiobooks-tv-mirror.sh >> /volume1/docker/arr-stack/logs/audiobooks-tv-mirror.log 2>&1

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; shift; fi
DATA_ROOT="${1:-${MEDIA_ROOT:-/volume1/data}}"

SOURCES=(media/audiobooks usenet/complete/other torrents/other)
DEST="$DATA_ROOT/media/audiobooks-tv"

linked=0 unchanged=0 pruned=0

link_one() {  # src.m4b
    local src="$1" book dest
    book=$(basename "$(dirname "$src")")
    # A file sitting directly in a source root has no book folder: use its name.
    for s in "${SOURCES[@]}"; do
        [[ "$(dirname "$src")" == "$DATA_ROOT/$s" ]] && book=$(basename "${src%.m4b}")
    done
    dest="$DEST/$book/$(basename "${src%.m4b}").m4a"
    if [[ -e "$dest" && "$dest" -ef "$src" ]]; then
        unchanged=$((unchanged + 1)); return
    fi
    echo "link: $dest"
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$dest")"
        ln -f "$src" "$dest"
    fi
    linked=$((linked + 1))
}

for s in "${SOURCES[@]}"; do
    [[ -d "$DATA_ROOT/$s" ]] || continue
    while IFS= read -r -d '' f; do link_one "$f"; done < <(find "$DATA_ROOT/$s" -type f -name '*.m4b' -print0)
done

# Prune links whose source is gone: a hardlink with a link count of 1 is the
# only remaining name for that data, i.e. the .m4b was deleted.
if [[ -d "$DEST" ]]; then
    while IFS= read -r -d '' f; do
        echo "prune: $f (source deleted)"
        if ! $DRY_RUN; then
            rm -f "$f"
            rmdir "$(dirname "$f")" 2>/dev/null || true
        fi
        pruned=$((pruned + 1))
    done < <(find "$DEST" -type f -name '*.m4a' -links 1 -print0)
fi

echo "audiobooks-tv: ${linked} linked, ${unchanged} unchanged, ${pruned} pruned$($DRY_RUN && echo ' (dry run — nothing written)')"
