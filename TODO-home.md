# TODO: When Home

## 1. Convert four files to PolyForm — WAITING ON ONE REPLY

**The relicence is DONE except for these**, implemented 2026-08-16:

- `LICENSE-code` — PolyForm Noncommercial 1.0.0, covering code
- `LICENSE-docs` — CC BY-NC 4.0, covering prose
- `LICENSE` — the index explaining which applies where

**Still on CC BY-NC 4.0, pending permission:**

- `tests/e2e/networking.spec.ts`
- `tests/e2e/vpn-security.spec.ts`
- `tests/e2e/helpers.ts`
- `scripts/detect-vpn-zombies.sh`

They're adapted from [@leonardoazeredo](https://github.com/leonardoazeredo)'s
fork and were contributed under CC BY-NC 4.0. Relicensing another author's
copyright without asking isn't ours to do. Asked in
[#20](https://github.com/Pharkie/ultimate-arr-stack/issues/20);
[@gncnpk](https://github.com/gncnpk) agreed on 2026-08-15,
[@eren-kemer](https://github.com/eren-kemer) needed no agreement (zero
surviving lines by `git blame`).

**When they agree:** delete the `LICENCE:` header block from each of the four
files, drop the "Four files" section from `LICENSE`, and drop the corresponding
paragraph from the README. Nothing else changes.

**If they never reply:** leave it exactly as it is. Per-file dual licensing is
legitimate and these four are self-contained test and script files, not
anything woven into the core compose. Nothing is blocked by this.

**If they decline:** same as never replying. No action.

> Nudge worth sending if there's no reply by roughly mid-September 2026 — an
> unsolicited GitHub ask is easy to miss, and silence is not refusal.
