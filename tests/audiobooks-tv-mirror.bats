#!/usr/bin/env bats
# Unit tests for scripts/audiobooks-tv-mirror.sh, on a throwaway tree.
#
# The script's whole job is hardlinks in one directory; each test builds the
# source layout it needs under $BATS_TEST_TMPDIR and checks the links by
# inode, not by name — a copy would pass a name check and defeat the point.

setup() {
    load helpers/setup
    SCRIPT="$REPO_ROOT/scripts/audiobooks-tv-mirror.sh"
    ROOT="$BATS_TEST_TMPDIR/data"
    mkdir -p "$ROOT/media/audiobooks/Book A" "$ROOT/usenet/complete/other/Book B" "$ROOT/torrents/other"
    printf 'A' > "$ROOT/media/audiobooks/Book A/Book A.m4b"
    printf 'B' > "$ROOT/usenet/complete/other/Book B/Book B.m4b"
    printf 'C' > "$ROOT/torrents/other/Loose Book.m4b"
    printf 'x' > "$ROOT/torrents/other/not-a-book.iso"
}

@test "links every .m4b from all three sources as .m4a, by inode" {
    run "$SCRIPT" "$ROOT"
    assert_success
    assert_output --partial "3 linked, 0 unchanged, 0 pruned"
    [ "$ROOT/media/audiobooks-tv/Book A/Book A.m4a" -ef "$ROOT/media/audiobooks/Book A/Book A.m4b" ]
    [ "$ROOT/media/audiobooks-tv/Book B/Book B.m4a" -ef "$ROOT/usenet/complete/other/Book B/Book B.m4b" ]
    [ "$ROOT/media/audiobooks-tv/Loose Book/Loose Book.m4a" -ef "$ROOT/torrents/other/Loose Book.m4b" ]
    [ ! -e "$ROOT/media/audiobooks-tv/not-a-book.iso" ]
}

@test "a second run changes nothing" {
    "$SCRIPT" "$ROOT" >/dev/null
    run "$SCRIPT" "$ROOT"
    assert_success
    assert_output --partial "0 linked, 3 unchanged, 0 pruned"
}

@test "prunes a link whose source was deleted, and its empty folder" {
    "$SCRIPT" "$ROOT" >/dev/null
    rm -r "$ROOT/media/audiobooks/Book A"
    run "$SCRIPT" "$ROOT"
    assert_success
    assert_output --partial "0 linked, 2 unchanged, 1 pruned"
    [ ! -e "$ROOT/media/audiobooks-tv/Book A" ]
    [ -e "$ROOT/media/audiobooks-tv/Book B/Book B.m4a" ]
}

@test "replaces a stale link that points at different data" {
    "$SCRIPT" "$ROOT" >/dev/null
    # Simulate the book being re-downloaded: new inode under the same name.
    rm "$ROOT/media/audiobooks/Book A/Book A.m4b"; printf 'A2' > "$ROOT/media/audiobooks/Book A/Book A.m4b"
    run "$SCRIPT" "$ROOT"
    assert_output --partial "1 linked, 2 unchanged, 0 pruned"
    [ "$ROOT/media/audiobooks-tv/Book A/Book A.m4a" -ef "$ROOT/media/audiobooks/Book A/Book A.m4b" ]
}

@test "--dry-run reports and writes nothing" {
    run "$SCRIPT" --dry-run "$ROOT"
    assert_success
    assert_output --partial "3 linked"
    assert_output --partial "dry run"
    [ ! -e "$ROOT/media/audiobooks-tv" ]
}

@test "a missing source directory is skipped, not an error" {
    rm -r "$ROOT/torrents"
    run "$SCRIPT" "$ROOT"
    assert_success
    assert_output --partial "2 linked"
}
