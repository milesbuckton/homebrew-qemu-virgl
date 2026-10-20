# typed: false
# frozen_string_literal: true

require "json"

# Assert that every source ANGLE's build graph names is actually on disk.
#
# The problem this exists for
# ---------------------------
#
# `DepsGuard` covers the *staged revisions*: it fails the build when a
# `resource` block's `revision:` stops matching what ANGLE's DEPS file pins.
# It cannot cover a dependency that upstream *added*.
#
# ANGLE's DEPS file has ~80 entries; this tap stages 9 of them. When ANGLE
# adds a new DEPS-managed dependency, nothing in this tap notices: the
# formula has no `resource` for it, so the tree is simply absent, and
# `DepsGuard` — which only inspects what the formula *does* stage — stays
# silent. The build then dies much later with an opaque ninja error:
#
#   ninja: error: '../../third_party/zstd/src/lib/compress/fse_compress.c',
#   needed by 'obj/third_party/zstd/compress/fse_compress.o', missing and
#   no known rule to make it
#
# That is a real failure this tap hit: ANGLE commit d93773830a ("DEPS: Add
# zstd to third_party") added `third_party/zstd/src`, and commit 29388bec65
# ("Add zstd support to compression helpers") made `angle_compression` — a
# dependency of `angle_common` — require it.
#
# What this guard does
# --------------------
#
# `gn gen` writes `out/<dir>/compile_commands.json`, listing every
# translation unit the generated build graph compiles, with paths relative
# to the output directory. Every one of those files must exist by the time
# ninja runs. So after `gn gen`, this guard walks that database and fails
# the build if any of the named sources is missing from the source tree.
#
# Two properties matter:
#
#   * A missing source is a hard error, never a pass. The list is compared
#     against the filesystem, not against a count, so a guard that cannot
#     read the database must also fail rather than skip the check.
#   * The message names the *tree* the missing files live in, not 26
#     individual paths, because the fix is always the same: stage the
#     dependency ANGLE's DEPS now lists. Grouping by the staged-tree
#     directory turns a wall of paths into one actionable line.
#
# Why this is not `ninja -n`
# --------------------------
#
# A ninja dry run on a fresh output directory reports the same missing file
# in 0.04s, so it would work as a check too. It is not used here because
# its failure is a ninja error string, not a statement about which DEPS
# dependency is missing — the reader still has to work out that
# `third_party/zstd/src` is a DEPS entry this tap has to stage. The
# compile database carries the same information in a form that can be
# grouped by tree and reported directly.
#
# Note that the *real* ninja build fails fast too (0.09s, in its graph
# evaluation, before compiling anything) — so this guard is not saving
# build time. It is turning a 20-minute build that ends in an opaque ninja
# error into a failure that names the missing dependency.
module StagedTreeGuard
  # The source files `gn gen` says the build compiles, relative to the
  # source root.
  #
  # `compile_commands.json` paths are relative to the *output* directory
  # (`../../third_party/...`), and each entry records the directory it was
  # generated for — so the path is resolved against that, not against an
  # assumed depth below the source root.
  #
  # Paths that resolve outside the source root are dropped: they are not
  # staged dependencies, and a file the formula cannot possibly stage must
  # not be reported as one it forgot to stage.
  def staged_source_files(compile_commands_path, out_dir, source_root)
    entries = JSON.parse(compile_commands_path.read)
    entries.filter_map do |entry|
      base = entry["directory"] ? Pathname.new(entry["directory"]) : out_dir
      path = Pathname.new(entry["file"]).expand_path(base).relative_path_from(source_root)
      path unless path.to_s.start_with?("../")
    end.uniq
  end

  # Raise unless every source the build graph names is on disk.
  #
  # `compile_commands_path` is the `compile_commands.json` gn wrote,
  # `out_dir` is the gn output directory it was written into, and
  # `source_root` is the root of the source tree the paths are relative to.
  def assert_staged_trees_present!(compile_commands_path, out_dir, source_root)
    unless compile_commands_path.exist?
      raise "#{compile_commands_path} is missing; cannot verify that ANGLE's " \
            "staged dependencies are complete"
    end

    missing = staged_source_files(compile_commands_path, out_dir, source_root).reject do |path|
      (source_root/path).exist?
    end

    return if missing.empty?

    # Group by the tree the file lives in, so the message names a dependency
    # to stage rather than a list of files to find.
    trees = missing.group_by { |path| staged_tree(path) }

    details = trees.sort_by { |tree, _| tree.to_s }.map do |tree, paths|
      "  - #{tree}: #{paths.size} file(s) missing, e.g. #{paths.min}"
    end

    raise "ANGLE's build graph needs source files that are not staged:\n" \
          "#{details.join("\n")}\n\n" \
          "#{missing_tree_hint(trees)}"
  end

  # What to tell the reader to do about the missing trees.
  #
  # A missing tree under `third_party/` is a DEPS-managed dependency this
  # tap has to stage. Anything else is a different kind of problem — an
  # incomplete checkout — and gets different advice.
  def missing_tree_hint(trees)
    if trees.keys.any? { |tree| tree.to_s.start_with?("third_party/") }
      "ANGLE's DEPS file lists a dependency this formula does not stage yet. " \
        "Add a `resource` for it (with the revision DEPS pins) and stage it into " \
        "the tree named above, then add it to DEPS_ENTRIES in Formula/libangle.rb. " \
        "The DEPS entry name is the path in the list above."
    else
      "The source tree ANGLE checked out is incomplete. Re-check that the " \
        "checkout was staged correctly."
    end
  end

  # The tree a source path belongs to.
  #
  # `third_party/zstd/src/lib/compress/fse_compress.c` belongs to
  # `third_party/zstd/src` — the path the DEPS entry uses — not to
  # `third_party/zstd`, which is a plain directory in ANGLE's own tree. That
  # is the difference that makes the message actionable: `third_party/zstd/src`
  # is a DEPS entry, `third_party/zstd` is not.
  #
  # A path outside any staged tree is reported under its top-level
  # directory, so the message still says where to look.
  def staged_tree(path)
    parts = path.each_filename.to_a
    return "" if parts.empty?

    if parts.first == "third_party"
      # A DEPS-managed tree is `third_party/<name>` or
      # `third_party/<name>/<subdir>`.
      return parts.first if parts.size < 2

      if parts.size >= 3
        parts[0, 3].join("/")
      else
        parts[0, 2].join("/")
      end
    else
      # `build` and `testing` are staged trees in their own right; anything
      # else is ANGLE's own source, reported under its top-level directory.
      parts.first
    end
  end
end
