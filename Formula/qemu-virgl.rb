require_relative "../lib/hermetic_venv"

class QemuVirgl < Formula
  include HermeticVenv

  desc "Emulator for AArch64 with VirGL + Venus GPU acceleration"
  homepage "https://www.qemu.org/"
  url "https://gitlab.com/milesbuckton/qemu.git",
      branch: "master"
  version "master"
  license "GPL-2.0-only"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    sha256 arm64_golden_gate: "bf8c401cf011a228169d0de6ae8e5a5b1282b21fc997091ccaa1ecc9c6527f83"
  end

  # keg_only: this tap intentionally replaces the standard `qemu` keg. Without
  # this line, `brew install` links qemu-system-aarch64/qemu-img/etc. into
  # $(brew --prefix)/bin for every user who doesn't have core qemu installed —
  # i.e. the common case — contradicting the README, which documents the keg
  # as not linked by default. Invoke via the opt path
  # (`$(brew --prefix)/opt/qemu-virgl/bin`) or link deliberately with
  # `brew link --overwrite --force milesbuckton/qemu-virgl/qemu-virgl`.
  keg_only "it shadows the core qemu formula"

  depends_on "libtool" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.14" => :build

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
  depends_on "pixman"
  depends_on "snappy"
  depends_on "vde"

  resource "tomli" do
    url "https://files.pythonhosted.org/packages/c0/3f/d7af728f075fb08564c5949a9c95e44352e23dee646869fa104a3b2060a3/tomli-2.0.1.tar.gz"
    sha256 "de526c12914f0c550d15924c62d72abc48d6fe7364aa87328337a31007fe8a4f"
  end

  # Build backend for the venv below, pinned and checksummed so `pip install`
  # never has to reach PyPI. `--no-index` makes a missing build requirement a
  # hard error rather than a silent download, so the *transitive* ones are
  # pinned too: wheel needs packaging, and tomli builds with flit_core (its
  # pyproject.toml declares `build-backend = "flit_core.buildapi"`, not
  # setuptools). See HermeticVenv in ../lib/hermetic_venv.rb.
  resource "setuptools" do
    url "https://files.pythonhosted.org/packages/95/9c/c510029fc6ef33a6275cd2c5d3cecd6613dfd6aa401d57c54f1c18852ccf/setuptools-84.0.0-py3-none-any.whl"
    sha256 "51a52592b3b99e102b609654876bd65f19f999935166d1352678931132b0c670"
  end

  resource "wheel" do
    url "https://files.pythonhosted.org/packages/2e/29/69cfbb602cd91690c55d38ba9fe53e6a7e76a6fa647bf38f19c138d25449/wheel-0.48.0-py3-none-any.whl"
    sha256 "3217dcc807155e45db462d7ef2431f5ddda0d7273b700d05a67b271ceb1287ab"
  end

  resource "packaging" do
    url "https://files.pythonhosted.org/packages/63/34/ba1c580383c9eada3711951fef0795c80b829a078d72188184bcab9dd527/packaging-26.3-py3-none-any.whl"
    sha256 "d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c"
  end

  resource "flit-core" do
    url "https://files.pythonhosted.org/packages/38/2a/8ea4bd54734f0fcbb507c28cb6b79d72f528e40498178a01cb35fc5d686f/flit_core-4.1.0-py3-none-any.whl"
    sha256 "17398cdd2c38b24047a5a9c93089ec5c0bf12ec3d1469bbf69c27ed7965299db"
  end

  # NOTE: do not mark this `resource "test-image", :test` — test-only
  # resources were added in Homebrew 7.0.8-31 (ef89d716f3), and on anything
  # older the second argument is treated as a class, so merely LOADING this
  # formula raises "undefined method 'new' for an instance of Symbol".
  resource "test-image" do
    url "https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.2/official/FD12FLOPPY.zip"
    sha256 "81237c7b42dc0ffc8b32a2f5734e3480a3f9a470c50c14a9c4576a2561a35807"
  end

  # ui/keycodemapdb is a required meson subproject for --target-list
  # aarch64-softmmu (ui/meson.build:21), and QEMU ships it as a [wrap-git]
  # that meson would clone from gitlab.com at configure time. Stage the pinned
  # tarball into subprojects/ instead: meson prefers an existing subproject
  # directory over the wrap, so the fetch never happens. The directory must be
  # named exactly "keycodemapdb" — the wrap has no `directory` field, so meson
  # derives the name from the project.
  resource "keycodemapdb" do
    url "https://gitlab.com/qemu-project/keycodemapdb/-/archive/f5772a62ec52591ff6870b7e8ef32482371f22c6/keycodemapdb-f5772a62ec52591ff6870b7e8ef32482371f22c6.tar.gz"
    sha256 "d014b53382dbb17b8196ad12f50de7f20d0ef1b9f7d54b0be51a6cbb14209195"
  end

  # Nothing fetches at build time: the venv is hermetic (pip runs --no-index
  # against the local wheelhouse), --disable-download below keeps QEMU's
  # configure from fetching mkvenv packages or meson subprojects, and
  # --disable-tests keeps the two test-only subproject wraps out of the build.
  # The one required subproject is staged from the keycodemapdb resource. Make
  # that offline invariant a hard guarantee.
  deny_network_access!

  def install
    # Setup Python environment
    ENV["LIBTOOL"] = "glibtool"

    venv_path = buildpath/"venv"
    venv_python = hermetic_venv(venv_path, %w[setuptools wheel packaging flit-core])

    hermetic_pip_install(venv_python, "tomli")

    ENV["PYTHON"] = venv_python
    ENV.prepend_path "PYTHONPATH", venv_site_packages(venv_python)

    # Set library paths
    angle_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/libangle")
    epoxy_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/libepoxy-angle")
    virgl_prefix = formula_opt_prefix("milesbuckton/qemu-virgl/virglrenderer")

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
      --extra-cflags=-DNCURSES_WIDECHAR=1
      --extra-ldflags=-L#{angle_prefix}/lib
      --extra-ldflags=-L#{epoxy_prefix}/lib
      --extra-ldflags=-L#{virgl_prefix}/lib
    ]

    # `-Wl,-rpath,` cannot live inside the %W array above: RuboCop's
    # Lint/PercentStringArray flags any element whose literal text ends with a
    # comma, and the correction would strip it out of the flag.
    [angle_prefix, epoxy_prefix, virgl_prefix].each do |lib_prefix|
      args << "--extra-ldflags=-Wl,-rpath,#{lib_prefix}/lib"
    end

    # QEMU's configure is a shell script that drives meson, and it translates
    # --disable-download into meson's --wrap-mode=nodownload while dropping its
    # mkvenv --online flag, so no subproject and no Python build dependency is
    # fetched. meson then resolves the staged subprojects/keycodemapdb (below),
    # and the [meson]/[tooling] groups are satisfied by QEMU's own vendored
    # python/wheels plus the hermetic venv. Without it, a missing subproject is
    # silently cloned instead of failing at setup, which is exactly the network
    # access being denied above.
    args << "--disable-download"

    # The test suite needs two more [wrap-git] subprojects from gitlab.com
    # (tests/fp/meson.build: berkeley-softfloat-3 and berkeley-testfloat-3),
    # and nothing outside tests/ links their libraries, nor are they installed.
    # Skip them instead of vendoring two more pinned revisions to keep current.
    args << "--disable-tests"

    # ParavirtualizedGraphics (apple-gfx) APIs used by QEMU were obsoleted
    # in the macOS 27 SDK; same guard as Homebrew's core qemu formula.
    args << "--disable-pvg" if OS.mac? && MacOS.version >= :golden_gate

    # The arm64 HVF backend needs the macOS 15 SDK for its EL2 sysregs and
    # vGIC. Same guard as Homebrew's core qemu formula, so the source-build
    # path the README advertises works on older macOS too.
    args << "--disable-hvf" if OS.mac? && Hardware::CPU.arm? && MacOS.version <= :sonoma

    # smbd for -net user,smb=. Only wired up when a samba build providing it
    # is actually installed (e.g. via a third-party tap); otherwise the flag
    # is omitted so the binary never embeds a path to a nonexistent binary.
    smbd = HOMEBREW_PREFIX/"sbin/samba-dot-org-smbd"
    args << "--smbd=#{smbd}" if smbd.executable?

    args << "--target-list=aarch64-softmmu"

    # meson runs from inside ./configure, so the subproject must already be in
    # place by then: with --wrap-mode=nodownload (from --disable-download) a
    # missing subprojects/keycodemapdb is a hard error instead of a fetch. The
    # wrap has no `directory` field, so meson derives the name from the project
    # name and the staged directory must be exactly subprojects/keycodemapdb.
    keymaps_dir = buildpath/"subprojects/keycodemapdb"
    resource("keycodemapdb").stage do
      # Resource#stage changes into the archive's top-level directory, so the
      # working directory normally already holds keycodemapdb's contents.
      # Fall back to the wrapped layout if that ever changes, and fail loudly
      # on anything else rather than staging a partial subproject.
      if File.exist?("meson.build")
        source = Pathname(".")
      else
        wrapped = Dir["keycodemapdb-*/"].find { |dir| File.exist?("#{dir}meson.build") }
        raise "unexpected keycodemapdb archive layout: #{Dir["*"].inspect}" if wrapped.nil?

        source = Pathname(wrapped)
      end
      keymaps_dir.mkpath
      # children covers dotfiles but excludes "." and "..", which
      # Pathname#install would reject.
      keymaps_dir.install(source.children)
    end

    # meson only consults a wrap when it must download, so a branch move that
    # bumps the wrap's revision leaves the staged copy silently stale (older
    # keymaps, still building). This tap tracks a moving branch, so assert the
    # staged revision is the one QEMU's wrap currently asks for.
    wrap_revision = (buildpath/"subprojects/keycodemapdb.wrap").read[/^revision = (\S+)$/, 1]
    unless resource("keycodemapdb").url.include?(wrap_revision.to_s)
      raise "subprojects/keycodemapdb.wrap pins #{wrap_revision.inspect}, " \
            "but the staged keycodemapdb resource targets a different revision"
    end

    system "./configure", *args
    system "make", "V=1"
    system "make", "install"

    # Runtime resolution needs no install_name_tool rewriting.
    #
    # QEMU never links libangle directly: libepoxy dlopens EGL, and QEMU links
    # libepoxy and libvirglrenderer, both of which Homebrew records with
    # absolute `$(brew --prefix)/opt/<formula>/lib/...` install names. The
    # -Wl,-rpath entries above are belt-and-braces for Homebrew versions that
    # use @rpath install names and rely on an rpath to resolve them; they are
    # prefix-relative, so they relocate correctly into the bottle either way.
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
