---
description: Reset local developer and Homebrew tap clones after a publish rewrites main and moves the latest tag
---

Load and follow the `sync-homebrew-tap-clones` skill at `.agents/skills/sync-homebrew-tap-clones/SKILL.md` exactly as written.

The skill file is the single source of truth for this workflow. In particular, do not improvise anything it pins down:

- Its safety rules — never delete or force-push remote tags/branches; only delete the local `latest` tag; check for uncommitted work before resetting (stop and report unless the user explicitly asked to discard); after a publish rewrite, recover with `git fetch origin --prune --force` + `git reset --hard origin/main`, not `git pull`.
- The clones to sync: the developer clone (`/Users/milesbuckton/Developer/homebrew-qemu-virgl` / repo root) and the Homebrew tap clone (`brew --repository milesbuckton/qemu-virgl`, typically `/opt/homebrew/Library/Taps/milesbuckton/homebrew-qemu-virgl`). If a clone is missing, report it and continue.
- Its verification/reporting: report both repo paths, resulting HEAD SHAs, and whether `latest` is present locally; confirm no remote tags were modified.

If anything in this message conflicts with the skill, the skill wins.
