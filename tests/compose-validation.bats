#!/usr/bin/env bats
# Compose file validation tests

setup() {
    load helpers/setup
}

# Extract lines belonging to a specific service from a compose file
# Args: $1 = service name, $2 = file path
get_service_block() {
    local svc="$1" file="$2"
    awk -v svc="$svc" '
        $0 ~ "^  "svc":" { found=1; next }
        found && /^  [a-zA-Z#]/ { found=0 }
        found
    ' "$file"
}

@test "all compose files pass docker compose config" {
    # This used to be an UNCONDITIONAL `skip "requires docker compose CLI"`,
    # so the one test that checks whether these files parse at all had never
    # run since it was written. The skip is now conditional and reports the
    # reason, so a missing CLI is visible rather than silently green.
    if ! docker compose version &>/dev/null; then
        skip "docker compose CLI not available"
    fi
    for f in $(get_compose_files); do
        run docker compose -f "$f" --env-file "$TEST_DIR/fixtures/.env.test" config -q
        assert_success
    done
}

# Guards the pinning in docker-compose.arr-stack.yml / .utilities.yml. Those
# `name:` keys are what stop a project/directory rename from silently swapping
# in empty volumes, so an unpinned volume is a data-loss risk, not a style nit.
@test "every named volume is pinned to an explicit physical name" {
    if ! docker compose version &>/dev/null; then
        skip "docker compose CLI not available"
    fi
    for f in $(get_compose_files); do
        local vols nkeys nnames
        vols=$(awk '/^volumes:/{f=1;next} /^[a-zA-Z]/{if(f)exit} f' "$f")
        [[ -z "${vols//[[:space:]]/}" ]] && continue
        nkeys=$(echo "$vols" | grep -cE '^  [a-z0-9-]+:' || true)
        nnames=$(echo "$vols" | grep -cE '^    name: ' || true)
        if [[ "$nkeys" -ne "$nnames" ]]; then
            echo "$(basename "$f"): $nkeys volume(s) declared, only $nnames pinned with an explicit name:"
            false
        fi
    done
}

@test "every service has a restart policy" {
    for f in $(get_compose_files); do
        local fname
        fname=$(basename "$f")
        local services
        services=$(awk '/^services:/{found=1; next} found && /^  [a-z]/{gsub(/:.*/, ""); gsub(/^  /, ""); print} found && /^[a-z]/{found=0}' "$f")
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            local block
            block=$(get_service_block "$svc" "$f")
            if ! echo "$block" | grep -q 'restart:'; then
                fail "Service '$svc' in $fname is missing restart policy"
            fi
        done <<< "$services"
    done
}

@test "every service has logging config" {
    for f in $(get_compose_files); do
        local fname
        fname=$(basename "$f")
        local services
        services=$(awk '/^services:/{found=1; next} found && /^  [a-z]/{gsub(/:.*/, ""); gsub(/^  /, ""); print} found && /^[a-z]/{found=0}' "$f")
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            local block
            block=$(get_service_block "$svc" "$f")
            if ! echo "$block" | grep -q 'logging:'; then
                fail "Service '$svc' in $fname is missing logging config"
            fi
        done <<< "$services"
    done
}

@test "no service uses privileged: true" {
    for f in $(get_compose_files); do
        local fname
        fname=$(basename "$f")
        if grep -qE 'privileged:[[:space:]]*true' "$f" 2>/dev/null; then
            fail "privileged: true found in $fname"
        fi
    done
}

@test "all image tags exist on their registry" {
    # Checks every pinned image:tag exists on its registry via HTTP API
    # No Docker CLI needed — uses curl against registry APIs directly
    if ! command -v curl &>/dev/null; then
        skip "requires curl"
    fi

    local failed=()
    local images
    images=$(get_all_images | sort -u)

    while IFS= read -r image; do
        [[ -z "$image" ]] && continue
        # Skip images with variable substitution
        [[ "$image" == *'${'* ]] && continue

        # Split image:tag
        local repo="${image%:*}"
        local tag="${image##*:}"

        # Route to the correct registry API
        if [[ "$repo" == lscr.io/* ]]; then
            # LinuxServer: query Docker Hub (lscr.io mirrors linuxserver/*)
            local hub_repo="${repo#lscr.io/}"
            local url="https://hub.docker.com/v2/repositories/${hub_repo}/tags/${tag}"
        elif [[ "$repo" == ghcr.io/* ]]; then
            # GitHub Container Registry: use OCI token + manifest check
            local ghcr_repo="${repo#ghcr.io/}"
            local token
            token=$(curl -sf "https://ghcr.io/token?scope=repository:${ghcr_repo}:pull" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$token" ]]; then
                local status
                status=$(curl -o /dev/null -w "%{http_code}" -s \
                    -H "Authorization: Bearer $token" \
                    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
                    "https://ghcr.io/v2/${ghcr_repo}/manifests/${tag}")
                [[ "$status" == "200" ]] && continue
            fi
            failed+=("$image")
            continue
        elif [[ "$repo" == */* ]]; then
            # Docker Hub with org/repo
            local url="https://hub.docker.com/v2/repositories/${repo}/tags/${tag}"
        else
            # Docker Hub official image (library/*)
            local url="https://hub.docker.com/v2/repositories/library/${repo}/tags/${tag}"
        fi

        # Check Docker Hub API
        local http_code
        http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$url")
        if [[ "$http_code" != "200" ]]; then
            failed+=("$image")
        fi
    done <<< "$images"

    if [[ ${#failed[@]} -gt 0 ]]; then
        local msg="Image tags not found on registry:"
        for img in "${failed[@]}"; do
            msg+=$'\n'"  - $img"
        done
        fail "$msg"
    fi
}

@test "all images are pinned (no :latest, no missing tags)" {
    for f in $(get_compose_files); do
        local fname
        fname=$(basename "$f")
        while IFS= read -r line; do
            local image
            image=$(echo "$line" | sed -E 's/^[[:space:]]+image:[[:space:]]*//')
            [[ -z "$image" ]] && continue
            if [[ "$image" == *":latest"* ]]; then
                fail "Image '$image' in $fname uses :latest tag"
            fi
            if [[ "$image" != *":"* ]] && [[ "$image" != *'${'* ]]; then
                fail "Image '$image' in $fname has no version tag"
            fi
        done < <(grep -E '^[[:space:]]+image:[[:space:]]' "$f" 2>/dev/null)
    done
}

# --- architecture: rules the compose files must keep, and can silently lose ---
#
# Adapted from leonardoazeredo/ultimate-arr-stack (tests/compose-validation.bats,
# the "quality plan" branch). Each rule has a negative test that feeds the same
# check a fixture or a mutated copy, because a guard that has never been seen
# to fail is not yet a guard.

@test "every BitTorrent or Usenet client runs inside gluetun's namespace" {
    run python3 "$TEST_DIR/helpers/check-clients-tunnelled.py" "$REPO_ROOT"
    assert_success
    assert_output --partial "all inside gluetun's namespace"
}

@test "the tunnelled-clients check rejects a client with no VPN binding" {
    cp "$TEST_DIR/fixtures/compose-client-outside-vpn.yml" "$BATS_TEST_TMPDIR/docker-compose.fixture.yml"
    run python3 "$TEST_DIR/helpers/check-clients-tunnelled.py" "$BATS_TEST_TMPDIR"
    assert_failure
    assert_output --partial "VIOLATION"
    assert_output --partial "qbittorrent"
}

# Which compose files form one project is not cosmetic: it is why
# `--remove-orphans` on one file deletes the others' containers (CLAUDE.md),
# and why the `arr-stack_` prefix on networks is stable. Written out rather
# than derived, so a rename fails here — that is the point of pinning it.
assert_project_names() {
    local dir="$1" f name base expected
    for f in "$dir"/docker-compose*.yml; do
        base=$(basename "$f")
        name=$(grep -m1 '^name:' "$f" | sed 's/^name:[[:space:]]*//')
        [ -n "$name" ] || { echo "$base does not pin a project name"; return 1; }
        case "$base" in
            docker-compose.arr-stack.yml|docker-compose.traefik.yml|docker-compose.utilities.yml) expected=arr-stack ;;
            docker-compose.cloudflared.yml) expected=cloudflared ;;
            docker-compose.tailscale.yml)   expected=tailscale ;;
            docker-compose.fixture.yml)     expected=arr-stack ;;   # what the negative test mutates
            *) echo "$base is not in the expected-project-name table; add it"; return 1 ;;
        esac
        [ "$name" = "$expected" ] || { echo "$base pins project '$name', expected '$expected'"; return 1; }
    done
    echo "project names pinned as expected"
}

