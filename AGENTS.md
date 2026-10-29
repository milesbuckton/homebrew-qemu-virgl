# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Sources are branches, not revisions

Every formula tracks a moving branch on purpose — there is no `revision:` on
any `url`. ANGLE, QEMU and virglrenderer all develop fast, and the maintainer
prepares bottles on demand rather than tracking upstream releases.

The cost is that a fresh source build can break at any upstream commit. Two
consequences to keep in mind when editing these formulae:

- **Assert every patch.** `inreplace`'s *block* form and `String#gsub!` no-op
  silently when the pattern is gone, which on a moving branch means either a
  baffling build failure or a patch that was never applied. (The three-argument
  `inreplace` form does raise on a miss, but with a generic message that does
  not say which patch failed.)
  `Formula/libangle.rb` routes its Chromium `toolchain.gni`/`angle.gni` patches
  through a `patch!` helper that raises on a miss; use it rather than
  reintroducing bare `inreplace`/`gsub!`.
- **Assert the staged revisions, too.** Patches are not the only thing that
  drifts under a moving branch. `Formula/libangle.rb` stages nine Chromium,
  SPIR-V, Vulkan and zstd trees that ANGLE's `DEPS` file pins by revision, and
  nothing in ANGLE's build files asserts that the staged tree matches DEPS —
  a stale tree still builds, just wrongly. `DepsGuard` in `lib/deps_guard.rb`
  reads the fetched tree's `DEPS` and fails the build when a staged revision
  no longer matches; see "ANGLE stages DEPS-managed trees by hand" below.
- **Assert the staged trees are complete, too.** A revision guard only sees
  the dependencies the formula already knows about. When ANGLE *adds* a
  DEPS-managed dependency, nothing here notices until ninja fails with an
  opaque "missing and no known rule to make it". `StagedTreeGuard` in
  `lib/staged_tree_guard.rb` closes that gap; see the same section below.
- **Bottles are only reproducible for the published tag.** Re-running
  `publish.yml` is what pins a known-good build; a source build on an arbitrary
  day may differ.

### The one audit rule this tap does not satisfy

Homebrew commit `85ffa721b0` ("Require verifiable official formula sources",
2026-10-17) added this rule to `ResourceAuditor#audit_download_strategy`:

```ruby
if (using == :git || url_strategy == GitDownloadStrategy) && specs[:tag] && !specs[:revision]
  problem "Git should specify `revision:` when a `tag:` is specified."
elsif !version&.head? && DownloadStrategyDetector.detect(url!, using) <= GitDownloadStrategy &&
      !specs[:revision].to_s.match?(/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i)
  problem "Git should specify a full commit hash in `revision:`."
end
```

It fires for every Git source that is not pinned to a commit hash, unless the
spec's version is `HEAD` — which is how upstream spells "this formula tracks
a moving branch". It applies to third-party taps too, so `brew audit --strict`
reports it for all five formulae here, and it reports nothing else.

The `elsif` above is the branch that fires here; the `if` above it is the
sibling rule about a `tag:` without a `revision:`, quoted so the rule reads as
upstream wrote it.

There is no way to satisfy it without changing what this tap is:

- Adding `revision:` would freeze the sources — the opposite of the design.
  It would also be fake compliance: `VCSDownloadStrategy::REF_TYPES` takes the
  *first* of `:tag, :branch, :revisions, :revision` that is present, so with
  `branch:` also set, the `revision:` is never used for the checkout.
- `version "HEAD"` is upstream's blessed shape for a moving source, but it
  makes Homebrew treat the installed keg as a HEAD keg. `brew outdated` and
  `brew upgrade` skip HEAD kegs entirely, so the branch would stop moving for
  users; the published bottle names would also change from
  `<formula>-<version>.<tag>.bottle.tar.gz` to
  `<formula>-HEAD.<tag>.bottle.tar.gz`, which breaks the release layout
  described below.

So `script/audit.sh` runs `brew audit --strict` and tolerates **exactly** that
one message:

