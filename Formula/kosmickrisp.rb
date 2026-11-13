require_relative "../lib/hermetic_venv"

# KosmicKrisp: Mesa's Vulkan-on-Metal driver (LunarG), built on its own as an
# alternative host Vulkan ICD to MoltenVK for virglrenderer's Venus backend.
#
# Only the Vulkan driver is built: no gallium drivers, no GL, no EGL/GLX. That
# keeps the keg small and keeps it out of the way of core's mesa, which ships
# the same driver as part of a much larger build.
#
# Approach inspired by startergo/homebrew-qemu-virgl-kosmickrisp, which installs
# the driver from the LunarG Vulkan SDK; this formula builds it from the
# miles.buckton/mesa fork's main branch instead, tracking it like the rest of the
# tap, and keeps the build offline.
class Kosmickrisp < Formula
  include HermeticVenv

  desc "Mesa Vulkan driver layered on Metal (alternative to MoltenVK)"
  homepage "https://docs.mesa3d.org/drivers/kosmickrisp.html"
  url "https://gitlab.freedesktop.org/miles.buckton/mesa.git",
      branch: "main"
  version "main"
  license "MIT"

  # Core's mesa installs the same ICD manifest name; keep this keg out of the
  # shared prefix so the two never fight over share/vulkan/icd.d. Consumers
  # point VK_DRIVER_FILES at this keg's opt_share explicitly.
  keg_only "it conflicts with the KosmicKrisp ICD shipped by core's mesa"

  depends_on "glslang" => :build
  depends_on "libyaml" => :build
  # The driver's internal OpenCL C kernels are compiled at build time by
  # mesa-clc (kk_clc), which needs LLVM and SPIRV-LLVM-Translator. Neither is
  # linked into the driver (checked with otool -L); SPIRV-Tools is.
  depends_on "llvm" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => :build
  # Keep in lockstep with HermeticVenv::PYTHON (enforced by style.yml).
  depends_on "python@3.15" => :build
  depends_on "spirv-llvm-translator" => :build
  # KosmicKrisp needs Metal 4, i.e. macOS 26 (Tahoe) or later.
  depends_on macos: :tahoe
  depends_on "spirv-tools"
  depends_on "vulkan-loader"
  depends_on "zstd"

  uses_from_macos "expat"

  # Same pinned, checksummed wheelhouse as virglrenderer; see HermeticVenv.
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

  deny_network_access!

  def install
    venv_path = buildpath/"venv"
    venv_python = hermetic_venv(venv_path, %w[setuptools wheel packaging cython])
    hermetic_pip_install(venv_python, "pyyaml")
    hermetic_pip_install(venv_python, "markupsafe")
    hermetic_pip_install(venv_python, "mako")

    ENV["PYTHON"] = venv_python
    ENV.prepend_path "PYTHONPATH", venv_site_packages(venv_python)
    ENV.prepend_path "PATH", venv_path/"bin"
    ENV.prepend_path "PATH", formula_opt_bin("llvm")
    ENV["SDKROOT"] = MacOS.sdk_for_formula(self).path
    ENV.append "LDFLAGS", "-Wl,-rpath,#{rpath}"

    system "meson", "setup", "build", *std_meson_args,
           "-Db_ndebug=true",
           "-Dstrip=true",
           "-Dplatforms=macos",
           "-Dvulkan-drivers=kosmickrisp",
           "-Dgallium-drivers=",
           "-Dopengl=false",
           "-Dgles1=disabled",
           "-Dgles2=disabled",
           "-Degl=disabled",
           "-Dglx=disabled",
           "-Dgbm=disabled",
           "-Dllvm=enabled",
           "-Dmesa-clc=enabled",
           "-Dvulkan-layers=",
           "-Dtools=",
           "-Dbuild-tests=false"
    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  def caveats
    <<~EOS
      KosmicKrisp is not on the default Vulkan loader search path. Select it
      per process, for example:
        export VK_DRIVER_FILES="$(echo #{opt_share}/vulkan/icd.d/kosmickrisp_mesa_icd*.json)"
      linux-desktop-vm does this for you with --host-vulkan-driver kosmickrisp.
    EOS
  end

  test do
    icds = Dir[share/"vulkan/icd.d/kosmickrisp_mesa_icd*.json"]
    assert_equal 1, icds.length, "expected exactly one KosmicKrisp ICD manifest"
    assert_path_exists lib/"libvulkan_kosmickrisp.dylib"
    assert_match "libvulkan_kosmickrisp.dylib", File.read(icds.first)
  end
end
