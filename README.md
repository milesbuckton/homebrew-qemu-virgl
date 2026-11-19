# 3D accelerated QEMU on macOS (VirGL + Venus)

[![Homebrew style](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/style.yml/badge.svg)](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/style.yml)
[![Publish](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/publish.yml/badge.svg)](https://github.com/milesbuckton/homebrew-qemu-virgl/actions/workflows/publish.yml)

QEMU with
**VirGL/ANGLE OpenGL** acceleration and **Venus Vulkan** pass-through,
packaged as a Homebrew tap. Both glue the guest GPU onto the Apple GPU over
Hypervisor.framework — no root, no kernel extensions.

## Features

- Hardware-accelerated **OpenGL** in the guest via `virtio-gpu-gl-pci` + `-display cocoa,gl=es`
- Hardware-accelerated **Vulkan** in the guest via **Venus** (`-device virtio-gpu-gl-pci,venus=on,blob=on,hostmem=512M`) — requires a guest Mesa and kernel that honour the host's blob alignment (see [Known limitations](#known-limitations))
- ANGLE for GL/GLES (on Apple, ANGLE's own Metal backend), plus Venus for Vulkan
- Choice of host Vulkan driver behind Venus: **MoltenVK** (default) or **KosmicKrisp** (Mesa's Vulkan-on-Metal driver, installed automatically on macOS 26+; see [Host Vulkan driver](#host-vulkan-driver-moltenvk-or-kosmickrisp))
- Works without root or kernel extensions (Hypervisor.framework)
- Dynamically changing guest resolution on window resize

## Prerequisites

Full **Xcode** (not just Command Line Tools) is required to build from source:

```sh
sudo xcodebuild -license accept
```

Check with `xcode-select -p` — it must point to a full Xcode path.

Homebrew handles Python automatically, and the build's venv machinery
(`lib/hermetic_venv.rb`) resolves Homebrew's `python@3.15` via its opt path —
no linked Python is required. If you see Python-related build errors anyway,
please report them rather than force-linking: `brew link --overwrite
python@3.15` can fight other Python consumers on your system.

## Installation

```sh
brew tap milesbuckton/qemu-virgl
brew install milesbuckton/qemu-virgl/qemu-virgl
```

Bottles are published for the `arm64_golden_gate` bottle tag (Apple Silicon,
macOS 27). On any other configuration Homebrew compiles from source instead —
which is still supported, but needs the full Xcode described under
[Prerequisites](#prerequisites).

Every formula except `gn` is `keg_only`, so none is linked into your `PATH`
by default: `qemu-virgl`, `virglrenderer` and `libepoxy-angle` shadow the
core `qemu`/`virglrenderer`/`libepoxy` kegs, ANGLE's EGL/GLES/KHR headers
would shadow any other GL provider on the default include path, and
`kosmickrisp` ships the same ICD manifest name as core's `mesa`. Either
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
- `libepoxy-angle` (libepoxy built against ANGLE's EGL/GLES)
- `virglrenderer` (virtual GL + **Venus Vulkan** renderer, tracking `main` of the `miles.buckton` fork; pulls `spice-protocol` headers for the venus host path)
- `molten-vk` and `vulkan-loader` (via `virglrenderer`; the default host Vulkan driver and its loader)

> ℹ️ `virglrenderer` is built from `miles.buckton/virglrenderer` fork which includes
> the macOS ObjC/Metal venus host path (`-Dvenus=true`; libvulkan is dlopened at
> runtime per the fork's default `vulkan-dload=true`, with `vulkan-loader` and
> `molten-vk` installed so Vulkan calls reach Apple Metal via MoltenVK), while the
> GL path stays on ANGLE. Pre-built bottles for
> Apple Silicon are published to a permanent release tagged
> [`latest`](https://github.com/milesbuckton/homebrew-qemu-virgl/releases/tag/latest);
> the `publish.yml` workflow is manual (`workflow_dispatch` only), builds and
> smoke-tests them on macOS, then republishes the assets in place and, once the poured bottles pass
> verification, recreates the release object. The tag's name never changes,
> but each run moves it onto the rewritten `main` (recreating it if missing);
> only the checksums differ between runs.
>
> `qemu-virgl` tracks `master` of the
> [`milesbuckton/qemu`](https://gitlab.com/milesbuckton/qemu) fork (QEMU
> 11.1.90): upstream plus one commit that adds ANGLE/EGL GL scanout to the
> Cocoa display (`gl=es`/`gl=on` accepted, `gl=core` rejected), makes HVF skip
> memory sections that are not host-page aligned, rejects unaligned blob maps
> under HVF, adds the `blob-alignment` virtio-gpu property (see
> [Known limitations](#known-limitations)), and adds audio capture to the
> CoreAudio backend, so guests get a microphone from the Mac's default input
> device (macOS asks the app that launches QEMU for microphone access).

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
  -cpu host -smp 2 -m 1G \
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
  -cpu host -smp 2 -m 4G \
  -device intel-hda -device hda-output \
  -device qemu-xhci \
  -device virtio-gpu-gl-pci,xres=1920,yres=1080,venus=on,blob=on,hostmem=512M \
  -device usb-kbd \
  -device usb-tablet \
  -device virtio-net-pci,netdev=net \
  -display cocoa,gl=es \
  -netdev user,id=net \
  -drive "if=pflash,format=raw,file=$QEMU_SHARE/edk2-aarch64-code.fd,readonly=on" \
  -drive "if=pflash,format=raw,file=./edk2-aarch64-vars.fd,discard=on" \
  -drive "if=virtio,format=qcow2,file=./hdd.qcow2,discard=on" \
  -cdrom "$ISO" \
  -boot d
```

`venus=on,blob=on,hostmem=512M` enables Vulkan pass-through (Venus). Drop those
three options for an OpenGL-only (VirGL) guest, or when the guest does not yet
have the blob-alignment support described under [Known limitations](#known-limitations).

Both EDK2 images ship with the formula — there is nothing extra to download.

`-netdev user` (QEMU's built-in NAT) works without root. For a bridged-style
`vmnet-shared` network, swap in `-netdev vmnet-shared,id=net` and run QEMU with
`sudo` — the binary does not carry Apple's `com.apple.vm.networking`
entitlement, so vmnet otherwise fails with *"cannot create vmnet interface:
general failure (possibly not enough privileges)"*.

**Windows 11 ARM64 guests** use the same QEMU, but 3D needs a separate
test-signed guest driver (`viogpu3d`); the
[`windows-desktop-vm`](https://github.com/milesbuckton/windows-desktop-vm)
builder wires both up with `--gpu 3d` (host Vulkan pinned to MoltenVK).

Inside the guest, verify the renderer:

```sh
sudo rpm-ostree install glx-utils && sudo systemctl reboot
glxinfo | grep -E "OpenGL renderer|direct rendering"
```

Expected output shows `direct rendering: Yes` and a renderer string starting with `virgl (ANGLE ...)`.

To verify **Vulkan (Venus)** is wired to the host:

```sh
sudo rpm-ostree install vulkan-tools && sudo systemctl reboot
vulkaninfo | grep -E "deviceName|driverName"
```

Expected output lists the **Venus** device first, reporting the **host GPU**
(e.g. `Apple M*` / MoltenVK); a software `llvmpipe` device may also be listed
after it. That is the venus renderer passing Vulkan through to the host over
`virtio-gpu`. The guest Mesa and kernel must honour the host's blob alignment
(see [Known limitations](#known-limitations)); the
[`linux-desktop-vm`](https://github.com/milesbuckton/linux-desktop-vm)
templates handle this automatically.

## Host Vulkan driver (MoltenVK or KosmicKrisp)

Venus hands the guest's Vulkan calls to a Vulkan driver on the host. macOS has
none of its own, so the tap supports two that sit on Metal:

| | MoltenVK (default) | KosmicKrisp (opt-in) |
|---|---|---|
| What | Khronos translation layer, Vulkan → Metal | Mesa Vulkan driver (LunarG), built on Metal 4 |
| Conformance | Vulkan 1.4 *portability subset* | Vulkan 1.3 conformant, no portability subset |
| Host | any supported macOS | macOS 26 or later |
| Maturity | years of production use | new; fewer extensions, moving fast |
| Install | pulled in by `virglrenderer` | pulled in by `virglrenderer` on macOS 26+ (bottle on `arm64_golden_gate`; otherwise a source build that needs LLVM); not installed on older macOS |

MoltenVK stays the default because it is the tested path. Try KosmicKrisp when
a guest app hits a portability-subset gap. The `kosmickrisp` formula builds
only Mesa's KosmicKrisp Vulkan driver from the `miles.buckton/mesa` fork's
`main` branch, offline like the rest of the tap, and is keg-only, so it never
lands on the loader's default search path. Select it per process:

```sh
export VK_DRIVER_FILES="$(echo "$(brew --prefix milesbuckton/qemu-virgl/kosmickrisp)"/share/vulkan/icd.d/kosmickrisp_mesa_icd*.json)"
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"   # for older Vulkan loaders
```

[`linux-desktop-vm`](https://github.com/milesbuckton/linux-desktop-vm) and
[`windows-desktop-vm`](https://github.com/milesbuckton/windows-desktop-vm) do
this for you with `--host-vulkan-driver moltenvk|kosmickrisp` (default
`moltenvk`).
`script/verify-gpu-wiring.sh` runs its Venus probe on MoltenVK, and on
KosmicKrisp too when it is installed (always on macOS 26+). CI installs `kosmickrisp` in both the
`publish` job (from source) and the `verify` job (poured from the published
bottle), so the KosmicKrisp probe runs on every publish.

## Known limitations

- **Apple Silicon Venus needs a blob-alignment-aware guest.** The host page
  size is **16 KB** while aarch64 guests use **4 KB** pages, so a guest that
  packs hostmem blobs at 4 KB granularity asks the host to map blobs that are
  not host-page aligned. The QEMU fork never uses `MAP_FIXED` for blobs on
  macOS (it maps them via `virgl_renderer_resource_map`), rejects unaligned
  blob maps under HVF (`-EOPNOTSUPP`, reported to the guest as
  `VIRTIO_GPU_RESP_ERR_UNSPEC`), and advertises the host page size through
  `VIRTIO_GPU_F_BLOB_ALIGNMENT` (`-device virtio-gpu-gl-pci,blob-alignment=on`,
  the default; off for `virt-11.1` and older machine types). The guest must
  honour it:
  - **Mesa**: *"venus: honor the virtio-gpu blob alignment"*
    ([MR 44783](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44783)),
    in Mesa 26.3.0 and backported to 26.2.4+.
  - **Kernel**: must report `VIRTGPU_PARAM_BLOB_ALIGNMENT` (Linux 7.2+).
  - On older kernels, the
    [`miles.buckton/mesa`](https://gitlab.freedesktop.org/miles.buckton/mesa/-/commits/main)
    fork also accepts a `VN_BLOB_ALIGNMENT=16384` override.

  Without these, `vkCreateInstance` returns `VK_ERROR_OUT_OF_HOST_MEMORY`. The
  [`linux-desktop-vm` templates](https://github.com/milesbuckton/linux-desktop-vm/tree/main/templates)
  set this up automatically. VirGL (OpenGL) is unaffected.
- Moving the VM window between Retina and non-Retina displays may render
  incorrectly (known QEMU cocoa/virtio-gpu issue). Keep the window on one
  display or restart after moving.
- EFI/GRUB run at a fixed low resolution before the desktop takes over.
- No host↔guest clipboard sharing: this build has neither SPICE nor the
  `qemu-vdagent` chardev (`-chardev qemu-vdagent` fails with *"'qemu-vdagent' is
  not a valid char driver name"*). Use RDP/SSH or a network clipboard syncer.

## Troubleshooting

- **`xcode-select -p` points to CommandLineTools** → install full Xcode; the GL/ANGLE build will not work with Command Line Tools alone.
- **libepoxy symlink conflicts** → re-run the optional link step from Installation: `brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl`.
- **Build failures** → `brew cleanup && brew uninstall milesbuckton/qemu-virgl/qemu-virgl && brew install -v milesbuckton/qemu-virgl/qemu-virgl`.

## Layout

- `Formula/` — `qemu-virgl.rb` (tracks `master` of the `milesbuckton/qemu`
  fork) plus supporting formulae `libangle` (latest `main`), `libepoxy-angle`
  (latest `master`), `virglrenderer` (tracks `main` of the
  `miles.buckton/virglrenderer` fork), and `gn` (latest `main`, build-only tool
  dependency of libangle). The QEMU and virglrenderer formulae track their
  respective forks rather than upstream. `kosmickrisp` (tracks `main` of the
  `miles.buckton/mesa` fork) is optional; it is bottled like the others, and
  builds from source (LLVM-heavy) only where no bottle applies.
- `lib/` — helpers shared by the formulae: `HermeticVenv` (builds a venv whose
  `pip install` never reaches PyPI), `WrapGuard` (asserts a staged meson
  subproject matches the revision its wrap file pins), `DepsGuard` (asserts the
  Chromium trees ANGLE's build stages still match the revisions ANGLE's own
  `DEPS` file pins), `StagedTreeGuard` (asserts every source ANGLE's build
  graph names is actually on disk, so a newly-added upstream dependency fails
  the build by name instead of inside ninja), and
  `NoSubmoduleGitDownloadStrategy`. Loaded with `require_relative`; each file
  defines a single top-level constant.
- `script/verify-gpu-wiring.sh` — hard assertions that QEMU actually links the
  GPU stack and that virglrenderer can initialise Venus and report its capset
  on every installed host Vulkan driver (MoltenVK always, KosmicKrisp when
  installed, i.e. on macOS 26+)
  (used by both the `publish` and `verify` jobs). It fails the job when the
  wiring is wrong, unlike the warning-only probe it replaced. Its Venus probe
  lives in `script/venus-probe.c` — a separate file, because shfmt (via
  `brew style`) re-indents heredoc bodies and would mangle the C.
- `script/audit.sh` — runs `brew audit --strict` over every formula and fails on
  every problem except the one upstream rule that contradicts this tap's design
  ("Git should specify a full commit hash in `revision:`.", which upstream
  added for moving sources in commit `85ffa721b0`). Every other problem still
  fails the job. If the running Homebrew has the rule but it no longer fires
  as expected (changed) or has been dropped (removed), the script fails, so
  the exemption cannot rot unnoticed; on a Homebrew that predates the rule it
  only warns. See AGENTS.md, "The one audit rule this tap does not satisfy".
- `script/update-angle-deps.rb` — fetches ANGLE's `DEPS` and rewrites the
  `libangle` resource revisions to match. `publish.yml` runs it before
  building, and the updated pins are committed with the bottle blocks.
- `.github/workflows/publish.yml` — the bottle pipeline: builds bottles for
  `arm64_golden_gate` (`libangle`, `libepoxy-angle`, `virglrenderer`,
  `qemu-virgl`, `kosmickrisp`) and runs `brew test` on the built formulae,
  updates the
  fixed `latest` release in place (uploading the fresh assets with
  `--clobber`; the release is never deleted first), squashes the updated
  bottle blocks into `main`'s single root commit and force-pushes `main`
  (`--force-with-lease`), and force-moves the `latest` tag onto it. The
  `verify` job pours the bottles (including `kosmickrisp`, so the wiring
  check probes Venus on it) and boots QEMU headless
  (`virtio-gpu-gl-pci`, `-display egl-headless,gl=es`); only then does
  `recreate` recreate the release under the same tag, after checking there
  are exactly five assets matching `main`'s bottle blocks. A final `style`
  job dispatches `style.yml` on `main`, waits for it and posts the result as
  a commit status. **Manual only** (`workflow_dispatch`), roughly 45 minutes.
- `.github/workflows/style.yml` — runs `brew style` and `brew audit --strict`
  (via `script/audit.sh`) on push, on pull requests, and on manual dispatch
  (never scheduled). `publish.yml`'s bottle-block push uses the default
  `GITHUB_TOKEN`, which GitHub's `push` trigger ignores, so `publish.yml`
  dispatches this workflow itself (see above).
- `.github/workflows/close-prs.yml` — automatically closes pull requests from
  non-owners; see [Contributing](#contributing).
- `docs/CONTRIBUTING.md` — the contribution policy, in full.
- `AGENTS.md` — conventions for AI coding agents working in this repo (bottle
  naming, release flow, runner updates).
- `.gitignore`, `LICENSE` (MIT).

## Releasing

Publishing bottles is a manual step, triggered by a maintainer:

```sh
gh workflow run publish.yml
```

Roughly 45 minutes later, `gh release view latest --json assets` should list a
`.bottle.tar.gz` for each of `qemu-virgl`, `virglrenderer`, `libangle`,
`libepoxy-angle`, and `kosmickrisp` on `arm64_golden_gate`. The workflow also rewrites `main`
(squashing the refreshed bottle blocks into its single commit), so before
starting new work run `git fetch && git reset --hard origin/main` — not
`git pull`, which will report a conflict.

## Contributing

This repository is a **personal artifact**: external contributions — pull
requests, issues, discussions — are **not accepted**. Issues are disabled at
the repository level, and pull requests opened by non-owners are closed
automatically by `close-prs.yml`.

The project is MIT-licensed, so feel free to fork it and adapt it freely. The
full policy and its reasoning live in
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

## Credits

This tap started from
[startergo/homebrew-qemu-virgl](https://github.com/startergo/homebrew-qemu-virgl),
which in turn built on
[knazarov/homebrew-qemu-virgl](https://github.com/knazarov/homebrew-qemu-virgl).
KosmicKrisp support was inspired by
[startergo/homebrew-qemu-virgl-kosmickrisp](https://github.com/startergo/homebrew-qemu-virgl-kosmickrisp).
