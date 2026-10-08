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
  local needle=$1
  shift
  "$@" 2>/dev/null | grep -qF -- "${needle}"
}

qemu_bin="$(brew --prefix milesbuckton/qemu-virgl/qemu-virgl)/bin/qemu-system-aarch64"
epoxy_dylib="$(brew --prefix)/opt/libepoxy-angle/lib/libepoxy.0.dylib"
virgl_dylib="$(brew --prefix)/opt/virglrenderer/lib/libvirglrenderer.1.dylib"
angle_lib="$(brew --prefix)/opt/libangle/lib"

echo "=== QEMU links the GPU stack ==="
check "qemu-system-aarch64 links libepoxy.0.dylib" \
  contains "libepoxy.0.dylib" otool -L "${qemu_bin}"
check "qemu-system-aarch64 links libvirglrenderer.1.dylib" \
  contains "libvirglrenderer.1.dylib" otool -L "${qemu_bin}"

# Deliberate negative assertion: libangle must NOT appear here. See the header.
if otool -L "${qemu_bin}" 2>/dev/null | grep -qF "libangle"
then
  echo "  note: qemu links libangle directly (unexpected, but not fatal)" >&2
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

if [[ "${failures}" -ne 0 ]]
then
  echo "=== ${failures} GPU wiring check(s) FAILED ===" >&2
  exit 1
fi

echo "=== all GPU wiring checks passed ==="
