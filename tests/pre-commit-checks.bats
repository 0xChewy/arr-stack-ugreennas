#!/usr/bin/env bats
# Tests for the pre-commit check scripts themselves

setup() {
    load helpers/setup
    # Source the check scripts
    source "$REPO_ROOT/scripts/lib/common.sh"
}

# Run check_secrets against a throwaway git repo containing $2 as $1.
#
# This deliberately does NOT stub get_files_to_scan/read_file_content. The
# previous version of these tests did, and the stubs did not survive into
# bats' `run` subshell — so check_secrets fell back to the real git-backed
# file list, found nothing, and returned 0. bats reported that as a plain
# failure with empty output for months. Driving the real code path in a real
# (tiny) git repo is both more honest and immune to that whole class of
# harness bug: if it passes, the production path genuinely works.
scan_in_temp_repo() {
    local filename="$1" content="$2" t
    t=$(mktemp -d)
    printf '%s\n' "$content" > "$t/$filename"
    git -C "$t" init -q
    git -C "$t" add -A
    run bash -c "cd '$t' && source '$REPO_ROOT/scripts/lib/common.sh' \
        && source '$REPO_ROOT/scripts/lib/check-secrets.sh' && check_secrets"
    rm -rf "$t"
}

# The fake key itself stays in tests/fixtures/, which check_secrets skips by
# design. Inlining it here instead is not an option: this file is not exempt,
# so the hook flags its own test suite and blocks the commit (it did).
@test "check_secrets catches a known WireGuard key pattern" {
    scan_in_temp_repo docker-compose.secrets.yml \
        "$(cat "$REPO_ROOT/tests/fixtures/compose-with-secrets.yml")"
    assert_failure
    assert_output --partial "WireGuard private key"
}

# Regression guard for the BSD-grep "empty (sub)expression" bug: the old
# pattern's trailing empty alternative made grep error out, so every one of
# these slipped through the hook on macOS.
@test "check_secrets catches PEM private key blocks of every flavour" {
    local header
    for header in "-----BEGIN PRIVATE KEY-----" \
                  "-----BEGIN RSA PRIVATE KEY-----" \
                  "-----BEGIN EC PRIVATE KEY-----" \
                  "-----BEGIN OPENSSH PRIVATE KEY-----" \
                  "-----BEGIN ENCRYPTED PRIVATE KEY-----"; do
        scan_in_temp_repo id_leaked.pem "$header"
        assert_failure
        assert_output --partial "Private key block detected"
    done
}

@test "check_secrets does not flag a public key" {
    scan_in_temp_repo id_public.pem "-----BEGIN PUBLIC KEY-----"
    assert_success
}

@test "check_secrets passes a repo with no secrets" {
    scan_in_temp_repo docker-compose.clean.yml "services: {}"
    assert_success
}

@test "check_env_vars catches an undocumented variable" {
    source "$REPO_ROOT/scripts/lib/check-env-vars.sh"

    # Create a temp compose file with an undocumented var
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/docker-compose.test.yml" <<'EOF'
services:
  test:
    image: alpine:3.20
    environment:
      - UNDOCUMENTED_VAR_XYZZY=${UNDOCUMENTED_VAR_XYZZY}
EOF

    # Run check_env_vars in a subshell with overridden repo root
    run bash -c "
        source '$REPO_ROOT/scripts/lib/common.sh'
        source '$REPO_ROOT/scripts/lib/check-env-vars.sh'
        # Override git rev-parse to use tmpdir
        git() { echo '$tmpdir'; }
        export -f git
        # Copy .env.example to tmpdir
        cp '$REPO_ROOT/.env.example' '$tmpdir/'
        check_env_vars
    "
    assert_failure
    assert_output --partial "UNDOCUMENTED_VAR_XYZZY"

    rm -rf "$tmpdir"
}

@test "check_conflicts catches duplicate ports within a file" {
    source "$REPO_ROOT/scripts/lib/check-conflicts.sh"

    # Create a temp dir with a conflicting compose file
    local tmpdir
    tmpdir=$(mktemp -d)
    cp "$REPO_ROOT/tests/fixtures/compose-port-conflict.yml" "$tmpdir/docker-compose.conflict.yml"

    run bash -c "
        source '$REPO_ROOT/scripts/lib/check-conflicts.sh'
        # Override git rev-parse to use tmpdir
        git() { echo '$tmpdir'; }
        export -f git
        check_conflicts
    "
    assert_failure
    assert_output --partial "Duplicate ports"

    rm -rf "$tmpdir"
}

@test "check_conflicts catches cross-file port duplicates" {
    source "$REPO_ROOT/scripts/lib/check-conflicts.sh"

    # Create two compose files with same port in different files
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/docker-compose.a.yml" <<'EOF'
services:
  svc-a:
    image: alpine:3.20
    ports:
      - "9999:80"
EOF
    cat > "$tmpdir/docker-compose.b.yml" <<'EOF'
services:
  svc-b:
    image: alpine:3.20
    ports:
      - "9999:8080"
EOF

    run bash -c "
        source '$REPO_ROOT/scripts/lib/check-conflicts.sh'
        git() { echo '$tmpdir'; }
        export -f git
        check_conflicts
    "
    assert_failure
    assert_output --partial "Port 9999 used across multiple files"

    rm -rf "$tmpdir"
}

# --- doc links -------------------------------------------------------------
#
# check_doc_links was hook-only: nothing in the suite ran it, so a contributor
# without the hooks could merge a broken link and CI would never know. It
# resolves the repo from the working directory, so the negative drives it in a
# throwaway git repo with one broken link.

@test "check_doc_links: every internal link in the repo's markdown resolves" {
    run bash -c "cd '$REPO_ROOT' && source scripts/lib/common.sh && source scripts/lib/check-doc-links.sh && check_doc_links"
    assert_success
    assert_output --partial "OK: All internal doc links valid"
}

@test "check_doc_links: reports a link to a file that does not exist" {
    local t; t=$(mktemp -d)
    printf '# Doc\n\nSee [the guide](docs/MISSING.md).\n' > "$t/README.md"
    git -C "$t" init -q && git -C "$t" add -A
    run bash -c "cd '$t' && source '$REPO_ROOT/scripts/lib/common.sh' && source '$REPO_ROOT/scripts/lib/check-doc-links.sh' && check_doc_links"
    rm -rf "$t"
    assert_failure
    assert_output --partial "broken link to 'docs/MISSING.md'"
}
