require_relative "../lib/no_submodule_git_download_strategy"

class Libangle < Formula
  desc "Conformant OpenGL ES implementation for Windows, Mac, Linux, iOS and Android"
  homepage "https://chromium.googlesource.com/angle/angle"
  # NoSubmoduleGitDownloadStrategy avoids cloning ANGLE's private submodules
  # (e.g. third_party/gles1_conform -> chrome-internal.googlesource.com), which
  # would require auth. The DEPS-managed third_party/* are staged manually below.
  url "https://chromium.googlesource.com/angle/angle.git",
      branch: "main",
      using:  NoSubmoduleGitDownloadStrategy
  version "main"
  license "BSD-3-Clause"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    sha256 cellar: :any, arm64_golden_gate: "a713cae333463de4e3fcad130507cf0de45c725bb77981252b47c276499fcaee"
  end

  # keg_only: ANGLE's public headers are installed into the shared prefix, so a
  # linked keg would put ANGLE's EGL/GLES/KHR headers on the default include
  # path of every formula compiled afterwards on the machine, where they would
  # silently shadow any other provider's. Consumers here (virglrenderer and
  # qemu-virgl) find it through explicit -I/-L and PKG_CONFIG_PATH instead.
  # `cellar: :any` above keeps the dylibs relocatable when poured.
  keg_only :versioned_formula

  depends_on "milesbuckton/qemu-virgl/gn" => :build
  depends_on "ninja" => :build
  depends_on "python@3.14" => :build
  depends_on "rapidjson"

  # ANGLE's public API is EGL + GLES + KHR. Its include/ directory also carries
  # CL/ (OpenCL), WGL/ (Windows), GLX/ (Linux) and vulkan/, none of which are
  # usable on macOS and all of which would collide with a real provider in
  # $(brew --prefix)/include.
  ANGLE_HEADERS = %w[
    EGL
    GLES
    GLES2
    GLES3
    KHR
  ].freeze

  # The GL frontends. libGLESv2_with_capture (3.8 MB) and libfeature_support
  # (88 KB) are ANGLE's own test/capture harnesses, not a runtime library.
  ANGLE_LIBRARIES = %w[
    libEGL
    libGLESv1_CM
    libGLESv2
  ].freeze

  # Chromium build dependencies - commit hashes from DEPS
  resource "chromium-build" do
    url "https://github.com/gsource-mirror/chromium-src-build.git",
        revision: "dd54bc718b7c5363155660d12b7965ea9f87ada9",
        using:    :git
  end

  resource "chromium-testing" do
    url "https://github.com/gsource-mirror/chromium-src-testing.git",
        revision: "6d914f364e23232b935ac9fb3a615065b716da13",
        using:    :git
  end

  resource "vulkan-headers" do
    url "https://github.com/KhronosGroup/Vulkan-Headers.git",
        revision: "d1cd37e925510a167d4abef39340dbdea47d8989",
        using:    :git
  end

  resource "chromium-zlib" do
    url "https://github.com/gsource-mirror/chromium-src-third_party-zlib.git",
        revision: "85f05b0835f934e52772efc308baa80cdd491838",
        using:    :git
  end

  resource "chromium-jsoncpp" do
    url "https://github.com/gsource-mirror/chromium-src-third_party-jsoncpp.git",
        revision: "f62d44704b4da6014aa231cfc116e7fd29617d2a",
        using:    :git
  end

  resource "jsoncpp-source" do
    url "https://github.com/open-source-parsers/jsoncpp.git",
        revision: "42e892d96e47b1f6e29844cc705e148ec4856448",
        using:    :git
  end

  resource "spirv-headers" do
    url "https://github.com/KhronosGroup/SPIRV-Headers.git",
        revision: "01e0577914a75a2569c846778c2f93aa8e6feddd",
        using:    :git
  end

  resource "spirv-tools" do
    url "https://github.com/KhronosGroup/SPIRV-Tools.git",
        revision: "d7ac0e0fd062953f946169304456b58e36c32778",
        using:    :git
  end

  resource "astc-encoder" do
    url "https://github.com/ARM-software/astc-encoder.git",
        revision: "2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b",
        using:    :git
  end

  # Every dependency arrives as a checksummed `resource` above and is staged
  # locally; ANGLE's submodules are skipped (NoSubmoduleGitDownloadStrategy)
  # and the build is gn + ninja on the system toolchain. Nothing fetches at
  # build time, so make that offline invariant a hard guarantee.
  deny_network_access!

  def install
    ohai "Staging Chromium build dependencies..."

    resource("chromium-build").stage do
      (buildpath/"build").install Dir["*"]
    end

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

    # Create gclient_args.gni
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

    # Apply MacPorts-style patches to use the system toolchain instead of
    # Chromium's bundled clang. Verified against ANGLE revision 62861200bf
    # (version "2025.11.24"); `url` tracks `main`, so re-verify when bumping.
    #
    # Every patch below is REQUIRED to match. `inreplace`'s block form and
    # `String#gsub!` both no-op silently, which for a moving upstream branch
    # means either a baffling build failure or — worse — a toolchain that was
    # never actually patched. `patch!` turns a missed match into an
    # explanation instead.
    ohai "Applying patches for system toolchain..."

    toolchain = "build/toolchain/apple/toolchain.gni"
    patch! toolchain, /^\s+prefix = rebase_path/, "#    prefix = rebase_path",
            "comment out Chromium's bundled toolchain prefix"
    patch! toolchain, /^\s+compiler_prefix = /, "#    compiler_prefix = ",
            "comment out Chromium's bundled toolchain compiler_prefix"
    patch! toolchain, '_cc = "${prefix}clang"', '_cc = "clang"',
            "use the system C compiler"
    patch! toolchain, '_cxx = "${prefix}clang++"', '_cxx = "clang++"',
            "use the system C++ compiler"
    patch! toolchain, "cc = compiler_prefix + _cc", "cc = _cc",
            "drop compiler_prefix from the C compiler command"
    patch! toolchain, "cxx = compiler_prefix + _cxx", "cxx = _cxx",
            "drop compiler_prefix from the C++ compiler command"
    patch! toolchain, "ld = _cxx", "ld = cxx",
            "link with the system driver"
    patch! toolchain, 'nm = "${prefix}llvm-nm"', 'nm = "nm"',
            "use the system nm"
    patch! toolchain, 'otool = "${prefix}llvm-otool"', 'otool = "otool"',
            "use the system otool"
    patch! toolchain, '_strippath = "${prefix}llvm-strip"', '_strippath = "strip"',
            "use the system strip"
    patch! toolchain, '_installnametoolpath = "${prefix}llvm-install-name-tool"',
            '_installnametoolpath = "install_name_tool"',
            "use the system install_name_tool"
    patch! toolchain, %r{rebase_path\("//tools/clang/dsymutil/bin/dsymutil",\s+root_build_dir\)},
            '"dsymutil"', "use the system dsymutil"

    # Chromium's build.gni runs scripts with the hermetic CPython that a full
    # gclient sync would place in third_party/cpython3; point it at the
    # Homebrew python instead (exit 127 otherwise).
    (buildpath/"third_party/cpython3/host/bin").mkpath
    ln_s formula_opt_bin("python@3.14")/"python3",
         buildpath/"third_party/cpython3/host/bin/python3"

    # Create dummy rust-toolchain VERSION
    (buildpath/"third_party/rust-toolchain").mkpath
    (buildpath/"third_party/rust-toolchain/VERSION").write "rustc 0.0.0 (00000000 0000-00-00)\n"

    # Symlink rapidjson headers
    (buildpath/"third_party/rapidjson/src").mkpath
    ln_s formula_opt_include("rapidjson"), buildpath/"third_party/rapidjson/src/include"

    # Comment out Rust import. ANGLE's `main` branch ships this, but guard it:
    # a branch-tracking `url` means the file may legitimately change shape.
    if File.exist?("testing/test.gni") && File.read("testing/test.gni").include?("rust_static_library.gni")
      patch! "testing/test.gni",
              %r{^import\("//build/rust/rust_static_library.gni"\)},
              '#import("//build/rust/rust_static_library.gni")',
              "drop the Rust test dependency ANGLE does not build here"
    end

    # Remove the sanitize_c_array_bounds block ANGLE added for a crbug fix.
    if File.exist?("gni/angle.gni") && File.read("gni/angle.gni").include?("sanitize_c_array_bounds")
      ohai "Removing sanitize_c_array_bounds block..."
      patch! "gni/angle.gni", %r{# See https://crbug.com/386992829.*?^  \}}m, "",
              "remove the sanitize_c_array_bounds block"
    end

    ohai "Starting GN configuration..."
    # Configure and build with gn and ninja.
    #
    # Only the GL/GLES frontends are built. On Apple, ANGLE implements them on
    # top of its Metal *backend*, so the resulting libEGL/libGLESv2 link
    # Metal.framework — not the CGL/OpenGL framework, and not MoltenVK.
    # `angle_enable_metal` and `angle_enable_vulkan` gate the standalone
    # Metal and Vulkan *frontends*, which virglrenderer has no use for, hence
    # they stay off. Vulkan reaches the guest only through virglrenderer's
    # Venus path, which dlopens the host's libvulkan at runtime; see the
    # virglrenderer formula.
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
    # Install only the libraries and headers this tap's formulae consume, so
    # the keg has a defined API surface instead of ANGLE's full tree — which
    # would also carry OpenCL (CL/), Windows (WGL/) and Linux (GLX/) headers.
    #
    # Receiver form (`lib.install`), never a bare `install src => lib`: inside
    # `def install` a receiver-less call resolves to Formula#install itself,
    # which is arity-0 — the hash form raises ArgumentError and the build dies
    # here. (Battle scar; do not "simplify" this back.)
    ANGLE_LIBRARIES.each do |name|
      lib.install "out/Release/#{name}.dylib"
    end
    ANGLE_HEADERS.each do |dir|
      include.install "include/#{dir}"
    end
  end

  def caveats
    <<~EOS
      QEMU from this tap links ANGLE via embedded rpaths — no environment
      setup is needed. If you build your own binaries against libangle, add
      its lib dir to your library path first:

        export DYLD_FALLBACK_LIBRARY_PATH="#{opt_lib}:$DYLD_FALLBACK_LIBRARY_PATH"

      For full documentation and usage examples, see:
      https://github.com/milesbuckton/homebrew-qemu-virgl
    EOS
  end

  private

  # Replace every occurrence of `pattern` with `replacement` in `path`, raising
  # when it does not match.
  #
  # `url` tracks ANGLE's `main` branch, so its build files move underneath us.
  # `inreplace`'s block form and `String#gsub!` both no-op silently on a miss,
  # which turns an upstream reshuffle into either a baffling build failure or a
  # toolchain that was never patched at all. This makes the miss explicit.
  def patch!(path, pattern, replacement, description)
    found =
      case pattern
      when Regexp
        File.read(path).match?(pattern)
      else
        File.read(path).include?(pattern)
      end
    unless found
      raise <<~EOS
        Cannot patch #{path} to #{description}.
        Pattern not found: #{pattern.inspect}

        ANGLE's build files have changed shape upstream. Re-check this patch
        against the new revision (the ANGLE revision this formula was last
        verified against is recorded above) and bump the pinned Chromium
        `resource` revisions to match ANGLE's DEPS file.
      EOS
    end

    inreplace path, pattern, replacement
  end

  test do
    ANGLE_LIBRARIES.each do |name|
      assert_path_exists lib/"#{name}.dylib"
    end

    (testpath/"test.c").write <<~EOS
      #include <EGL/egl.h>
      #include <GLES2/gl2.h>
      #include <stdio.h>

      int main(void) {
        EGLint major, minor;
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY) {
          /* Headless (CI has no window server). The dylibs still had to load
           * for us to reach this point, which is all this test can assert. */
          printf("no display; link check only\\n");
          return 0;
        }
        if (!eglInitialize(display, &major, &minor)) {
          fprintf(stderr, "eglInitialize failed\\n");
          return 1;
        }
        printf("ANGLE test: EGL %d.%d\\n", major, minor);
        return 0;
      }
    EOS

    # -Wl,-rpath keeps the test binary runnable on Homebrew versions that give
    # the installed dylibs an @rpath install name and rely on an rpath to
    # resolve them; current Homebrew uses absolute $(brew --prefix)/opt paths.
    system ENV.cc, "test.c",
           "-I#{include}",
           "-L#{lib}",
           "-Wl,-rpath,#{lib}",
           "-lEGL",
           "-lGLESv2",
           "-o", "test"

    # Asserting on the program's own output proves the binary actually ran, so
    # a dylib that failed to load fails the test instead of being hidden behind
    # an exit status the shell reports as success. Accept the headless branch
    # too ("no display; link check only", see test.c above): on a machine with
    # no window server that output is still proof the dylibs loaded, and
    # requiring "ANGLE test" would fail the test on exactly the machines the
    # branch exists for.
    assert_match(/ANGLE test|no display/, shell_output("./test"))
  end
end
