# 3D accelerated QEMU 11 on macOS

QEMU 11.0.3 with VirGL/ANGLE GPU acceleration, packaged as a Homebrew tap.

This tap ports the virgl renderer patch stack (by [Akihiko Odaki](https://github.com/akihikodaki)) to QEMU **11.0.3**, the same stack that ships in the [startergo tap](https://github.com/startergo/homebrew-qemu-virgl) for QEMU 10.1.2.

## Features

- Hardware-accelerated OpenGL in the guest via `virtio-gpu-gl-pci` + `-display cocoa,gl=es`
- ANGLE GL (OpenGL) backend on Apple Silicon and Intel Macs
- Works without root or kernel extensions (Hypervisor.framework)
- Dynamically changing guest resolution on window resize

## Prerequisites

Full **Xcode** (not just Command Line Tools) is required to build from source:

```sh
sudo xcodebuild -license accept
```

Check with `xcode-select -p` — it must point to a full Xcode path.

## Installation

```sh
brew tap milesbuckton/qemu-virgl
brew install milesbuckton/qemu-virgl/qemu-virgl
```

The formula installs its dependencies automatically:
- `libangle` (ANGLE, OpenGL ES via native CGL backend)
- `libepoxy-angle` (OpenGL dispatch library)
- `virglrenderer` (OpenGL virtualization library)
- `spice-server` (clipboard sharing and guest integration)

> ℹ️ Prebuilt bottles for Apple Silicon (`arm64_tahoe`) and Intel (`tahoe`) on macOS Tahoe (26) are published as GitHub Release assets — Homebrew pours them and skips the source build. From-source builds (full Xcode, 30-60 minutes) only happen if no bottle matches your platform.

## Usage

For the best experience, maximize the QEMU window. Release the mouse with Ctrl-Alt-g.

### Apple Silicon Macs

Create a disk image:

```sh
qemu-img create -f qcow2 hdd.qcow2 64G
```

Verify OpenGL acceleration is wired up:

```sh
sudo qemu-system-aarch64 \
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
sudo qemu-system-aarch64 \
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

### Intel Macs

```sh
sudo qemu-system-x86_64 \
  -M q35 \
  -cpu host \
  -smp 4 \
  -m 8G \
  -bios ./edk2-x86_64-code.fd \
  -drive file=hdd.qcow2,if=virtio,format=qcow2 \
  -netdev vmnet-shared,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio-gpu-gl-pci \
  -display cocoa,gl=es \
  -usb -device usb-tablet \
  -cdrom Fedora-Workstation-Live-x86_64-40-1.2.iso \
  -boot d
```

## Known limitations

- Moving the VM window between Retina and non-Retina displays may render incorrectly (known QEMU cocoa/virtio-gpu issue). Keep the window on one display or restart after moving.
- EFI/GRUB run at a fixed low resolution before the desktop takes over.
- Clipboard sharing requires `spice-vdagent` inside the guest (`sudo dnf install spice-vdagent && sudo systemctl enable --now spice-vdagentd`).

## Troubleshooting

- **`xcode-select -p` points to CommandLineTools** → install full Xcode; the GL/ANGLE build will not work with Command Line Tools alone.
- **libepoxy symlink conflicts** → `brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl`.
- **Build failures** → `brew cleanup && brew uninstall milesbuckton/qemu-virgl/qemu-virgl && brew install -v milesbuckton/qemu-virgl/qemu-virgl`.

## Layout

- `Formula/` — `qemu-virgl.rb` (QEMU 11.0.3) plus supporting formulae `gn`, `libangle`, `libepoxy-angle`, `virglrenderer`.
- `Patches/` — `qemu-11.0.3-virgl.diff` (the 3-way merged QEMU 11 port) and the virglrenderer/libepoxy patches.
