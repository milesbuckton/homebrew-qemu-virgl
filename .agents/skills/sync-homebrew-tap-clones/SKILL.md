---
name: Sync Homebrew Tap Clones
slug: sync-homebrew-tap-clones
description: >-
  Sync local Homebrew tap clones after a publish rewrites main and moves the
  latest tag. Use when the user asks to reset/pull their tap clones, sync the
  developer and /opt Homebrew tap repos, or refresh local latest tags after a
  release/publish run for milesbuckton/qemu-virgl.
---
# Sync Homebrew Tap Clones

Resets local clones of `milesbuckton/homebrew-qemu-virgl` to `origin/main` and refreshes the local `latest` tag **without modifying remote tags or branches**.

## Clones to Sync

Resolve and deduplicate target paths:
1. **Developer clone**: Current repository (`git rev-parse --show-toplevel`) or default fallback `/Users/milesbuckton/Developer/homebrew-qemu-virgl`.
2. **Homebrew tap clone**: Resolve with `brew --repository milesbuckton/qemu-virgl` (typically `/opt/homebrew/Library/Taps/milesbuckton/homebrew-qemu-virgl`).

If a path does not exist, report it and continue with the remaining clone. If both paths resolve to the same location, process it only once.

## Safety Rules

- **Never delete or push remote tags or branches.** Only local operations are permitted.
- **Dirty workspace gate**: If uncommitted changes exist and the user has not explicitly requested discarding them, halt and report (`git -C "$REPO" status --short`). Discard only if the user explicitly confirmed a clean reset.
- Do not run `git pull`; rewritten upstream history requires fetch and hard reset.

## Execution Steps

For each verified repository path (`REPO`):

1. **Inspect state and branch**:
   ```sh
   git -C "$REPO" branch --show-current
   git -C "$REPO" status -sb
   git -C "$REPO" tag -l latest
   ```
   *Stop here if uncommitted changes exist without user confirmation to discard.*

2. **Ensure main branch**:
   ```sh
   git -C "$REPO" checkout main
   ```

3. **Delete local stale tag**:
   ```sh
   git -C "$REPO" tag -d latest 2>&1 || true
   ```

4. **Fetch remote updates and force-sync main**:
   ```sh
   git -C "$REPO" fetch origin --prune --force --tags
   git -C "$REPO" reset --hard origin/main
   ```

5. **Verify synchronization**:
   ```sh
   git -C "$REPO" tag -l latest
   git -C "$REPO" log -1 --oneline
   git -C "$REPO" status -sb
   ```

## Completion Report

Report back to the user:
- Path of each processed clone.
- Resulting HEAD commit SHA and message.
- Confirmation that `latest` is present locally and no remote references were modified.

## Notes

- **Never use `git pull`**: Rewritten upstream history will fail or produce merge conflicts; always use fetch and hard reset.
- **Stale lock / ref errors**: If `origin/main` cannot update due to a ref lock error, retry with `git -C "$REPO" fetch origin --prune --force --tags` before resetting.
- **Remote safety**: Verify that no remote tags or branches were touched.