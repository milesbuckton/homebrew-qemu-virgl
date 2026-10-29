#!/usr/bin/env bash
#
# Assert that the installed tap formulae are actually wired together the way the
# README claims, and fail the build when they are not.
#
# This is deliberately a set of hard assertions. The previous version of this
# check ran under `set +e` and printed a warning after every probe, so it could
# never fail a publish run: a build that dropped ANGLE entirely would still go
# green. A warning that cannot fail the job is not a check.
#
# Two of the assertions are worth calling out because the obvious probe gets
# them wrong:
#
#   * Nothing links libangle directly. libepoxy dlopens EGL at runtime, and
#     QEMU links only libepoxy and libvirglrenderer. Grepping the QEMU binary's
#     dependencies for "libangle" therefore never matches -- the real
#     dependency chain is qemu -> libvirglrenderer -> libepoxy -> dlopen(EGL).
#   * libepoxy is built with -Degl=yes, so it has no build-time EGL dependency.
#     An empty dependency list there is the expected outcome, not a warning.

set -euo pipefail

failures=0

check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1
  then
    echo "  ok: ${description}"
  else
    echo "  FAIL: ${description}" >&2
    failures=$((failures + 1))
  fi
}

contains() {
  # usage: contains <needle> <haystack-command...>
  #
  # Capture-then-compare rather than piping into `grep -q`: under
  # `set -o pipefail`, grep -q exits as soon as the needle matches and the
  # producer can then die of SIGPIPE (exit 141), turning a MATCH into a
  # pipeline failure. Today's producers are small enough to fit a pipe
  # buffer, but capture-first removes the failure class for any future
  # producer that grows verbose.
  local needle=$1
  shift
  local output
  output=$("$@" 2>/dev/null) || return 1
  [[ ${output} == *"${needle}"* ]]
}

# Every keg in the tap is addressed by its fully qualified name.
# `brew --prefix <fq>` already returns the keg's opt directory, so it is used
# directly. The bare `$(brew --prefix)/opt/<short>` form this replaces resolves
# whichever `brew` finds first, which is not guaranteed to be this tap: `brew
# info virglrenderer` warns that the tap formula shadows homebrew/core's of the
# same name, and a core keg of that name would satisfy the short form and
# silently probe the wrong dylib.
qemu_bin="$(brew --prefix milesbuckton/qemu-virgl/qemu-virgl)/bin/qemu-system-aarch64"
epoxy_dylib="$(brew --prefix milesbuckton/qemu-virgl/libepoxy-angle)/lib/libepoxy.0.dylib"
virgl_dylib="$(brew --prefix milesbuckton/qemu-virgl/virglrenderer)/lib/libvirglrenderer.1.dylib"
angle_lib="$(brew --prefix milesbuckton/qemu-virgl/libangle)/lib"

echo "=== QEMU links the GPU stack ==="
check "qemu-system-aarch64 links libepoxy.0.dylib" \
  contains "libepoxy.0.dylib" otool -L "${qemu_bin}"
check "qemu-system-aarch64 links libvirglrenderer.1.dylib" \
  contains "libvirglrenderer.1.dylib" otool -L "${qemu_bin}"

# Deliberate negative assertion, and a hard one: libangle must NOT appear
# here. libepoxy resolves EGL by dlopen() at runtime, so a direct libangle
# link means the build bypassed libepoxy entirely. See the header.
if otool -L "${qemu_bin}" 2>/dev/null | grep -qF "libangle"
then
  echo "  FAIL: qemu links libangle directly (must go through libepoxy's dlopen)" >&2
  failures=$((failures + 1))
else
  echo "  ok: qemu does not link libangle directly (libepoxy dlopens EGL)"
fi

echo "=== libvirglrenderer links libepoxy ==="
check "libvirglrenderer.1.dylib links libepoxy.0.dylib" \
  contains "libepoxy.0.dylib" otool -L "${virgl_dylib}"