@test "every compose file pins its project name, and the core three share arr-stack" {
    run assert_project_names "$REPO_ROOT"
    assert_success
}

@test "the project-name check fails when a file loses its name line" {
    grep -v '^name:' "$REPO_ROOT/docker-compose.arr-stack.yml" > "$BATS_TEST_TMPDIR/docker-compose.fixture.yml"
    run assert_project_names "$BATS_TEST_TMPDIR"
    assert_failure
    assert_output --partial "does not pin a project name"
}

# Two addresses in this stack are only safe because of these lines: gluetun's
# reserved 172.20.0.3 and every other static IP sit outside the dynamic half,
# and ip_range is what confines Docker's allocator to 172.20.0.128/25 — the
# reason a neighbouring container does not land on gluetun's address after a
# reboot (CLAUDE.md, "Cross-Stack"). Widen the range and the allocator is back
# on top of the pins.
assert_arr_network_pinned() {
    local f="$1" block
    block=$(awk '/^  arr-stack:$/{p=1} p&&/^  [a-z]/&&!/^  arr-stack:$/{p=0} p' "$f")
    [ -n "$block" ] || { echo "no arr-stack network block in $(basename "$f")"; return 1; }
    grep -qE '^[[:space:]]*-[[:space:]]*subnet:[[:space:]]*172\.20\.0\.0/24$' <<<"$block" || { echo "arr-stack subnet must stay 172.20.0.0/24"; return 1; }
    grep -qE '^[[:space:]]+ip_range:[[:space:]]*172\.20\.0\.128/25$' <<<"$block"     || { echo "arr-stack ip_range must stay 172.20.0.128/25 — or Docker's allocator overlaps the pinned static IPs"; return 1; }
    grep -qE '^[[:space:]]+gateway:[[:space:]]*172\.20\.0\.1$' <<<"$block"             || { echo "arr-stack gateway must stay 172.20.0.1"; return 1; }
    echo "arr-stack network pins intact"
}

@test "the arr-stack subnet, dynamic range and gateway stay pinned" {
    run assert_arr_network_pinned "$REPO_ROOT/docker-compose.arr-stack.yml"
    assert_success
}

@test "the network-pin check fails when the dynamic range is widened" {
    sed 's|ip_range: 172.20.0.128/25|ip_range: 172.20.0.0/24|' "$REPO_ROOT/docker-compose.arr-stack.yml" > "$BATS_TEST_TMPDIR/docker-compose.mutated.yml"
    run assert_arr_network_pinned "$BATS_TEST_TMPDIR/docker-compose.mutated.yml"
    assert_failure
    assert_output --partial "ip_range must stay"
}
