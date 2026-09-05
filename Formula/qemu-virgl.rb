class QemuVirgl < Formula
  desc "Emulator for AArch64 with VirGL + Venus GPU acceleration"
  homepage "https://www.qemu.org/"
  url "https://gitlab.com/milesbuckton/qemu.git",
      branch: "master"
  version "master"
  license "GPL-2.0-only"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    rebuild 1
    sha256 arm64_tahoe: "19873f9ad3e752be3dbe46a7f9826cf593b262aac27bd07d99bf8519489d3616"
  end

  depends_on "libtool" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.14" => :build

  depends_on "coreutils"
  depends_on "dtc"
  depends_on "glib"
  depends_on "gnutls"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "libslirp"
  depends_on "libssh"
  depends_on "libusb"
  depends_on "lzo"
  depends_on "milesbuckton/qemu-virgl/libangle"
  depends_on "milesbuckton/qemu-virgl/libepoxy-angle"
  depends_on "milesbuckton/qemu-virgl/virglrenderer"
  depends_on "ncurses"
  depends_on "nettle"
  depends_on "pixman"
  depends_on "snappy"
  depends_on "spice-protocol"
  depends_on "spice-server"
  depends_on "vde"

  resource "tomli" do
    url "https://files.pythonhosted.org/packages/c0/3f/d7af728f075fb08564c5949a9c95e44352e23dee646869fa104a3b2060a3/tomli-2.0.1.tar.gz"
    sha256 "de526c12914f0c550d15924c62d72abc48d6fe7364aa87328337a31007fe8a4f"
  end

  resource "test-image" do
    url "https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.2/official/FD12FLOPPY.zip"
    sha256 "81237c7b42dc0ffc8b32a2f5734e3480a3f9a470c50c14a9c4576a2561a35807"
  end

  def install
    # Setup Python environment
    ENV["LIBTOOL"] = "glibtool"

    python3 = formula_opt_bin("python@3.14")/"python3.14"
    ENV["PYTHON"] = python3

    venv_path = buildpath/"venv"
    system python3, "-m", "venv", venv_path
    venv_python = venv_path/"bin/python"

    resource("tomli").stage do
      system venv_python, "-m", "pip", "install", "."
    end

    ENV["PYTHON"] = venv_python
    ENV.prepend_path "PYTHONPATH", venv_path/"lib/python3.14/site-packages"

    # Set library paths
    angle_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/libangle")
    epoxy_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/libepoxy-angle")
    virgl_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/virglrenderer")
    spice_protocol_prefix = formula_opt_prefix("spice-protocol")
    spice_server_prefix = formula_opt_prefix("spice-server")

    # libepoxy-angle is keg_only, so point pkg-config at its .pc file (qemu's
    # meson uses `dependency('epoxy')` to detect it).
    ENV.prepend_path "PKG_CONFIG_PATH", "#{epoxy_prefix}/lib/pkgconfig"

    # Build configuration
    args = %W[
      --prefix=#{prefix}
      --cc=#{ENV.cc}
      --host-cc=#{ENV.cc}
      --disable-bsd-user
      --disable-guest-agent
      --disable-sdl
      --disable-gtk
      --enable-cocoa
      --enable-opengl
      --enable-virglrenderer
      --enable-curses
      --enable-libssh
      --enable-slirp
      --enable-vde
      --enable-fdt=system
      --enable-trace-backends=log,simple
      --enable-malloc=system
      --extra-cflags=-I#{angle_prefix}/include
      --extra-cflags=-I#{epoxy_prefix}/include
      --extra-cflags=-I#{virgl_prefix}/include
      --extra-cflags=-I#{spice_protocol_prefix}/include/spice-1
      --extra-cflags=-I#{spice_server_prefix}/include/spice-server
      --extra-cflags=-DNCURSES_WIDECHAR=1
      --extra-ldflags=-L#{angle_prefix}/lib
      --extra-ldflags=-L#{epoxy_prefix}/lib
      --extra-ldflags=-L#{virgl_prefix}/lib
      --extra-ldflags=-L#{spice_server_prefix}/lib
      --extra-ldflags=-Wl,-rpath,#{angle_prefix}/lib
      --extra-ldflags=-Wl,-rpath,#{epoxy_prefix}/lib
      --extra-ldflags=-Wl,-rpath,#{virgl_prefix}/lib
      --extra-ldflags=-Wl,-rpath,#{spice_server_prefix}/lib
    ]

    # Add smbd path
    args << "--smbd=#{HOMEBREW_PREFIX}/sbin/samba-dot-org-smbd"

    args << "--target-list=aarch64-softmmu"

    system "./configure", *args
    system "make", "V=1"
    system "make", "install"

    # The custom libraries (libangle, libepoxy-angle, virglrenderer) are built
    # with @rpath install names, and the configure -Wl,-rpath flags above add
    # their lib dirs to the binaries' rpath. So the binaries already resolve
    # them at runtime with no install_name_tool rewriting required.
  end

  def caveats
    <<~EOS
      QEMU has been built with VirGL/ANGLE GPU acceleration and Venus
      (Vulkan via MoltenVK) support.

      To run with OpenGL acceleration, use:
        qemu-system-aarch64 -machine virt,accel=hvf -cpu host -m 4G \\
          -device virtio-gpu-gl-pci -display cocoa,gl=es [other options]

      To enable Venus (Vulkan passthrough to the host GPU), add
      venus=on,blob=on,hostmem=512M to the GPU device, e.g.:
        -device virtio-gpu-gl-pci,venus=on,blob=on,hostmem=512M

      For detailed usage examples, see:
      https://github.com/milesbuckton/homebrew-qemu-virgl
    EOS
  end

  test do
    expected = "QEMU Project"

    # Test basic system emulator
    assert_match expected, shell_output("#{bin}/qemu-system-aarch64 --version")

    # Test disk image tools
    resource("test-image").stage testpath
    assert_match "file format: raw", shell_output("#{bin}/qemu-img info FLOPPY.img")

    # Test that binaries can find libraries (check for missing library errors)
    shell_output("#{bin}/qemu-system-aarch64 -accel help")
  end
end
