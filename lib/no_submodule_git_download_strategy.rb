# typed: false
# frozen_string_literal: true

# Clone a git repo without its submodules.
#
# `GitDownloadStrategy#submodules?` is `cached_location/".gitmodules".exist?`,
# and Homebrew offers no opt-out, so the only way to skip them is to override
# it. Two formulas in this tap need that, for different reasons:
#
# * ANGLE's tree declares submodules that point at
#   `chrome-internal.googlesource.com`, which needs authentication. ANGLE's
#   DEPS-managed `third_party/*` dependencies are staged manually by the
#   formula instead, from checksummed `resource` blocks.
#
# * QEMU's tree declares 15 submodules under `roms/` (plus one under
#   `tests/`). None of them is needed for the aarch64-softmmu-only build this
#   tap makes: every ROM blob the build installs is committed in `pc-bios/`
#   (the `blobs` list in `pc-bios/meson.build`, and the edk2 `*.fd.bz2`
#   archives next to them), and no `meson.build` outside `roms/` refers to a
#   `roms/` path. Cloning them is pure fetch time — and QEMU's `configure`
#   never asks for them either, since its only `git-submodule.sh` call is
#   guarded by `have_target s390x-softmmu`.
class NoSubmoduleGitDownloadStrategy < GitDownloadStrategy
  def submodules?
    false
  end
end
