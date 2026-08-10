class NoSubmoduleGitDownloadStrategy < GitDownloadStrategy
  def submodules?; false; end
end

class Libangle < Formula
  desc "Conformant OpenGL ES implementation for Windows, Mac, Linux, iOS and Android"
  homepage "https://chromium.googlesource.com/angle/angle"
  # Pin to the ANGLE commit whose DEPS matches every resource revision below
  # (build dd54bc71, testing 6d914f36, vulkan-headers d1cd37e9, zlib 85f05b08,
  # jsoncpp f62d4470, spirv-headers 01e05779, spirv-tools d7ac0e0f,
  # astc-encoder 2319d9c4) — 2025-09-29 on main.
  # NoSubmoduleGitDownloadStrategy avoids cloning ANGLE's private submodules
  # (e.g. third_party/gles1_conform -> chrome-internal.googlesource.com), which
  # would require auth. The DEPS-managed third_party/* are staged manually below.
  url "https://chromium.googlesource.com/angle/angle.git",
      revision: "62861200bff6e265d6518ef1faa0f2eb90439dbc",
      using: NoSubmoduleGitDownloadStrategy
  version "2025.11.24"
  license "BSD-3-Clause"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    rebuild 1
    sha256 cellar: :any, arm64_tahoe: "40a371009e94e70fa23f5b97d906dccbe3188c7f7b56e91b99f33b6a5f397f39"
    sha256 cellar: :any, tahoe:       "5983f94f4789d25a37bf3a7802b971701884bbba7d31e75ef9c972922babbc28"
  end

  depends_on "milesbuckton/qemu-virgl/gn" => :build
  depends_on "ninja" => :build
  depends_on "python@3.13" => :build
  depends_on "rapidjson"

  # Chromium build dependencies - commit hashes from DEPS
  resource "chromium-build" do
    url "https://github.com/gsource-mirror/chromium-src-build.git",
        revision: "dd54bc718b7c5363155660d12b7965ea9f87ada9",
        using: :git
  end

  resource "chromium-testing" do
    url "https://github.com/gsource-mirror/chromium-src-testing.git",
        revision: "6d914f364e23232b935ac9fb3a615065b716da13",
        using: :git
  end

  resource "vulkan-headers" do
    url "https://github.com/KhronosGroup/Vulkan-Headers.git",
        revision: "d1cd37e925510a167d4abef39340dbdea47d8989",
        using: :git
  end

  resource "chromium-zlib" do
    url "https://github.com/gsource-mirror/chromium-src-third_party-zlib.git",
        revision: "85f05b0835f934e52772efc308baa80cdd491838",
        using: :git
  end

  resource "chromium-jsoncpp" do
    url "https://github.com/gsource-mirror/chromium-src-third_party-jsoncpp.git",
        revision: "f62d44704b4da6014aa231cfc116e7fd29617d2a",
        using: :git
  end

  resource "jsoncpp-source" do
    url "https://github.com/open-source-parsers/jsoncpp.git",
        revision: "42e892d96e47b1f6e29844cc705e148ec4856448",
        using: :git
  end

  resource "spirv-headers" do
    url "https://github.com/KhronosGroup/SPIRV-Headers.git",
        revision: "01e0577914a75a2569c846778c2f93aa8e6feddd",
        using: :git
  end

  resource "spirv-tools" do
    url "https://github.com/KhronosGroup/SPIRV-Tools.git",
        revision: "d7ac0e0fd062953f946169304456b58e36c32778",
        using: :git
  end

  resource "astc-encoder" do
    url "https://github.com/ARM-software/astc-encoder.git",
        revision: "2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b",
        using: :git
  end

  def install
    ohai "Installing Chromium build dependencies..."

    # Download and setup all Chromium dependencies
    ohai "Staging chromium-build..."
    resource("chromium-build").stage do
      (buildpath/"build").install Dir["*"]
    end

    ohai "Staging chromium-testing..."
    resource("chromium-testing").stage do
      (buildpath/"testing").install Dir["*"]
    end

    (buildpath/"third_party/vulkan-headers").mkpath
    resource("vulkan-headers").stage do
      (buildpath/"third_party/vulkan-headers/src").install Dir["*"]
    end

    (buildpath/"third_party/zlib").mkpath
    resource("chromium-zlib").stage do
      (buildpath/"third_party/zlib").install Dir["*"]
    end

    (buildpath/"third_party/jsoncpp").mkpath
    resource("chromium-jsoncpp").stage do
      (buildpath/"third_party/jsoncpp").install Dir["*"]
    end

    resource("jsoncpp-source").stage do
      (buildpath/"third_party/jsoncpp/source").install Dir["*"]
    end

    (buildpath/"third_party/spirv-headers").mkpath
    resource("spirv-headers").stage do
      (buildpath/"third_party/spirv-headers/src").install Dir["*"]
    end

    (buildpath/"third_party/spirv-tools").mkpath
    resource("spirv-tools").stage do
      (buildpath/"third_party/spirv-tools/src").install Dir["*"]
    end

    (buildpath/"third_party/astc-encoder").mkpath
    resource("astc-encoder").stage do
      (buildpath/"third_party/astc-encoder/src").install Dir["*"]
    end

    ohai "All resources staged successfully"

    # Create gclient_args.gni
    ohai "Creating gclient_args.gni..."
    (buildpath/"build/config/gclient_args.gni").write <<~EOS
      # Generated from DEPS
      checkout_angle_internal = false
      checkout_angle_mesa = false
      checkout_angle_restricted_traces = false
      generate_location_tags = false
      checkout_android = false
      checkout_android_native_support = false
      checkout_google_benchmark = false
      checkout_openxr = false
      checkout_telemetry_dependencies = false
    EOS

    # Apply MacPorts-style patches (make them optional to support different ANGLE versions)
    ohai "Applying patches for system toolchain..."

    # Use system toolchain - check file content first
    toolchain_content = File.read("build/toolchain/apple/toolchain.gni")
    has_prefix = toolchain_content.include?("prefix = rebase_path")
    has_compiler_prefix = toolchain_content.include?("compiler_prefix = ")

    inreplace "build/toolchain/apple/toolchain.gni" do |s|
      s.gsub!(/^\s+prefix = rebase_path/, "#    prefix = rebase_path") if has_prefix
      s.gsub!(/^\s+compiler_prefix = /, "#    compiler_prefix = ") if has_compiler_prefix
      s.gsub!(/_cc = "\$\{prefix\}clang"/, '_cc = "clang"')
      s.gsub!(/_cxx = "\$\{prefix\}clang\+\+"/, '_cxx = "clang++"')
      s.gsub!(/cc = compiler_prefix \+ _cc/, "cc = _cc") if has_compiler_prefix
      s.gsub!(/cxx = compiler_prefix \+ _cxx/, "cxx = _cxx") if has_compiler_prefix
      s.gsub!(/ld = _cxx/, "ld = cxx")
      s.gsub!(/nm = "\$\{prefix\}llvm-nm"/, 'nm = "nm"')
      s.gsub!(/otool = "\$\{prefix\}llvm-otool"/, 'otool = "otool"')
      s.gsub!(/_strippath = "\$\{prefix\}llvm-strip"/, '_strippath = "strip"')
      s.gsub!(/_installnametoolpath = "\$\{prefix\}llvm-install-name-tool"/, '_installnametoolpath = "install_name_tool"')
      s.gsub!(/rebase_path\("\/\/tools\/clang\/dsymutil\/bin\/dsymutil",\s+root_build_dir\)/, '"dsymutil"')
    end

    # Create dummy rust-toolchain VERSION
    (buildpath/"third_party/rust-toolchain").mkpath
    (buildpath/"third_party/rust-toolchain/VERSION").write "rustc 0.0.0 (00000000 0000-00-00)\n"

    # Symlink rapidjson headers
    (buildpath/"third_party/rapidjson/src").mkpath
    ln_s Formula["rapidjson"].opt_include, buildpath/"third_party/rapidjson/src/include"

    # Comment out Rust import if it exists
    if File.exist?("testing/test.gni") && File.read("testing/test.gni").include?("rust_static_library.gni")
      inreplace "testing/test.gni",
        /^import\("\/\/build\/rust\/rust_static_library.gni"\)/,
        '#import("//build/rust/rust_static_library.gni")'
    end

    # Remove sanitize_c_array_bounds block if it exists
    if File.exist?("gni/angle.gni") && File.read("gni/angle.gni").include?("sanitize_c_array_bounds")
      ohai "Removing sanitize_c_array_bounds block..."
      inreplace "gni/angle.gni", /# See https:\/\/crbug.com\/386992829.*?^  \}/m, ""
    end

    ohai "Starting GN configuration..."
    # Configure and build with gn and ninja.
    # ANGLE's GL backend (native macOS OpenGL via CGL) is the one virglrenderer
    # uses; Metal and Vulkan backends are disabled. See README "Known
    # limitations" for the rationale.
    system "gn", "gen", "out/Release",
           "--args=mac_sdk_min=\"0\" " \
           "is_official_build=true " \
           "is_clang=false " \
           "treat_warnings_as_errors=false " \
           "fatal_linker_warnings=false " \
           "use_custom_libcxx=false " \
           "angle_build_tests=false " \
           "angle_enable_gl=true " \
           "angle_enable_metal=false " \
           "angle_enable_vulkan=false"

    ohai "Starting ninja build (this will take 10-20 minutes)..."
    system "ninja", "-C", "out/Release"

    ohai "Installing libraries and headers..."
    # Install libraries and headers
    lib.install Dir["out/Release/*.dylib"]
    include.install Dir["include/*"]
  end

  def caveats
    <<~EOS
      To use libangle with QEMU, add this to your environment before running QEMU:

      export DYLD_FALLBACK_LIBRARY_PATH="#{opt_lib}:$DYLD_FALLBACK_LIBRARY_PATH"

      For full documentation and usage examples, see:
      https://github.com/milesbuckton/homebrew-qemu-virgl
    EOS
  end

  test do
    (testpath/"test.c").write <<~EOS
      #include <EGL/egl.h>
      #include <GLES2/gl2.h>
      #include <stdio.h>

      int main() {
        printf("ANGLE test\\n");
        EGLint major, minor;
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY) {
          return 0;
        }
        return eglInitialize(display, &major, &minor) ? 0 : 1;
      }
    EOS

    system ENV.cc, "test.c",
           "-I#{include}",
           "-L#{lib}",
           "-lEGL",
           "-lGLESv2",
           "-o", "test"

    # ANGLE needs a GPU/display to fully initialize, so only verify it links
    # and runs; eglInitialize may return without a usable display.
    system "./test"
  end
end
