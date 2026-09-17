#!/usr/bin/env bats
# Regression guard: the pre-commit hook must actually be INSTALLED.
#
# Every blocking check in this repo — secrets, undocumented env vars, port and
# static-IP collisions, YAML syntax — runs from scripts/pre-commit. None of it
# runs if the hook isn't wired into .git/hooks, and nothing else notices.
# The checks can be perfect and still never execute.
#
# This is not hypothetical. setup-hooks.sh tested `[[ -d "$SCRIPT_DIR/.git" ]]`
# to decide whether it was in a git repo. In a worktree, `.git` is a FILE
# holding a gitdir pointer, not a directory — so the script exited with
# "Not a git repository", installed nothing, and said so in a way that looked
# like a sensible refusal rather than a bug. Fixed 2026-08-15; this test is
# what stops it regressing.
#
# If this fails: run ./setup-hooks.sh

setup() {
    load helpers/setup
}

@test "pre-commit hook is installed" {
    local git_common_dir
    # --git-common-dir, not --git-dir: hooks live in the dir shared by every
    # worktree, which is exactly what the original bug got wrong.
    git_common_dir=$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [[ -n "$git_common_dir" ]] || fail "Could not resolve the git common dir — is this a git repo?"

    local hook_path="$git_common_dir/hooks/pre-commit"
    [[ -e "$hook_path" ]] || fail "Pre-commit hook not installed at $hook_path — run ./setup-hooks.sh"
}

@test "pre-commit hook points at scripts/pre-commit" {
    local git_common_dir hook_path
    git_common_dir=$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    hook_path="$git_common_dir/hooks/pre-commit"

    [[ -e "$hook_path" ]] || skip "hook not installed (covered by the previous test)"

    # A hook that exists but points somewhere else is worse than none — it
    # looks installed while running something other than this repo's checks.
    if [[ -L "$hook_path" ]]; then
        local target
        target=$(readlink "$hook_path")
        [[ "$target" == *"scripts/pre-commit" ]] \
            || fail "Pre-commit hook symlink points at an unexpected target: $target"
    else
        grep -q "ultimate-arr-stack\|check_secrets\|check_env_vars" "$hook_path" \
            || fail "Pre-commit hook at $hook_path doesn't look like this repo's hook"
    fi
}

@test "pre-commit hook is executable" {
    local git_common_dir hook_path
    git_common_dir=$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    hook_path="$git_common_dir/hooks/pre-commit"

    [[ -e "$hook_path" ]] || skip "hook not installed (covered by the first test)"

    # git silently ignores a non-executable hook. Same failure shape as the
    # worktree bug: present, apparently fine, never runs.
    [[ -x "$hook_path" ]] || fail "Pre-commit hook at $hook_path is not executable — git will skip it silently"
}
