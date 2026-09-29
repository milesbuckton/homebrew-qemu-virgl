# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Bottle naming

Bottles are published as `<formula>-<version>.<tag>.bottle.tar.gz`; the only
platform marker in the name is the Homebrew bottle tag (the macOS codename),
e.g. `arm64_golden_gate`. There is deliberately **no rebuild number**:
`brew bottle` only writes a `rebuild N` line into the bottle block — and only
then appends `.bottle.N` to the archive name — when the formula already
declares one, so none of the four bottle-bearing formulae may ever gain a
`rebuild` line:

- `Formula/qemu-virgl.rb`
- `Formula/virglrenderer.rb`
- `Formula/libangle.rb`
- `Formula/libepoxy-angle.rb`

`Formula/gn.rb` has no bottle block (it is built from source every time as a
build-only tool dependency of libangle).

Because the formulae carry no `rebuild` line, the publish job must pass
`--no-rebuild` to every `brew bottle` call: current Homebrew *derives* a
rebuild on its own when a formula's `pkg_version` matches the one committed at
the tap's `origin/HEAD` (it uses the upstream bottle rebuild + 1), so an
unversioned formula would otherwise bottle as `<formula>-<version>.<tag>.bottle.1.tar.gz`
with `"rebuild": 1` in the bottle JSON — and `brew bottle --merge` writes that
`rebuild 1` back into the formula, while the release job's `sed` guard strips it
again, leaving the committed formula requesting an un-numbered URL that does not
exist on the release (a 404 in `verify`). `--no-rebuild` forces rebuild 0, so the
archive name and the bottle block always agree.

`.github/workflows/publish.yml` strips any `rebuild N` line from the formulae
twice — after tapping (before `brew bottle` builds) and again after
`brew bottle --merge --write` — so a stray rebuild cannot reappear and pin
`.bottle.N.tar.gz` onto the archive names.

Since the archive name does not move when a formula is rebuilt for the same
version, each publish run relies on the release being pruned and recreated
(see the release flow below): the previous tarballs are replaced outright,
and the `sha256` written into the merged bottle block is what invalidates a
user's cached copy.

### The runner

All three publish-chain jobs in `.github/workflows/publish.yml` (`publish`,
`release`, `verify`) declare the same `runs-on` image. GitHub no longer
ships `macos-NN` labels — macOS images are Xcode-versioned now, and
`xcode-27` runs on macOS 27. When a new macOS generation arrives, update
all three sites at once — the workflow file has a `sed` recipe in a
top-of-file comment you can paste, e.g. for the next generation:

```sh
sed -i '' 's/xcode-27/xcode-28/g' .github/workflows/publish.yml
```

`env:` cannot be referenced inside `runs-on:` (the expression context
is limited there), so the value is inlined in each job. Using `sed`
keeps the three sites in sync so a partial migration can't leave one
job on the old image. A runner that doesn't match the bottle tag in the
formulae would build bottles Homebrew will reject.

Do not change the runner at any other time.

**Also update the macOS codename** in bottle tags and comments wherever it
appears. Homebrew bottle tags use the format `arm64_<codename>` (e.g.
`arm64_golden_gate` for macOS 27). When bumping
the macOS version, update the codename in all of these locations:

- `Formula/qemu-virgl.rb`, `Formula/virglrenderer.rb`,
  `Formula/libangle.rb`, `Formula/libepoxy-angle.rb` — bottle tag key
- `.github/workflows/publish.yml` — artifact name, comments, release notes
- `README.md` — bottle tag reference
- `AGENTS.md` — release verification step

### The release tag is fixed

Releases are always published under the tag `latest`, giving every formula a
permanent `root_url` (`.../releases/download/latest`), so never reintroduce
per-run timestamped tags: the release is pruned and recreated under the same
tag on every run instead. Only checksums are expected to differ between
builds.

## Release flow

1. Commit changes.
2. Push to `main`.
3. Trigger the build: `gh workflow run publish.yml` (workflow_dispatch only).
4. CI (~30 min) prunes the previous release, publishes fresh bottles named
   `<formula>-<version>.<tag>.bottle.tar.gz`, and commits the updated
   bottle blocks back to `main`.
5. Verify: `gh release view latest --json assets` shows `.bottle.tar.gz`
   for all four formulae on `arm64_golden_gate`.

## Local install

```sh
brew install milesbuckton/qemu-virgl/qemu-virgl
```

The formulae intentionally shadow the standard `qemu`/`libepoxy` kegs and are
not linked; invoke binaries via their Cellar path or follow the caveats printed
after install.
