# typed: false
# frozen_string_literal: true

# Clone a git repo without its submodules.
#
# ANGLE's tree declares submodules that point at `chrome-internal.googlesource.com`,
# which needs authentication. `GitDownloadStrategy#submodules?` is
# `cached_location/".gitmodules".exist?`, and Homebrew offers no opt-out, so the
# only way to skip them is to override it.
#
# ANGLE's DEPS-managed `third_party/*` dependencies are staged manually by the
# formula instead, from checksummed `resource` blocks.
class NoSubmoduleGitDownloadStrategy < GitDownloadStrategy
  def submodules?
    false
  end
end
