# 3D accelerated QEMU on macOS (VirGL + Venus)

QEMU (latest `master`) with **VirGL/ANGLE** OpenGL acceleration **and** **Venus** Vulkan
pass-through, packaged as a Homebrew tap. Both glue the guest GPU onto the
Apple GPU over Hypervisor.framework — no root, no kernel extensions.



## Features

- Hardware-accelerated **OpenGL** in the guest via `virtio-gpu-gl-pci` + `-display cocoa,gl=es`
- Hardware-accelerated **Vulkan** in the guest via **Venus** (`-device virtio-gpu-gl-pci,venus=true,blob=on,hostmem=512M`) — requires a patched guest Mesa ICD (see Venus section below)
- ANGLE GL (OpenGL) + MoltenVK (Vulkan) backends
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

The formula installs its dependencies automatically:
- `libangle` (ANGLE, OpenGL ES via native CGL backend)
- `virglrenderer` (virtual GL + **Venus** Vulkan renderer, built from `miles.buckton` fork)
- `spice-server` (clipboard sharing and guest integration)

> ℹ️ `virglrenderer` is built from `miles.buckton/virglrenderer` fork which includes
> the macOS ObjC/Metal venus host path (`-Dvenus=true -Dvulkan-dload=false`), so
> the guest's Vulkan calls reach the Apple GPU through MoltenVK while the GL path
> stays on ANGLE. No prebuilt bottles are currently published — formulas build from
> source (full Xcode, ~1 minute for virglrenderer, longer for QEMU itself).

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

Install and run a Linux system:

```sh
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
  -drive "if=pflash,format=raw,file=./edk2-aarch64-code.fd,readonly=on" \
  -drive "if=pflash,format=raw,file=./edk2-arm-vars.fd,discard=on" \
  -drive "if=virtio,format=qcow2,file=./hdd.qcow2,discard=on" \
  -chardev qemu-vdagent,id=spice,name=vdagent,clipboard=on \
  -device virtio-serial-pci \
  -device virtserialport,chardev=spice,name=com.redhat.spice.0 \
  -cdrom Fedora-Silverblue-ostree-aarch64-41-1.4.iso \
  -boot d
```

Inside the guest, verify the renderer:

```sh
sudo dnf install mesa-demos glx-utils
glxinfo | grep -E "OpenGL renderer|direct rendering"
```

Expected output shows `direct rendering: Yes` and a renderer string starting with `virgl (ANGLE ...)`.

To verify **Vulkan** (Venus) is wired to the host:

```sh
sudo dnf install vulkan-tools
vulkaninfo | grep -E "deviceName|driverName"
```

Expected output reports the **host GPU** (e.g. `Apple M*` / MoltenVK), not a software
fallback — that is the venus renderer passing Vulkan through to the host over
`virtio-gpu`. The guest ICD must be the patched version (HISTORY #45 in
linux-desktop-vm); the stock distro ICD will return `VK_ERROR_OUT_OF_HOST_MEMORY`
due to the 16 KB vs 4 KB page-size mismatch.

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
  automatically by the `linux-desktop-vm` templates (Ubuntu and Gentoo) via an
  in-guest Mesa rebuild with the 16 KB alignment patch (`vn_renderer_virtgpu.c`
  + `vn_renderer_util.c`). The patch is filed as MR against Mesa `main`. VirGL
  (OpenGL) is unaffected.
- Moving the VM window between Retina and non-Retina displays may render incorrectly (known QEMU cocoa/virtio-gpu issue). Keep the window on one display or restart after moving.
- EFI/GRUB run at a fixed low resolution before the desktop takes over.
- Clipboard sharing requires `spice-vdagent` inside the guest (`sudo dnf install spice-vdagent && sudo systemctl enable --now spice-vdagentd`).

## Troubleshooting

- **`xcode-select -p` points to CommandLineTools** → install full Xcode; the GL/ANGLE build will not work with Command Line Tools alone.
- **libepoxy symlink conflicts** → `brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl`.
- **Build failures** → `brew cleanup && brew uninstall milesbuckton/qemu-virgl/qemu-virgl && brew install -v milesbuckton/qemu-virgl/qemu-virgl`.

## Layout

- `Formula/` — `qemu-virgl.rb` (QEMU from `milesbuckton/qemu` fork) plus supporting formulae `libangle` (latest `main`), `libepoxy-angle` (latest `master`), `virglrenderer` (from `miles.buckton/virglrenderer` fork), and `gn` (latest `main`, build-only tool dependency of libangle). The QEMU and virglrenderer formulae track their respective forks rather than upstream.
