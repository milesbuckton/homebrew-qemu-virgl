# Formula for virglrenderer with Venus support + borrow_texture_for_scanout.
# Uses miles.buckton fork which includes the scanout borrow and DRM Darwin patches.
class Virglrenderer < Formula
  desc "VirGL virtual OpenGL renderer"
  homepage "https://gitlab.freedesktop.org/miles.buckton/virglrenderer"

  url "https://gitlab.freedesktop.org/miles.buckton/virglrenderer.git",
      branch: "main"
  version "main"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    rebuild 1
    sha256 arm64_tahoe: "641889c23faf8ed77c38161a7c9466adf690435e35cc5468b2e2cd8093dda15b"
  end

  depends_on "cmake" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.14" => :build
  depends_on "vulkan-headers" => :build
  depends_on "libyaml" => :build
  depends_on "epoll-shim" => :build
  depends_on "milesbuckton/qemu-virgl/libangle"
  depends_on "milesbuckton/qemu-virgl/libepoxy-angle"
  depends_on "spice-protocol"
  depends_on "vulkan-loader"

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

  def install
    python3 = formula_opt_bin("python@3.14")/"python3.14"
    venv_path = buildpath/"venv"
    system python3, "-m", "venv", venv_path
    venv_python = venv_path/"bin/python"

    resource("pyyaml").stage do
      system venv_python, "-m", "pip", "install", "."
    end

    resource("markupsafe").stage do
      system venv_python, "-m", "pip", "install", "."
    end

    resource("mako").stage do
      system venv_python, "-m", "pip", "install", "."
    end

    ENV["PYTHON"] = venv_python
    ENV.prepend_path "PYTHONPATH", venv_path/"lib/python3.14/site-packages"
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
    # it. Manually clone venus-protocol v1.1.1 into the subprojects dir so
    # the subproject is present before meson setup. Use git + depth=1 to avoid
    # downloading full history. The extracted dir name must match the wrap's
    # `directory` field (venus-protocol-1.1.1 at our pinned rev).
    venus_dir = buildpath/"subprojects/venus-protocol-1.1.1"
    unless venus_dir.exist?
      system "git", "clone", "--depth=1", "--branch=v1.1.1",
             "https://gitlab.freedesktop.org/virgl/venus-protocol.git",
             venus_dir.to_s
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
           "--pkg-config-path=#{epoxy.opt_lib}/pkgconfig"

    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  test do
    assert_match "usage", shell_output("#{bin}/virgl_test_server --help")
  end
end
