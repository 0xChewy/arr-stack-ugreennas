# Quality control map

Which surface checks what. Filled in from what actually runs, not from what
was intended; the point of the table is the cells that say MISSING.

Adapted from the same map in leonardoazeredo/ultimate-arr-stack, which found
gaps there that nothing else had surfaced.

## Legend

- **YES** — runs there and fails the surface when it fails.
- **DIAG** — runs there and reports; never fails the surface.
- **SKIP** — present but skipped on that surface (usually: needs the NAS or a network).
- **N/A** — the surface cannot do this by nature.
- **MISSING** — could run there and does not.

## The surfaces

| surface | when | what it is |
|---|---|---|
| **Hook** | every commit, on the developer's machine | `scripts/pre-commit` — eleven checks, three of which need SSH to the NAS and skip without it |
| **Local** | on demand | `tests/run-tests.sh` (bats) and `npm run test:e2e` (Playwright, needs `.env.e2e` and the NAS) |
| **CI** | every push and PR | `.github/workflows/ci.yml` — bats, lint, supply chain |
| **Nightly** | 04:17 UTC and on demand | the same workflow's image scan |
| **NAS** | before every merge, by hand | branch-first deploy per CLAUDE.md: recreate, verify, `npm run test:e2e` |

## The map

| capability | Hook | Local | CI | Nightly | NAS | where |
|---|---|---|---|---|---|---|
| Compose files parse (`docker compose config`) | YES | YES | YES | N/A | YES | bats `compose-validation` |
| Port and static-IP conflicts across files | YES | YES | YES | N/A | — | hook `check-conflicts`; bats `port-conflicts` |
| Secret patterns in tracked files | YES | YES | YES | N/A | — | hook `check-secrets`; bats `security`, `pre-commit-checks` |
| Every compose variable documented in `.env.example` | YES | YES | YES | N/A | — | hook `check-env-vars`; bats `env-vars` |
| Internal doc links resolve | YES | YES | YES | N/A | — | hook `check-doc-links` |
| Image tags pinned (no `latest`) | YES | YES | YES | N/A | — | bats `compose-validation` |
| Image tags exist on their registry | SKIP* | SKIP* | YES | N/A | — | bats `compose-validation` — *needs a network; the hook reports newer tags instead |
| Volumes pinned to physical names | — | YES | YES | N/A | — | bats `compose-validation` |
| Every download client inside gluetun's namespace | — | YES | YES | N/A | — | bats `compose-validation` + `helpers/check-clients-tunnelled.py` |
| Project names pinned; core three share `arr-stack` | — | YES | YES | N/A | — | bats `compose-validation` |
| `arr-stack` subnet, `ip_range` and gateway pinned | — | YES | YES | N/A | — | bats `compose-validation` |
| Services declaring a VPN binding are inside gluetun's *current* namespace | — | — | — | N/A | YES | e2e `resilience`; script `detect-vpn-zombies.sh` (unit-tested in bats `vpn-zombies`) |
| Gluetun's capability set (OpenVPN path) | — | YES | YES | N/A | — | bats `openvpn-caps` |
| shellcheck, `error` severity | — | YES | YES | N/A | — | bats `shellcheck` |
| shellcheck, `warning` severity | — | — | DIAG | N/A | — | CI `lint` |
| actionlint over the workflow | — | — | YES | N/A | — | CI `lint` |
| hadolint over the devcontainer Dockerfile | — | — | YES | N/A | — | CI `lint`, policy in `.hadolint.yaml` |
| `configure-apps.sh` HTTP layer (curl stubbed) | — | YES | YES | N/A | — | bats `configure-helpers` |
| Bazarr language plan across profile states | — | YES | YES | N/A | — | bats `bazarr-language-plan` |
| `configure-apps.sh` structure (step order, no unbounded curl, CLI) | — | YES | YES | N/A | — | bats `configure-apps` |
| `configure-apps.sh` against real services | — | — | — | N/A | YES | by hand, `--dry-run` then run; throwaway containers for Bazarr |
| Python in `scripts/lib/` — lint | — | MISSING | MISSING | N/A | — | nothing runs pyflakes/ruff |
| YAML lint beyond `compose config` | — | MISSING | MISSING | N/A | — | no yamllint |
| Vulnerabilities, misconfiguration, secrets over the tree (trivy) | — | MISSING | YES | N/A | — | CI `supply chain`, HIGH/CRITICAL block |
| SBOM | — | MISSING | YES | N/A | — | CI `supply chain`, artifact |
| Container image CVEs | — | MISSING | — | DIAG | — | CI `nightly`, artifact + summary table |
| Uptime Kuma monitors match the services | YES (SSH) | — | SKIP | N/A | — | hook `check-uptime-monitors` |
| `.lan` DNS duplicates; `.env` backup in sync | YES (SSH) | — | SKIP | N/A | — | hook `check-dns-duplicates`, `check-env-backup` |
| Every service UI answers; API state (root folders, clients, profiles) | — | — | — | N/A | YES | e2e `ui-screenshots`, `api-assertions` |
| VPN egress per service; killswitch | — | — | — | N/A | YES | e2e `vpn-security` (killswitch needs `ALLOW_DISRUPTIVE_TESTS=1`) |
| No executables under `/data` | — | — | — | N/A | YES | e2e `media-hygiene`; `scan-executables.sh` |
| Mutation testing of the guards | — | MISSING | MISSING | MISSING | — | the fork has a corpus; not adopted |

## Gaps this map makes visible

1. **The Python plan has no linter.** `scripts/lib/bazarr-language-plan.py` is unit-tested but nothing runs pyflakes or ruff over it. Cheap to add to `lint`.
2. **Nothing lints YAML** beyond `docker compose config`, which accepts a lot.
3. **Three hook checks exist only on a machine that can SSH to the NAS** — monitors, DNS duplicates, `.env` backup sync. A contributor's push is never checked for them, and CI cannot be.
4. **The e2e suite runs only from a machine with `.env.e2e`.** By design — it needs the stack — but it means the NAS step is the only place UI and egress are ever exercised.
5. **The guards are never mutation-tested.** Each new architecture test carries its own negative case instead, which proves the check can fail once, not that it stays sharp.

## Maintaining this file

When a job, test file or hook check is added or removed, change the row here in the same commit. A row that says YES for a check that no longer runs is worse than no map.
