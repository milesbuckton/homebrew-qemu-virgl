# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Sources are branches, not revisions

Every formula tracks a moving branch on purpose — there is no `revision:` on
any `url`. ANGLE, QEMU and virglrenderer all develop fast, and the maintainer
prepares bottles on demand rather than tracking upstream releases.

The cost is that a fresh source build can break at any upstream commit. Two
consequences to keep in mind when editing these formulae:

- **Assert every patch.** `inreplace`'s block form and `String#gsub!` no-op
  silently when the pattern is gone, which on a moving branch means either a
  baffling build failure or a patch that was never applied.
  `Formula/libangle.rb` routes its Chromium `toolchain.gni`/`angle.gni` patches
  through a `patch!` helper that raises on a miss; use it rather than
  reintroducing bare `inreplace`/`gsub!`.
- **Bottles are only reproducible for the published tag.** Re-running
  `publish.yml` is what pins a known-good build; a source build on an arbitrary
  day may differ.

## Builds must not touch the network

`deny_network_access!` is the homebrew-core convention and what makes the rule
enforced: it fails the build outright. `brew audit --strict` (run by
`style.yml`) does **not** detect network access, so a formula that fetches
during `install` is only caught by the deny itself.

The Python steps in `qemu-virgl` and `virglrenderer` therefore go through
`HermeticVenv` in `lib/hermetic_venv.rb`, which installs a pinned,
checksummed build backend from a local wheelhouse and then installs each
package with `--no-index --no-build-isolation`.

QEMU needed more than a hermetic venv. Its `configure` is a shell script that
drives meson, and on a network-enabled machine it quietly fetched three things
`deny_network_access!` then turned into build failures: `mkvenv.py`
pip-installs the `qemu.qmp` build dependency from PyPI, meson clones the
`keycodemapdb` subproject from gitlab.com through `subprojects/keycodemapdb.wrap`,
and the test suite clones two more wraps. `Formula/qemu-virgl.rb` closes all
three with `--disable-download` (which configures meson's
`--wrap-mode=nodownload` and drops mkvenv's `--online`), a pinned `keycodemapdb`
resource staged into `subprojects/` — meson prefers an existing subproject
directory over the wrap — and `--disable-tests`, since nothing outside `tests/`
links those libraries and they are not installed. The wrap's pinned revision is
asserted against the resource's URL so a branch move that bumps it fails loudly
instead of shipping stale keymaps.

`--no-index` makes a **missing build requirement a hard error**, so any new
Python resource must ship its whole build backend in the wheelhouse — not just
the package itself. The transitive pins are easy to miss and were found the
hard way: `wheel` needs `packaging`, `tomli` builds with `flit_core` rather than
setuptools, and `pyyaml` needs `cython` on Python >= 3.13. Each is declared as
its own `resource` with a `sha256`.

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
   `<formula>-<version>.<tag>.bottle.tar.gz`, and amends the updated
   bottle blocks back into the root commit on `main`.
5. Verify: `gh release view latest --json assets` shows `.bottle.tar.gz`
   for all four formulae on `arm64_golden_gate`.
6. Style: the publish run's force-push to `main` uses the default
   `GITHUB_TOKEN`, which GitHub's `push` trigger ignores, so no
   `Homebrew style` run fires after a publish. Dispatch it manually
   (`gh workflow run style.yml`) if you want the amended bottle-block
   commit linted.

### The publish window

Because the `latest` release is pruned and recreated **in place**, the
new assets live at exactly the URLs the previous bottle blocks already
point at. Between the `release` job uploading assets and its later step
amending `main`, `main`'s bottle blocks name the *old* checksums for the
*new* files, so every `brew install` fails a checksum mismatch until the
amend lands. This is inherent to a fixed tag with fixed filenames and
cannot be removed without reintroducing per-run tags.

It is kept short and self-healing instead:

- `Create release and upload bottles` uses `gh release upload --clobber`
  when the release already exists, so a re-run does not die on
  `already_exists`.
- `Amend bottle blocks into root commit` retries `--force-with-lease`
  three times, rebasing onto any newer `origin/main` rather than
  clobbering it, and then re-verifies against the remote. A mismatch
  fails the job loudly instead of leaving the tap quietly broken.
- The `verify` job pours the published bottles, so a bad swap is caught
  rather than shipped.

Do not reorder these steps to "publish the formula first": the assets
would not exist yet, and `brew install` would 404 instead of failing a
checksum.

## Local install

```sh
brew install milesbuckton/qemu-virgl/qemu-virgl
```

The formulae intentionally shadow the standard `qemu`/`libepoxy` kegs and are
not linked; invoke binaries via their Cellar path or follow the caveats printed
after install.
