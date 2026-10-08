require_relative "../lib/hermetic_venv"

# Formula for virglrenderer with Venus support + borrow_texture_for_scanout.
# Uses miles.buckton fork which includes the scanout borrow and DRM Darwin patches.
class Virglrenderer < Formula
  include HermeticVenv

  desc "VirGL virtual OpenGL renderer"
  homepage "https://gitlab.freedesktop.org/miles.buckton/virglrenderer"

  url "https://gitlab.freedesktop.org/miles.buckton/virglrenderer.git",
      branch: "main"
  version "main"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    sha256 arm64_golden_gate: "0db69830b601d38a2463a7545eedcd9a514b8974ba7e60ee38a739e196fe1f27"
  end

  depends_on "cmake" => :build
  # epoll-shim is statically linked — otool -L on the installed dylib shows no
  # libepoll-shim dependency, and the bottle loads on machines without it
  # installed. It is correctly build-only; do not "fix" it into a runtime dep.
  depends_on "epoll-shim" => :build
  depends_on "libyaml" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.14" => :build
  # spice-protocol is headers + a .pc file only (no library), needed at compile
  # time for the venus host path; core's qemu formula likewise marks it :build.
  depends_on "spice-protocol" => :build
  depends_on "vulkan-headers" => :build
  depends_on "milesbuckton/qemu-virgl/libangle"
  depends_on "milesbuckton/qemu-virgl/libepoxy-angle"
  depends_on "vulkan-loader"

  # Meson subproject of the build. The wrap file in the fork pins v1.1.3
  # (directory venus-protocol-1.1.3) and meson's "subprojects download" caches
  # the tarball without extracting it, so it is staged manually in `install`
  # below. Declared here as a resource rather than cloned at install time so
  # the build is hermetic and the revision is pinned.
  #
  # No `using: :git`: the `.git` suffix already selects GitDownloadStrategy, and
  # `brew audit` flags the explicit form as redundant.
  resource "venus-protocol" do
    url "https://gitlab.freedesktop.org/virgl/venus-protocol.git",
        revision: "ca19b6358d7cc491bc3e4de76f04c6700876a8fa"
  end

  # Build backend for the venv below, pinned and checksummed so `pip install`
  # never has to reach PyPI. `--no-index` makes a missing build requirement a
  # hard error rather than a silent download, so the *transitive* ones are
  # pinned too: wheel needs packaging, and pyyaml's pyproject.toml requires
  # Cython on Python >= 3.13. See HermeticVenv in ../lib/hermetic_venv.rb.
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

  resource "cython" do
    url "https://files.pythonhosted.org/packages/bf/77/67b0b24e45073a699610e50f00c18474ff9b09ea29ecc95083bdf5e60acd/cython-3.3.0-py3-none-any.whl"
    sha256 "9b24b5c8cd536946b62086fcafee6d5509d3f549f72d553d2336af87ffbe0da1"
  end

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/54/ed/79a089b6be93607fa5cdaedf301d7dfb23af5f25c398d5ead2525b063e17/pyyaml-6.0.2.tar.gz"
    sha256 "d584d9ec91ad65861cc08d42e834324ef890a082e591037abe114850ff7bbc3e"
  end

  resource "markupsafe" do
    url "https://files.pythonhosted.org/packages/7e/99/7690b6d4034fffd95959cbe0c02de8deb3098cc577c67bb6a24fe5d7caa7/markupsafe-3.0.3.tar.gz"
    sha256 "722695808f4b6457b320fdc131280796bdceb04ab50fe1795cd540799ebe1698"
  end

  resource "mako" do
    url "https://files.pythonhosted.org/packages/2a/12/b5fa2353e2754cd67fb9f83793fa48ff42c213a5da7e719869d2301f6ab8/mako-1.4.1.tar.gz"
    sha256 "d7904710b662996425a21627710c4777c45053146942cf8a7aebf757c92b8c27"
  end

  # Sources and the meson venus-protocol subproject are staged as resources and
  # pip runs against the local wheelhouse; no wrap DB is consulted. Make that
  # offline build explicit.
  deny_network_access!

  def install
    venv_path = buildpath/"venv"
    venv_python = hermetic_venv(venv_path, %w[setuptools wheel packaging cython])

    hermetic_pip_install(venv_python, "pyyaml")
    hermetic_pip_install(venv_python, "markupsafe")
    hermetic_pip_install(venv_python, "mako")

    ENV["PYTHON"] = venv_python
    ENV.prepend_path "PYTHONPATH", venv_site_packages(venv_python)
    # meson's import('python').find_installation('python3', modules: ['mako'])
    # in the venus-protocol subproject resolves 'python3' from PATH, not from
    # ENV["PYTHON"], so the venv bin must lead PATH for the mako check to pass.
    ENV.prepend_path "PATH", venv_path/"bin"

    epoxy = Formula["milesbuckton/qemu-virgl/libepoxy-angle"]
    angle = Formula["milesbuckton/qemu-virgl/libangle"]

    vulkan = Formula["vulkan-loader"]
    spice = Formula["spice-protocol"]
    epoll_shim = Formula["epoll-shim"]
    ENV.prepend_path "PKG_CONFIG_PATH", "#{epoxy.opt_lib}/pkgconfig"
    ENV.prepend_path "PKG_CONFIG_PATH", "#{vulkan.opt_lib}/pkgconfig"
    ENV.append "PKG_CONFIG_PATH", "#{spice.opt_share}/pkgconfig"
    ENV.append "PKG_CONFIG_PATH", "#{epoll_shim.opt_lib}/pkgconfig"
    ENV.append "LDFLAGS", "-L#{angle.opt_lib}"
    ENV.append "CPPFLAGS", "-I#{angle.opt_include}"

    # meson subprojects download only caches the tarball, it does NOT extract
    # it. Stage the pinned venus-protocol resource into the subprojects dir so
    # the subproject is present before meson setup. The dir name must match
    # the wrap's `directory` field (venus-protocol-1.1.3 at the revision the
    # wrap pins). v1.1.2+ ships include/vulkan/vulkan_metal.h, which
    # src/venus/vkr_metal_helpers.m includes via "venus-protocol/vulkan_metal.h".
    venus_dir = buildpath/"subprojects/venus-protocol-1.1.3"
    venus_dir.mkpath
    resource("venus-protocol").stage do
      venus_dir.install Dir["*"]
    end

    # Create a venus-protocol -> include/vulkan symlink inside the subproject
    # so the include resolves for Metal helpers (vkr_metal_helpers.m does
    # #include "venus-protocol/vulkan_metal.h"). Must happen before setup.
    link = venus_dir/"venus-protocol"
    link.make_symlink("include/vulkan") unless link.exist?

    system "meson", "setup", "build",
           "--prefix=#{prefix}",
           "--buildtype=release",
           "-Dplatforms=egl",
           "-Dvenus=true",
           "--pkg-config-path=#{epoxy.opt_lib}/pkgconfig",
           # venus-protocol is staged into subprojects/ above. Refuse to fetch
           # any *other* subproject from the wrap DB, mirroring the offline
           # build `deny_network_access!` enforces: a missing subproject then
           # fails clearly here at setup instead of attempting a download.
           "--wrap-mode=nodownload"

    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  test do
    # `virgl_test_server` has no --help option: an unrecognised flag falls
    # through to virglrenderer's usage banner and exits EXIT_FAILURE, and the
    # banner is spelled "Usage:", so do not drive the test off it. Assert the
    # library loads and initialises instead, and that the test server — which
    # virglrenderer's own test suite drives — is installed.
    assert_path_exists "#{bin}/virgl_test_server"
    assert_path_exists "#{lib}/libvirglrenderer.1.dylib"

    (testpath/"test.c").write <<~EOS
      #include <stdio.h>
      #include <virglrenderer.h>

      int main(void) {
        struct virgl_renderer_callbacks cbs = {0};
        cbs.version = 1;

        /* VIRGL_RENDERER_NO_VIRGL avoids needing an EGL/GL context, so this
           works on a headless runner. */
        if (virgl_renderer_init(NULL, VIRGL_RENDERER_NO_VIRGL, &cbs) != 0) {
          fprintf(stderr, "virgl_renderer_init failed\\n");
          return 1;
        }
        virgl_renderer_poll();
        virgl_renderer_cleanup(NULL);
        printf("virgl_renderer_init: OK\\n");
        return 0;
      }
    EOS

    # -Wl,-rpath keeps the test binary runnable on Homebrew versions that give
    # the installed dylibs an @rpath install name and rely on an rpath to
    # resolve them; current Homebrew uses absolute $(brew --prefix)/opt paths.
    system ENV.cc, "test.c",
           "-I#{include}/virgl",
           "-L#{lib}", "-Wl,-rpath,#{lib}",
           "-lvirglrenderer",
           "-o", "test"
    assert_match "virgl_renderer_init: OK", shell_output("./test")
  end
end
