---
name: sync-homebrew-tap-clones
description: Sync local Homebrew tap clones after a publish rewrites main and moves the latest tag. Use when the user asks to reset/pull their tap clones, sync the developer and /opt Homebrew tap repos, or refresh local latest tags after a release/publish run for milesbuckton/qemu-virgl.
---

# Sync Homebrew Tap Clones

Resets local clones of `milesbuckton/homebrew-qemu-virgl` to `origin/main` and refreshes the local `latest` tag **without touching remote tags**. Use after the `publish.yml` workflow squashes/force-pushes `main` and moves the `latest` tag.

## Clones to sync

1. **Developer clone** (current repo when working here): `/Users/milesbuckton/Developer/homebrew-qemu-virgl` (or `git rev-parse --show-toplevel`).
2. **Homebrew tap clone** (installed tap): resolve with `brew --repository milesbuckton/qemu-virgl` (typically `/opt/homebrew/Library/Taps/milesbuckton/homebrew-qemu-virgl`).

If a clone is missing, report it and continue with the others.

## Safety

- **Never delete or force-push remote tags/branches.** Only local tag deletion (`git tag -d latest`) is allowed.
- Check for uncommitted work before resetting. If dirty and the user hasn't asked to discard it, stop and report (`git -C <repo> status --short`). If the user explicitly asked to reset/sync, discard local changes with `git reset --hard` (and `git clean -fd` only if needed/untracked files block the sync).
- `main` is rewritten by publish runs; `git reset --hard origin/main` is the correct recovery (not `git pull` merge/rebase).

## Steps

For each clone (`REPO` = developer clone, then tap clone):

1. Inspect state:
   ```sh
   git -C "$REPO" status -sb
   git -C "$REPO" tag -l latest
   ```

2. Remove the local `latest` tag only (ignore if absent):
   ```sh
   git -C "$REPO" tag -d latest 2>&1 || true
   ```

3. Fetch and hard-reset `main` to match the rewritten remote (force ref update handles diverged history):
   ```sh
   git -C "$REPO" fetch origin --prune --force
   git -C "$REPO" reset --hard origin/main
   ```

4. Confirm the `latest` tag was fetched locally and repos match remote:
   ```sh
   git -C "$REPO" tag -l latest
   git -C "$REPO" log -1 --oneline
   git -C "$REPO" status -sb
   ```

## Notes

- Do **not** run `git pull` when `main` has diverged due to a publish rewrite; it will fail or create merge conflicts. Use fetch + hard reset.
- If `origin/main` cannot be updated due to a stale lock/ref issue, retry with `git -C "$REPO" fetch origin --prune --force` before resetting.
- Report both repo paths, their resulting HEAD SHAs, and whether `latest` is present locally. Confirm no remote tags were modified.
