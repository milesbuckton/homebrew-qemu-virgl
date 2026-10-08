# 3D accelerated QEMU on macOS (VirGL + Venus)

[![Homebrew style](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/style.yml/badge.svg)](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/style.yml)

QEMU (tracking `master` of the `milesbuckton/qemu` fork) with
**VirGL/ANGLE OpenGL** acceleration and **Venus Vulkan** pass-through,
packaged as a Homebrew tap. Both glue the guest GPU onto the Apple GPU over
Hypervisor.framework — no root, no kernel extensions.

## Features

- Hardware-accelerated **OpenGL** in the guest via `virtio-gpu-gl-pci` + `-display cocoa,gl=es`
- Hardware-accelerated **Vulkan** in the guest via **Venus** (`-device virtio-gpu-gl-pci,venus=on,blob=on,hostmem=512M`) — requires a patched guest Mesa ICD (see [Known limitations](#known-limitations))
- ANGLE for GL/GLES (on Apple, ANGLE's own Metal backend), plus Venus for Vulkan
- Works without root or kernel extensions (Hypervisor.framework)
- Dynamically changing guest resolution on window resize

## Prerequisites

Full **Xcode** (not just Command Line Tools) is required to build from source:

```sh
sudo xcodebuild -license accept
```

Check with `xcode-select -p` — it must point to a full Xcode path.

Homebrew handles Python automatically, but `python@3.14` is used as a build dependency by all formulae. If you see Python-related build errors, ensure Homebrew's Python is linked: `brew link --overwrite python@3.14`.

## Installation

```sh
brew tap milesbuckton/qemu-virgl
brew install milesbuckton/qemu-virgl/qemu-virgl
```

Bottles are published for the `arm64_golden_gate` bottle tag (Apple Silicon,
macOS 27). On any other configuration Homebrew compiles from source instead —
which is still supported, but needs the full Xcode described under
[Prerequisites](#prerequisites).

The formula is **not linked** into your `PATH` by default (it intentionally
shadows the core `qemu`/`libepoxy` kegs). `libangle` and `libepoxy-angle` are
`keg_only` for the same reason — they replace libraries that macOS or core
formulae provide, so they are never linked into `$(brew --prefix)`. Either
invoke QEMU via its opt path:

```sh
"$(brew --prefix)/opt/qemu-virgl/bin/qemu-system-aarch64" --version
```

or link it into your `PATH` (shadowing a core-installed `qemu`, if present):

```sh
brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl
```

The usage examples below assume the link step was performed; otherwise prefix
the commands with the opt path above.

The formula installs its dependencies automatically:
- `libangle` (ANGLE, OpenGL ES via ANGLE's own Metal backend — not CGL)
- `virglrenderer` (virtual GL + **Venus Vulkan** renderer, tracking `main` of the `miles.buckton` fork; pulls `spice-protocol` headers for the venus host path)

> ℹ️ `virglrenderer` is built from `miles.buckton/virglrenderer` fork which includes
> the macOS ObjC/Metal venus host path (`-Dvenus=true`; libvulkan is dlopened at
> runtime per the fork's default `vulkan-dload=true`, with `vulkan-loader`
> installed as the dlopen provider), so the guest's Vulkan calls reach the Apple
> GPU through MoltenVK while the GL path stays on ANGLE. Pre-built bottles for
> Apple Silicon are published to a permanent release tagged
> [`latest`](https://github.com/milesbuckton/homebrew-qemu-virgl/releases/tag/latest);
> the `publish.yml` workflow is manual (`workflow_dispatch` only), builds and
> smoke-tests them on macOS, then republishes the assets in place. The tag never
> changes — only the checksums differ between runs.

## Usage

For the best experience, maximize the QEMU window. Release the mouse with Ctrl-Alt-g.

### Apple Silicon Macs

Create a disk image:

```sh
qemu-img create -f qcow2 hdd.qcow2 64G
```

Verify OpenGL acceleration is wired up:

```sh
qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu cortex-a72 -smp 2 -m 1G \
  -device virtio-gpu-gl-pci \
  -display cocoa,gl=es \
  -nodefaults \
  -device VGA,vgamem_mb=64 \
  -monitor stdio
```

At the `(qemu)` prompt, run `info qtree` and look for `dev: virtio-gpu-gl-pci` and `dev: virtio-gpu-gl-device`. Type `quit` to exit.

Install and run a Linux system. Download a guest ISO first — the example below
uses Fedora Silverblue for aarch64 from
[getfedora.org](https://fedoraproject.org/workstation/download/) (Silverblue →
aarch64) — then copy the EDK2 VARS template out of the keg into your working
directory, because the code image is read-only while the VARS image is written
to on every boot:

```sh
QEMU_SHARE="$(brew --prefix)/opt/qemu-virgl/share/qemu"
cp "$QEMU_SHARE/edk2-aarch64-vars.fd" ./edk2-aarch64-vars.fd
ISO=Fedora-Silverblue-ostree-aarch64-44.iso   # substitute your ISO filename

qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu cortex-a72 -smp 2 -m 4G \
  -device intel-hda -device hda-output \
  -device qemu-xhci \
  -device virtio-gpu-gl-pci,xres=1920,yres=1080 \
  -device usb-kbd \
  -device usb-tablet \
  -device virtio-net-pci,netdev=net \
  -display cocoa,gl=es \
  -netdev vmnet-shared,id=net \
  -drive "if=pflash,format=raw,file=$QEMU_SHARE/edk2-aarch64-code.fd,readonly=on" \
  -drive "if=pflash,format=raw,file=./edk2-aarch64-vars.fd,discard=on" \
  -drive "if=virtio,format=qcow2,file=./hdd.qcow2,discard=on" \
  -chardev qemu-vdagent,id=spice,name=vdagent,clipboard=on \
  -device virtio-serial-pci \
  -device virtserialport,chardev=spice,name=com.redhat.spice.0 \
  -cdrom "$ISO" \
  -boot d
```

Both EDK2 images ship with the formula — there is nothing extra to download.

Inside the guest, verify the renderer:

```sh
sudo dnf install mesa-demos glx-utils
glxinfo | grep -E "OpenGL renderer|direct rendering"
```

Expected output shows `direct rendering: Yes` and a renderer string starting with `virgl (ANGLE ...)`.

To verify **Vulkan (Venus)** is wired to the host:

```sh
sudo dnf install vulkan-tools
vulkaninfo | grep -E "deviceName|driverName"
```

Expected output reports the **host GPU** (e.g. `Apple M*` / MoltenVK), not a software
fallback — that is the venus renderer passing Vulkan through to the host over
`virtio-gpu`. The guest ICD must be the patched version, applied automatically
by the [`linux-desktop-vm`](https://github.com/milesbuckton/linux-desktop-vm)
templates (the stock distro ICD returns `VK_ERROR_OUT_OF_HOST_MEMORY` due to the
16 KB vs 4 KB page-size mismatch).

## Known limitations

- **Apple Silicon Venus requires a patched guest Mesa ICD.** The Venus command ring
  is a `VIRTGPU_BLOB_MEM_HOST3D` + `USE_MAPPABLE` blob that the host maps with
  `mmap(..., MAP_FIXED|MAP_SHARED, fd, 0)`. On Apple Silicon the host page size is
  **16 KB** while the aarch64 guest uses **4 KB** pages, and the guest kernel packs
  hostmem blobs contiguously at guest-page granularity (`drm_mm_insert_node` with
  the requested size, no larger alignment). The ring blob therefore lands at a
  host address that is 4 KB-aligned but **not 16 KB-aligned**, so the host's
  `MAP_FIXED` mmap fails with `EINVAL`, the guest cannot mmap the ring
  (`mmap failed ... Invalid argument`), the renderer-instance-version handshake
  never completes, and `vkCreateInstance` returns `VK_ERROR_OUT_OF_HOST_MEMORY`.
  **Fix**: the guest Mesa ICD must align blob allocations to 16 KB. This is done
  automatically by the [`linux-desktop-vm` templates](https://github.com/milesbuckton/linux-desktop-vm/tree/main/templates)
  (Ubuntu and Gentoo) via an in-guest Mesa rebuild with
  [`docs/venus-mesa-16kb.patch`](https://github.com/milesbuckton/linux-desktop-vm/blob/main/docs/venus-mesa-16kb.patch)
  (`vn_renderer_virtgpu.c` + `vn_renderer_util.c`). The patch is filed as MR
  against Mesa `main`. VirGL (OpenGL) is unaffected.
- Moving the VM window between Retina and non-Retina displays may render incorrectly (known QEMU cocoa/virtio-gpu issue). Keep the window on one display or restart after moving.
- EFI/GRUB run at a fixed low resolution before the desktop takes over.
- Clipboard sharing requires macOS-native tools (e.g. universal clipboard / third-party syncers); the QEMU build does not link SPICE display. The `qemu-vdagent` chardev is still passed to the guest for compatibility, but no host-side SPICE server is attached.

## Troubleshooting

- **`xcode-select -p` points to CommandLineTools** → install full Xcode; the GL/ANGLE build will not work with Command Line Tools alone.
- **libepoxy symlink conflicts** → re-run the optional link step from Installation: `brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl`.
- **Build failures** → `brew cleanup && brew uninstall milesbuckton/qemu-virgl/qemu-virgl && brew install -v milesbuckton/qemu-virgl/qemu-virgl`.

## Layout

- `Formula/` — `qemu-virgl.rb` (tracks `master` of the `milesbuckton/qemu` fork) plus supporting formulae `libangle` (latest `main`), `libepoxy-angle` (latest `master`), `virglrenderer` (tracks `main` of the `miles.buckton/virglrenderer` fork), and `gn` (latest `main`, build-only tool dependency of libangle). The QEMU and virglrenderer formulae track their respective forks rather than upstream.
- `lib/` — helpers shared by the formulae: `HermeticVenv` (builds a venv whose `pip install` never reaches PyPI) and `NoSubmoduleGitDownloadStrategy`. Loaded with `require_relative`, so nothing leaks into the global Ruby namespace at Homebrew load time.
- `script/verify-gpu-wiring.sh` — hard assertions that QEMU actually links the GPU stack (used by both the `publish` and `verify` jobs). It fails the job when the wiring is wrong, unlike the warning-only probe it replaced.
- `.github/workflows/publish.yml` — the bottle pipeline: builds and smoke-tests bottles for `arm64_golden_gate`, prunes the previous `latest` release, republishes the assets, and commits the updated bottle blocks back to `main`. **Manual only** (`workflow_dispatch`), roughly 30 minutes.
- `.github/workflows/style.yml` — runs `brew style` and `brew audit --strict` on push, on pull requests, on a weekly schedule, and on manual dispatch. Note that `publish.yml` amends `main` and force-pushes it with the default `GITHUB_TOKEN`, which GitHub's `push` trigger ignores, so the resulting bottle-block commit is not styled automatically; dispatch this workflow manually to lint it.
- `.github/workflows/close-prs.yml` — automatically closes pull requests from non-owners; see [Contributing](#contributing).
- `docs/CONTRIBUTING.md` — the contribution policy, in full.
- `AGENTS.md` — conventions for AI coding agents working in this repo (bottle naming, release flow, runner updates).
- `.gitignore`, `LICENSE` (MIT).

## Releasing

Publishing bottles is a manual step, triggered by a maintainer:

```sh
gh workflow run publish.yml
```

Roughly 30 minutes later, `gh release view latest --json assets` should list a
`.bottle.tar.gz` for each of `qemu-virgl`, `virglrenderer`, `libangle`, and
`libepoxy-angle` on `arm64_golden_gate`. The workflow also pushes the refreshed
bottle blocks back to `main`, so pull before starting any new work.

## Contributing

This repository is a **personal artifact**: external contributions — pull
requests, issues, discussions — are **not accepted**. Issues are disabled at
the repository level, and pull requests opened by non-owners are closed
automatically by `close-prs.yml`.

The project is MIT-licensed, so feel free to fork it and adapt it freely. The
full policy and its reasoning live in
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
