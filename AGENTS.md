# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Rebuild number convention

Each formula's `bottle do ... rebuild N ... end` block uses N as a
**macOS-generation marker**, not a republish counter:

- `rebuild 1` = bottles built for macOS 26 (Tahoe)
- `rebuild 2` = macOS 27, and so on

### The rule

Whenever you cut a new release — i.e. whenever the QEMU major version is
bumped (e.g. 11.0.3 → 12) **or** support for a new macOS generation is added —
increment `rebuild N` to `N + 1` in **all four** formulae, in the same commit:

- `Formula/qemu-virgl.rb`
- `Formula/virglrenderer.rb`
- `Formula/libangle.rb`
- `Formula/libepoxy-angle.rb`

Do not change `rebuild` at any other time.

### Why it must be hand-edited

`.github/workflows/publish.yml` invokes `brew bottle --keep-old`, which reuses
each formula's declared rebuild verbatim instead of computing prev+1 from git
history. Reruns therefore never inflate the number; it only moves when the
formulae are edited deliberately here.

### The release tag is fixed

Releases are always published under the tag `latest`, giving every formula a
permanent `root_url` (`.../releases/download/latest`). `brew bottle --keep-old`
aborts if `root_url` or `rebuild` change between builds, so never reintroduce
per-run timestamped tags. Only checksums are expected to differ between builds.

## Release flow

History carries **one commit per release**: each QEMU-major or macOS-generation
bump adds exactly one commit, and CI's temporary bottle-block commit is folded
back into it after publishing. Routine republishes add no permanent commits.

1. Commit changes (including any `rebuild` bump).
2. Push to `main`.
3. Trigger the build: `gh workflow run publish.yml` (workflow_dispatch only).
4. CI (~30 min) prunes the previous release/tag, publishes fresh bottles named
   `<formula>-<version>.<tag>.bottle.<N>.tar.gz`, and commits the updated
   bottle blocks back to `main`.
5. Verify: `gh release view latest --json assets` shows `.bottle.<N>.tar.gz`
   for all four formulae across both `arm64_tahoe` and `tahoe`.

### Post-release housekeeping

CI's bottle-block commit leaves `main` one commit ahead, with the `latest` tag
still on the pre-squash head. Once the release verifies, fold CI's commit into
the release commit that precedes it (safe here because this tap has a single
committer and no forks pinning SHAs):

1. Squash CI's commit into the preceding release commit, keeping that
   commit's message and trailers:
   ```sh
   git reset --soft HEAD~1
   git commit --amend --no-edit
   ```
   Confirm `git diff origin/main HEAD` is empty (tree unchanged), then
   `git push --force-with-lease origin main`.
2. Move the tag to the new head as a single atomic ref update — never
   delete-then-recreate, which can transiently detach the release:
   ```sh
   git tag -f latest <new-sha>
   git push --force origin refs/tags/latest
   ```
3. Sanity-check that a bottle URL still returns HTTP 200, e.g.
   `curl -sIL -o /dev/null -w "%{http_code}\n"
   https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest/qemu-virgl-<version>.arm64_tahoe.bottle.<N>.tar.gz`

`brew install` resolves bottles via the release's tag name plus checksums, so
rewriting history and moving the tag never affects installed users.

## Local install

```sh
brew install milesbuckton/qemu-virgl/qemu-virgl
```

The formulae intentionally shadow the standard `qemu`/`libepoxy` kegs and are
not linked; invoke binaries via their Cellar path or follow the caveats printed
after install.
