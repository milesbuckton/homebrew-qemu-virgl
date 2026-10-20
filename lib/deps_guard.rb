# typed: false
# frozen_string_literal: true

# Assert that the Chromium/SPIR-V/Vulkan revisions this tap stages for ANGLE
# are still the ones ANGLE's own DEPS file asks for.
#
# The problem this exists for
# ---------------------------
#
# `Formula/libangle.rb` tracks ANGLE's `main` branch, and ANGLE's `main` branch
# tracks Chromium's `main` branch. ANGLE's DEPS file pins the exact revision of
# every Chromium sub-repository it needs:
#
#   'build': {
#     'url': Var('chromium_git') + '/chromium/src/build.git@16c326db38d9...',
#   },
#   'third_party/zlib': {
#     'url': Var('chromium_git') + '/chromium/src/third_party/zlib@456ae730...',
#   },
#
# This tap does not run `gclient sync` — it cannot, because ANGLE's
# submodules point at `chrome-internal.googlesource.com`, which needs
# authentication. Instead the formula stages the DEPS-managed trees by hand
# from checksummed `resource` blocks.
#
# That inverts the role of the pins: `resource "chromium-build"`'s revision is
# no longer "whatever we last synced to" but "whatever ANGLE's DEPS currently
# says". When Chromium rolls a dependency and ANGLE's autoroller follows, the
# staged tree silently becomes *older* than what ANGLE expects. The build still
# succeeds — nothing in ANGLE's build files asserts that the staged tree
# matches DEPS — so the drift only shows up as a subtly wrong build, months
# later, with no obvious cause. This is the same silent-no-op class of failure
# that `patch!` and `WrapGuard` exist to prevent, one level up: those guard
# *patches* against upstream drift, this guards the *staged inputs*.
#
# What this guard does
# --------------------
#
# It reads ANGLE's DEPS file (already present in the fetched source tree — no
# network access needed) and asserts that every revision the formula stages is
# still named there. A revision that has been dropped from DEPS means the
# formula is staging something upstream no longer uses, and the build is
# running against a stale tree.
#
# Two properties matter:
#
#   * A revision that DEPS no longer mentions is a hard error, never a pass.
#     A missing revision is the exact signal this guard exists to raise.
#   * DEPS is a Python dict literal, so it is parsed as text with a regex
#     rather than evaluated. Evaluating it would execute upstream code during
#     a build — the one thing `deny_network_access!` and the pinned-resource
#     design exist to prevent. Only `url:` values and `Var('name')` references
#     are read, and the regex is anchored on the 40-hex-character revision
#     shape, so a stray match elsewhere in the file cannot masquerade as a pin.
#
# The revision list is a hash of { DEPS entry name => staged revision }. DEPS
# names vary with how upstream lays out the tree (`build` vs `third_party/zlib`
# vs `third_party/spirv-headers/src`), so each entry is looked up by its own
# key rather than by guessing.
module DepsGuard
  # A git revision: 40 lowercase hex characters.
  REVISION = /\b[0-9a-f]{40}\b/

  # The `deps = { ... }` entries of a DEPS file, keyed by the DEPS path.
  #
  # Only the pieces this guard needs are extracted: the entry's own `url`
  # value and the `Var('name')` references inside it. DEPS is a Python dict
  # literal; the structure is regular enough to read with a regex, and
  # evaluating it would mean running upstream code inside a build.
  #
  # Returns a Hash of { "third_party/zlib" => "<revision>" }, where the
  # revision is the one the entry's URL names. Entries whose revision comes
  # from a `Var(...)` (ANGLE's `chromium_jsoncpp_revision` for example) are
  # resolved through the file's own `vars = { ... }` block.
  def self.deps_revisions(deps_text)
    vars = parse_vars(deps_text)
    deps = deps_block(deps_text)

    deps.each_with_object({}) do |(name, body), revisions|
      url = body[/['"]url['"]:\s*(.*?)(?=,\n|\n\s*\},|\Z)/m, 1]
      next if url.nil?

      # A DEPS entry may name its revision through a variable:
      #   'url': Var('chromium_git') + '/chromium/src/third_party/jsoncpp'
      #          + '@' + Var('chromium_jsoncpp_revision')
      # Resolve the variable indirection before looking for the revision.
      resolved = url.dup
      url.scan(/Var\(['"]([a-z0-9_]+)['"]\)/).flatten.each do |var_name|
        resolved = resolved.gsub(/Var\(['"]#{var_name}['"]\)/, vars.fetch(var_name, ""))
      end

      revision = resolved[REVISION]
      revisions[name] = revision if revision
    end
  end

  # The `vars = { ... }` block, as { "name" => "value" }.
  def self.parse_vars(deps_text)
    block = deps_text[/^vars\s*=\s*\{(.*?)^\}/m, 1]
    return {} if block.nil?

    block.scan(/['"]([a-z0-9_]+)['"]:\s*['"]([^'"]*)['"]/).to_h
  end

  # The `deps = { ... }` block, as { "name" => "entry body" }.
  def self.deps_block(deps_text)
    block = deps_text[/^deps\s*=\s*\{(.*?)^\}/m, 1]
    return {} if block.nil?

    block.scan(/^\s*['"]([^'"]+)['"]:\s*\{(.*?)^  \},/m).to_h
  end

  # Raise unless every staged revision is still named by ANGLE's DEPS.
  #
  # `deps_text` is the contents of ANGLE's DEPS file, `staged` is a Hash of
  # { DEPS entry name => revision the formula stages }.
  def assert_deps_revisions!(deps_text, staged, deps_path: "DEPS")
    revisions = DepsGuard.deps_revisions(deps_text)

    stale = staged.reject do |name, revision|
      revisions[name] == revision
    end

    return if stale.empty?

    details = stale.map do |name, revision|
      current = revisions[name]
      if current.nil?
        "#{name}: DEPS no longer lists this dependency at all (staged #{revision})"
      else
        "#{name}: DEPS now pins #{current} (staged #{revision})"
      end
    end

    raise "#{deps_path} has moved past the revisions this formula stages:\n" \
          "#{details.map { |line| "  - #{line}" }.join("\n")}\n\n" \
          "ANGLE's DEPS file is the source of truth for these revisions. Update the " \
          "matching `resource` blocks in Formula/libangle.rb to the revisions DEPS now " \
          "names, and re-check the toolchain.gni patches against the new tree — the " \
          "staged Chromium tree changes shape between revisions."
  end

  # Raise unless `revision` is still the value ANGLE's DEPS file gives the
  # named variable.
  #
  # Some dependencies are pinned through a DEPS *variable* rather than through
  # a `deps` entry, because the dependency is nested inside another one:
  #
  #   vars = {
  #     'jsoncpp_revision': '42e892d96e47b1f6e29844cc705e148ec4856448',
  #   },
  #   deps = {
  #     'third_party/jsoncpp': {
  #       'url': Var('chromium_git') + '/chromium/src/third_party/jsoncpp'
  #              + '@' + Var('chromium_jsoncpp_revision'),
  #     },
  #   },
  #
  # The upstream jsoncpp repository (the one the formula stages as
  # "jsoncpp-source") is pinned by `jsoncpp_revision` alone — it appears
  # nowhere in `deps`, because Chromium's own `third_party/jsoncpp` carries it
  # as a nested `source` dependency. So it needs its own check.
  def assert_deps_var_revision!(deps_text, var_name, revision, deps_path: "DEPS")
    current = DepsGuard.parse_vars(deps_text)[var_name]

    return if current == revision

    if current.nil?
      raise "#{deps_path} no longer defines the variable #{var_name.inspect} " \
            "(staged revision #{revision}). Either upstream renamed the variable or " \
            "the dependency is gone. Update Formula/libangle.rb to match."
    end

    raise "#{deps_path} has moved past the revision this formula stages:\n  " \
          "- #{var_name}: DEPS now pins #{current} (staged #{revision})\n\n" \
          "ANGLE's DEPS file is the source of truth for these revisions. Update the " \
          "matching `resource` block in Formula/libangle.rb to the revision DEPS now " \
          "names."
  end
end