- Every other problem still fails the job, including the other rules in the
  same audit method ("Git should specify `revision:` when a `tag:` is
  specified.", "Redundant `using:` value in URL", the CVS rules).
- The expectation is derived from each formula (a stable spec with a
  `branch:`, no `revision:` and a non-HEAD version), not from a hard-coded
  list of names, so a new formula is covered without editing the script.

### The rule is not in any release yet

`85ffa721b0` is on Homebrew's `master` and in **no release tag** —
`git tag --contains 85ffa721b0` comes back empty, and `7.0.9` and `7.0.10`
both lack the rule. The GitHub runner's Homebrew is therefore usually *older*
than the rule, and `brew audit` there reports nothing for it at all.

So the script must not assume the rule exists. It asks the Homebrew that is
about to run the audit: it builds a throwaway `Resource` pointing at a
`branch:` (never downloaded) and hands it to that Homebrew's own
`ResourceAuditor`, and reads the result back. Five states follow, and the
script refuses to guess between them:

| state | how it is recognised | what the script does |
| --- | --- | --- |
| `present` | the probe's audit reports the message | expect the message once per branch-tracking formula |
| `changed` | the rule's text is in the auditor's source but the probe did not report it | fail: upstream changed the rule's shape, update the script |
| `removed` | this Homebrew's git history contains `85ffa721b0` but the rule is gone | fail: the exemption is no longer needed, update the script |
| `absent` | the rule is neither in the source nor in the history | warn, expect no message, fail on every other problem |
| `broken` | the probe itself could not run | fail: the script cannot tell what this Homebrew does, update the script |

`present` and `changed` are told apart by the probe, `removed` from `absent`
by `git merge-base --is-ancestor 85ffa721b0 HEAD` against
`$(brew --repository)`. An older Homebrew is therefore a warning, not a
failure — but the moment the rule turns up in the Homebrew that is running
the audit, the exemption is enforced again, so it cannot rot unnoticed. A
broken probe fails rather than being read as "the rule is not there": a probe
that cannot run must not silently drop the exemption.

`brew audit --only=download_strategy` and `--except=download_strategy` are
*not* the answer: they gate whole audit methods, so the first skips every
other rule and the second skips the other rules in the same method.

### `brew test` and Homebrew's own type check

`brew test` is the only command in a publish run that loads *core* formulae
from Homebrew's API, and it is the only one that runs with Sorbet's runtime
type checking switched on — `brew.sh` sets `HOMEBREW_SORBET_RUNTIME=1` for
`brew test`, `brew test-bot` and `brew tests` (and only for those).

That combination is a trap: the API publishes formulae in a shape that the
Homebrew on the runner may not be able to *read*. The API now emits a
dependency entry with **combined role tags** — `{"pkgconf" => [":build",
":test"]}` — while Homebrew 7.0.9 (the version the `xcode-27` runner image
ships) types a dependency entry as `T::Hash[String, Symbol]`. Assigning the
prop then raises

```text
Parameter 'head_dependencies': Can't set Homebrew::API::FormulaStruct.head_dependencies
to [... {"pkgconf" => [:build, :test]} ...] (instance of Array) - need a
T::Array[T.any(String, Symbol, T::Hash[String, Symbol], ...)]
```

and the whole test step dies — on a core formula (`glib`) that has nothing
to do with this tap. Homebrew widened the type in 7.0.10 (commit
`d323f2407913a03ce5cc3378c2dd0703e6a71622`, "Accept dependency tag arrays
in API metadata"), but the runner image pins an older Homebrew and the
workflow never updates it.

So the test step asks the Homebrew that is about to run the tests rather
than assuming a version. It probes the *type* that Homebrew actually has:

```ruby
type = Homebrew::API::FormulaStruct.decorator.prop_rules(:stable_dependencies)[:type]
type.recursively_valid?([{ "probe-dep" => [:build, :test] }])
```

`recursively_valid?` is the same predicate the props setter uses, so the
probe predicts the failure exactly, and it answers without the runtime
type check being active — it works under a plain `brew ruby`. If the type
is too narrow, the step sets `HOMEBREW_TESTS_NO_SORBET_RUNTIME=1`, Homebrew's
own escape hatch: `brew.sh` unsets `HOMEBREW_SORBET_RUNTIME` when it is
set, and the type check never runs. It is present in every Homebrew release
from 6.0.11 to 7.0.10, and it changes nothing else — the same formulae are
loaded and the same tests run.

If the probe cannot decide, the workaround is applied anyway: it is safe on
any Homebrew (it only skips a type check), whereas guessing wrong leaves
the step failing on a core formula. When the runner's Homebrew widens the
type, the probe reports `wide` and the workaround retires itself.

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
asserted against the resource's URL via `WrapGuard` in `lib/wrap_guard.rb` so a
branch move that bumps it fails loudly instead of shipping stale keymaps. The
same helper is available to any formula that stages a meson subproject resource
(e.g. `virglrenderer` keeps its own stricter tag-resolution check alongside it).

`--no-index` makes a **missing build requirement a hard error**, so any new
Python resource must ship its whole build backend in the wheelhouse — not just
the package itself. The transitive pins are easy to miss and were found the
hard way: `wheel` needs `packaging`, `tomli` builds with `flit_core` rather than
setuptools, and `pyyaml` needs `cython` on Python >= 3.13. Each is declared as
its own `resource` with a `sha256`.

`style.yml` checks the coupling that is easy to break by accident: every
`resource` that both `qemu-virgl.rb` and `virglrenderer.rb` declare must be
byte-identical in the two files, must play the same role in both (a venv
build backend in one and a runtime package in the other breaks one build and
not the other), and every resource the venv installs must be declared at all.
The shared set is derived from the formulae, not listed in the workflow, so a
resource that becomes shared later is covered without editing `style.yml`.

### The Python pin moves as one piece

The interpreter is pinned once, in `HermeticVenv::PYTHON`
(`lib/hermetic_venv.rb`), and that constant is the source of truth. But the
pin has a second life in the formulae, and a bump that misses one of its
sites breaks a build *late* — in the publish run, half an hour in, instead
of in `style.yml`:

- `depends_on "python@3.15" => :build` in **five** formulae: `gn`,
  `libangle`, `libepoxy-angle`, `virglrenderer` and `qemu-virgl`.
- The two versioned interpreter paths, `formula_opt_bin("python@3.15")/"python3.15"`
  in `gn.rb` and `libangle.rb`.
- The workflow's `brew install python@3.15` / `brew link --overwrite --force
  python@3.15` step, and the README's mention of it.

`style.yml` derives the pin from `lib/hermetic_venv.rb` and fails when any
`Formula/*.rb` mentions a different `python@3.x`, or when `gn.rb` /
`libangle.rb` mention a different `python3.x` binary. The workflow step and
the README are not covered by that check — they are prose and shell, and
`style.yml` cannot see them.

Two things make the bump safe on the runner: `python@3.15` is bottled in
homebrew-core (so the runner installs it from a bottle, like every other
Python), and its dependency set is identical to `python@3.14`'s — the same
`openssl@4`, `sqlite`, `lz4`, `readline`, `mpdecimal` and `zstd`. The
runner image's own preinstalled Python is 3.15, so the "the runner ships an
`idle3.x` that blocks `brew link`" problem now applies to `idle3.15`; the
force-link is still needed.

## ANGLE stages DEPS-managed trees by hand

ANGLE's `main` branch tracks Chromium's `main` branch, and ANGLE's `DEPS`
file pins the exact revision of every Chromium sub-repository it needs. This
tap cannot run `gclient sync`: ANGLE's submodules point at
`chrome-internal.googlesource.com`, which needs authentication. So
`Formula/libangle.rb` stages the DEPS-managed trees by hand from checksummed
`resource` blocks, and that inverts what the pins mean. A resource's
`revision:` is no longer "whatever we last synced to" but "whatever ANGLE's
DEPS currently says" — when Chromium rolls a dependency and ANGLE's autoroller
follows, the staged tree silently becomes *older* than what ANGLE expects, and
the build still succeeds because nothing in ANGLE's build files compares the
two.

`DepsGuard` in `lib/deps_guard.rb` closes that gap. It reads the `DEPS` file
that is already in the fetched source tree — no network access — and fails the
build when a staged revision no longer matches:

- `assert_deps_revisions!` covers the dependencies DEPS names in its `deps`
  block (`build`, `third_party/zlib`, `third_party/spirv-headers/src`, …).
  The formula's `DEPS_ENTRIES` map ties each `resource` name to the DEPS key
  it is checked against.
- `assert_deps_var_revisions!` covers the ones DEPS pins through a *variable*
  instead of an entry, because the dependency is nested inside another one:
  upstream jsoncpp is pinned by the `jsoncpp_revision` variable and appears
  nowhere in `deps` at all. The formula's `DEPS_VAR_ENTRIES` map covers those.

DEPS is a Python dict literal, so it is parsed as text with a regex rather
than evaluated — evaluating it would run upstream code inside a build.

### A new dependency is a different failure

`DepsGuard` only sees the dependencies the formula *already* stages. When
ANGLE *adds* one, there is no `resource` for it, so the tree is simply absent
and the guard has nothing to compare — the build then dies inside ninja with
an opaque:

```text
ninja: error: '../../third_party/zstd/src/lib/compress/fse_compress.c',
needed by 'obj/third_party/zstd/compress/fse_compress.o', missing and no
known rule to make it
```

That is not hypothetical: ANGLE commit `d93773830a` ("DEPS: Add zstd to
third_party") added `third_party/zstd/src`, and commit `29388bec65` ("Add
zstd support to compression helpers") made `angle_compression` — a dependency
of `angle_common` — require it. `gn gen` happily writes a build graph naming
files that do not exist, and `gn check` cannot be used instead: it reports a
false positive for the Homebrew `rapidjson` keg, whose headers predate
`rapidjson/cursorstreamwrapper.h`.

`StagedTreeGuard` in `lib/staged_tree_guard.rb` closes the gap from the
*build graph* side rather than from DEPS. `gn gen` writes
`out/Release/compile_commands.json`, listing every translation unit the
generated graph compiles; each of those files must exist before ninja runs.
The guard walks that database after `gn gen` and fails the build when a named
source is missing, grouping the missing files by the tree they live in so the
message names a DEPS dependency to stage:

```text
ANGLE's build graph needs source files that are not staged:
  - third_party/zstd/src: 26 file(s) missing, e.g. third_party/zstd/src/lib/common/debug.c
```

A missing `compile_commands.json` is itself an error — a guard that cannot
read the database must fail, not pass.

Note that this does not save build time: the real ninja build already fails
fast (0.09s, in its graph evaluation). The guard changes the *message*, from
an opaque ninja error to a statement of which dependency has to be staged.

Two rules for editing the pins:

- **Take the revision from DEPS, not from upstream's HEAD.** The `resource`
  block and the DEPS entry must name the same commit; the guard fails the
  build when they disagree.
- **Fetch Chromium from `chromium.googlesource.com`, not from the
  `gsource-mirror` GitHub mirrors.** The mirrors lag behind and do not carry
  the current DEPS revisions at all ("fatal: remote error: upload-pack: not
  our ref `<rev>`"), so a DEPS-driven bump from a mirror is impossible.

When the guard fires, also re-check the `toolchain.gni` patches: the staged
Chromium tree changes shape between revisions, and the `patch!` helper will
tell you which pattern no longer matches.

### Staging a DEPS-managed tree

Not every DEPS entry is a directory of its own. ANGLE tracks some trees as
*gitlinks* — a mode-160000 entry pointing at another repository — and those
have to be staged by hand, because `NoSubmoduleGitDownloadStrategy` does not
clone them. The shape differs per dependency:

- `third_party/zlib`, `third_party/jsoncpp`, `third_party/spirv-headers/src`
  and the other gitlinks are the whole tree; stage the checkout at that path.
- `third_party/zstd` is a **plain directory** in ANGLE's own tree — it holds
  ANGLE's `BUILD.gn` and the `src` gitlink below it. Only `src` has to be
  staged; the `BUILD.gn` comes with the checkout. ANGLE's `BUILD.gn` refers to
  `$angle_zstd_dir/src/lib`, so the *whole* zstd repository is staged under
  `third_party/zstd/src`, not just its `lib` directory.
- `third_party/rapidjson` and `third_party/llvm` are plain directories
  ANGLE carries itself and are never staged.

## QEMU's submodules are not needed

QEMU's tree declares 15 submodules under `roms/` (plus one under `tests/`).
None of them is needed for the `aarch64-softmmu`-only build this tap makes:
every ROM blob the build installs is committed in `pc-bios/`, and no
`meson.build` outside `roms/` refers to a `roms/` path. QEMU's `configure`
never asks for them either — its only `git-submodule.sh` call is guarded by
`have_target s390x-softmmu`. `Formula/qemu-virgl.rb` therefore fetches the
source with `NoSubmoduleGitDownloadStrategy`
(`lib/no_submodule_git_download_strategy.rb`, which ANGLE also uses for its
private submodules) instead of cloning several hundred megabytes of ROM
toolchains that the build throws away.

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
version, each publish run relies on the release being **updated in place**
(see the release flow below): `gh release upload --clobber` replaces the
previous tarballs outright under the fixed tag, and the `sha256` written
into the merged bottle block is what invalidates a user's cached copy. The
release itself is never deleted — deleting it would 404 every formula's
pinned `root_url` for as long as the gap lasts.

### The runner

All three publish-chain jobs in `.github/workflows/publish.yml` (`publish`,
`release`, `verify`) declare the same `runs-on` image, and the style job in
`.github/workflows/style.yml` declares the same one (a fourth site). GitHub
no longer ships `macos-NN` labels — macOS images are Xcode-versioned now,
and `xcode-27` runs on macOS 27. When a new macOS generation arrives, update
all four sites at once — `publish.yml` has a `sed` recipe in a top-of-file
comment covering both workflow files, e.g. for the next generation:

```sh
sed -i '' 's/xcode-27/xcode-28/g' \
  .github/workflows/publish.yml .github/workflows/style.yml
```

`env:` cannot be referenced inside `runs-on:` (the expression context
is limited there), so the value is inlined in each job. Using `sed`
keeps the four sites in sync so a partial migration can't leave one
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
per-run timestamped tags: the release is updated in place under the same
tag on every run instead (assets are re-uploaded with `--clobber`; the
release object is never deleted). Only checksums are expected to differ
between builds.

## Release flow

1. Commit changes.
2. Push to `main`.
3. Trigger the build: `gh workflow run publish.yml` (workflow_dispatch only).
4. CI (~30 min) updates the `latest` release in place (uploading fresh
   bottles named `<formula>-<version>.<tag>.bottle.tar.gz` with
   `--clobber`, replacing the previous assets), and squashes the updated
   bottle
   blocks into `main`'s single root commit — rewriting `main` and moving the
   `latest` tag onto the result (see the publish window below).
5. Verify: `gh release view latest --json assets` shows `.bottle.tar.gz`
   for all four formulae on `arm64_golden_gate`.
6. Style: the publish run's push to `main` uses the default
   `GITHUB_TOKEN`, which GitHub's `push` trigger ignores, so no
   `Homebrew style` run fires after a publish. Style is never
   scheduled; dispatch it manually (`gh workflow run style.yml`) if
   you want the bottle-block commit linted.

### The publish window

Because the `latest` release is updated **in place** (assets re-uploaded
with `--clobber`, never deleted first), the
new assets live at exactly the URLs the previous bottle blocks already
point at. Between the `release` job uploading assets and its later step
committing the bottle blocks to `main`, `main`'s bottle blocks name the
*old* checksums for the *new* files, so every `brew install` fails a
checksum mismatch until that commit lands. This is inherent to a fixed
tag with fixed filenames and cannot be removed without reintroducing
per-run tags.

It is kept short and self-healing instead:

- `Create release and upload bottles` uses `gh release upload --clobber`
  when the release already exists, so a re-run does not die on
  `already_exists`. It also re-publishes the release if it is ever found
  as a draft: a draft's assets are served under
  `.../releases/download/untagged-<sha>/...` instead of the pinned
  `.../releases/download/latest/...`, so a drafted `latest` 404s every
  formula. (`gh release create` makes a draft whenever the tag does not
  exist yet, which is exactly the state the tag-recovery branch above it
  guards against — but a release drafted by hand hits the same failure
  and is healed the same way.)
- `Commit bottle blocks to main` squashes the merged blocks into `main`'s
  existing root commit and force-pushes `main` with `--force-with-lease`, so
  `main` stays a single commit and the rewritten commit keeps the root
  commit's message and authorship. Nothing that landed on `main` while the
  run was building is clobbered: every attempt re-derives the squashed commit
  from a freshly fetched `origin/main`, folding those newer commits in (and
  warning which ones) rather than dropping them, while a genuine conflict in
  the same formula lines fails the job loudly. It then re-verifies against
  the remote; a mismatch fails the job instead of leaving the tap quietly
  broken.
- The `verify` job pours the published bottles, so a bad swap is caught
  rather than shipped.

Because `main` is rewritten, every publish leaves a checkout of `main`
diverged from `origin/main`: `git pull` reports a conflict and
`git reset --hard origin/main` is the way back. The `verify` job does exactly
that before it installs.

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
