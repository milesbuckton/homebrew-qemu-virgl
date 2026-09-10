# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Rebuild number convention

Each formula's `bottle do ... rebuild N ... end` block uses N as a
**macOS-generation marker**, not a republish counter:

- `rebuild 1` = bottles built for macOS 26 (Tahoe)
- `rebuild 2` = macOS 27, and so on

### The rule

Whenever you cut a new release — i.e. whenever support for a new macOS
generation is added — increment `rebuild N` to `N + 1` in **all four**
bottle-bearing formulae, in the same commit:

- `Formula/qemu-virgl.rb`
- `Formula/virglrenderer.rb`
- `Formula/libangle.rb`
- `Formula/libepoxy-angle.rb`

`Formula/gn.rb` has no bottle block (it is built from source every time as a
build-only tool dependency of libangle) and is excluded from this convention.

**Also bump the workflow runner in the same commit.** All three
publish-chain jobs in `.github/workflows/publish.yml` (`publish`,
`release`, `verify`) declare `runs-on: macos-NN`. When bumping, update
all three sites at once — the workflow file has a `sed` recipe in a
top-of-file comment you can paste, e.g.:

```sh
sed -i '' 's/macos-26/macos-27/g' .github/workflows/publish.yml
```

`env:` cannot be referenced inside `runs-on:` (the expression context
is limited there), so the value is inlined in each job. Using `sed`
keeps the three sites in sync so a partial migration can't leave one
job on the old image. Leaving runner labels and `rebuild` out of sync
would build bottles on a runner that doesn't match the bottle tag in
the formulae, which Homebrew will reject.

Do not change `rebuild` or the runner at any other time.

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

1. Commit changes (including any `rebuild` bump).
2. Push to `main`.
3. Trigger the build: `gh workflow run publish.yml` (workflow_dispatch only).
4. CI (~30 min) prunes the previous release, publishes fresh bottles named
   `<formula>-<version>.<tag>.bottle.<N>.tar.gz`, and commits the updated
   bottle blocks back to `main`.
5. Verify: `gh release view latest --json assets` shows `.bottle.<N>.tar.gz`
   for all four formulae on `arm64_tahoe`.

## Local install

```sh
brew install milesbuckton/qemu-virgl/qemu-virgl
```

The formulae intentionally shadow the standard `qemu`/`libepoxy` kegs and are
not linked; invoke binaries via their Cellar path or follow the caveats printed
after install.