echo "=== GPU libraries are present and self-consistent ==="
check "libepoxy.0.dylib exists" test -f "${epoxy_dylib}"
check "libvirglrenderer.1.dylib exists" test -f "${virgl_dylib}"
check "ANGLE's libEGL.dylib exists" test -f "${angle_lib}/libEGL.dylib"
check "ANGLE's libGLESv2.dylib exists" test -f "${angle_lib}/libGLESv2.dylib"
# Every dylib's own install name must be recorded, or dyld cannot load it once
# the bottle has been relocated to a different prefix.
check "libepoxy.0.dylib has a recorded install name" \
  contains "libepoxy.0.dylib" otool -D "${epoxy_dylib}"
check "libvirglrenderer.1.dylib has a recorded install name" \
  contains "libvirglrenderer.1.dylib" otool -D "${virgl_dylib}"

echo "=== QEMU build configuration ==="
if "${qemu_bin}" -display help 2>&1 | grep -qE "cocoa"
then
  echo "  ok: cocoa display backend present"
else
  echo "  FAIL: cocoa display backend missing" >&2
  failures=$((failures + 1))
fi
if "${qemu_bin}" -device help 2>&1 | grep -q "virtio-gpu"
then
  echo "  ok: virtio-gpu devices present"
else
  echo "  FAIL: virtio-gpu devices missing" >&2
  failures=$((failures + 1))
fi

echo "=== Venus (Vulkan) support ==="

# Guards against the QEMU fork losing the Venus device code. Upstream defines
# the property unconditionally (since 9.2), so this alone does NOT prove that
# virglrenderer has Venus -- the capset probe below does.
check "virtio-gpu-gl-pci exposes the venus property" \
  contains "venus=" "${qemu_bin}" -device virtio-gpu-gl-pci,help

# The formula's own test initialises with VIRGL_RENDERER_NO_VIRGL only, so it
# never touches Venus. venus-probe.c initialises the Venus backend explicitly
# and asks for its capset: a build without Venus either fails init (the vkr
# stub returns -1) or reports a zero-size capset.
#
# The probe lives in its own file rather than a heredoc on purpose: brew
# style's shfmt wrapper re-indents line by line and does not skip heredoc
# bodies, so a C `if (...) {` inside one is taken for a shell `if` and every
# line up to the next `then` -- including the EOF terminator -- is shifted.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
virgl_prefix="$(brew --prefix milesbuckton/qemu-virgl/virglrenderer)"
venus_probe_dir="$(mktemp -d)"
trap 'rm -rf "${venus_probe_dir}"' EXIT

# The compile runs outside check() on purpose: check() discards stdout and
# stderr, which for a compiler means a capset-id move or header split would
# fail the job with zero diagnostics. Mirror the probe RUN below (which has
# always run inline for the same reason) and keep the compiler's output.
if cc "${script_dir}/venus-probe.c" \
   -I"${virgl_prefix}/include/virgl" \
   -L"${virgl_prefix}/lib" -Wl,-rpath,"${virgl_prefix}/lib" \
   -lvirglrenderer -o "${venus_probe_dir}/probe"
then
  echo "  ok: Venus probe compiles against libvirglrenderer"
else
  echo "  FAIL: Venus probe compiles against libvirglrenderer (compiler output above)" >&2
  failures=$((failures + 1))
fi

# Run outside check() so the probe's output reaches the log either way.
if venus_out=$("${venus_probe_dir}/probe" 2>&1)
then
  echo "  ok: virglrenderer initialises Venus (${venus_out})"
else
  echo "  FAIL: virglrenderer Venus init/capset (${venus_out:-no output})" >&2
  failures=$((failures + 1))
fi

if [[ "${failures}" -ne 0 ]]
then
  echo "=== ${failures} GPU wiring check(s) FAILED ===" >&2
  exit 1
fi

echo "=== all GPU wiring checks passed ==="
