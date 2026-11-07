# typed: false
# frozen_string_literal: true

# Assert that a meson wrap file agrees with the resource staged in its place.
#
# Both meson-driven formulae in this tap stage a pinned resource into
# `subprojects/` so meson never downloads: meson prefers an existing
# subproject directory over the wrap. That inverts the wrap's role — meson
# only consults it when it must download, so once the directory is staged the
# wrap becomes documentation, and an upstream branch move that bumps the
# wrap's pinned revision would otherwise leave the staged copy silently stale
# (older keymaps / protocol headers, still building).
#
# `assert_wrap_revision_matches_url!` is the guard against that drift. Two
# properties matter:
#
#   * A wrap without a parseable `revision =` line is a hard error, never a
#     pass. `nil.to_s` is `""`, and `String#include?("")` is always true, so
#     comparing without the nil check would make the assertion vacuous — the
#     same silent-no-op failure class `patch!` exists to prevent.
#   * The regex tolerates drift in spacing (`revision  = <rev>`, indented,
#     CRLF): upstream wrap files are not formatted to our taste.
#
# The virglrenderer formula's check is stricter still (its wrap pins a *tag*
# while the resource pins the commit the tag resolves to, so it resolves the
# tag in the resource's git cache) and keeps its own implementation in
# `Formula/virglrenderer.rb`; this helper covers the simpler case where the
# pinned revision is expected to appear in the resource URL verbatim.
module WrapGuard
  def assert_wrap_revision_matches_url!(wrap_path, resource_name)
    wrap_revision = wrap_path.read[/^revision\s*=\s*(\S+)\s*$/, 1]
    if wrap_revision.to_s.empty?
      raise "#{wrap_path} does not declare a revision; " \
            "refusing to stage #{resource_name} against an unverifiable wrap"
    end
    return if resource(resource_name).url.include?(wrap_revision)

    raise "#{wrap_path} pins revision #{wrap_revision.inspect}, " \
          "but the staged #{resource_name} resource targets a different revision"
  end
end
