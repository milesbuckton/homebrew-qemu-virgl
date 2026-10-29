require_relative "../lib/deps_guard"
require_relative "../lib/no_submodule_git_download_strategy"
require_relative "../lib/staged_tree_guard"

class Libangle < Formula
  include DepsGuard
  include StagedTreeGuard

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
    sha256 cellar: :any, arm64_golden_gate: "de8fc50079c0f3e0318079a22d69311224233c03079282f9c035c39c63398550"
  end

  # keg_only: ANGLE's public headers are installed into the shared prefix, so a
  # linked keg would put ANGLE's EGL/GLES/KHR headers on the default include
  # path of every formula compiled afterwards on the machine, where they would
  # silently shadow any other provider's. Consumers here (virglrenderer and
  # qemu-virgl) find it through explicit -I/-L and PKG_CONFIG_PATH instead.
  # `cellar: :any` above keeps the dylibs relocatable when poured. The reason
  # is a plain string, not a symbol: Homebrew's only keg_only symbols are
  # :versioned_formula/:provided_by_macos/:shadowed_by_macos, none of which is
  # true here — and :versioned_formula is worse than wrong, because `brew
  # link` may link a versioned-formula keg without --force (cmd/link.rb),
  # which is exactly what this formula must never allow.
  keg_only "it puts ANGLE's EGL/GLES/KHR headers on the default include path, shadowing other providers"

  depends_on "milesbuckton/qemu-virgl/gn" => :build
  depends_on "ninja" => :build
  # Keep in lockstep with HermeticVenv::PYTHON; style.yml's lockstep check
  # enforces it (a drift would otherwise surface 30 minutes into a publish).
  depends_on "python@3.15" => :build
  # Metal-backed GL on macOS only.
  depends_on "rapidjson" => :build
  depends_on :macos
  # Headers-only build dependency: the installed dylibs link no rapidjson
  # (verified with `otool -L`), so it must not install into users' machines.

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
  #
  # These revisions are NOT this formula's to choose: ANGLE's DEPS file names
  # them, and `assert_deps_revisions!` below fails the build when a revision
  # here stops matching what DEPS says. The mapping from resource to DEPS
  # entry name is what ties the two together.
  #
  # The Chromium trees are fetched from their canonical googlesource
  # repositories rather than the `gsource-mirror` GitHub mirrors: the mirrors
  # lag behind, and the mirror does not carry the current DEPS revisions at
  # all ("fatal: remote error: upload-pack: not our ref <rev>"). The upstream
  # revisions are what DEPS names, so that is where they come from.
  DEPS_ENTRIES = {
    "chromium-build"   => "build",
    "chromium-testing" => "testing",
    "chromium-zlib"    => "third_party/zlib",
    "chromium-zstd"    => "third_party/zstd/src",
    "vulkan-headers"   => "third_party/vulkan-headers/src",
    "spirv-headers"    => "third_party/spirv-headers/src",
    "spirv-tools"      => "third_party/spirv-tools/src",
    "astc-encoder"     => "third_party/astc-encoder/src",
    "chromium-jsoncpp" => "third_party/jsoncpp",
  }.freeze

  # Dependencies DEPS pins through a *variable* rather than through a `deps`
  # entry. Chromium's `third_party/jsoncpp` carries the upstream jsoncpp
  # repository as a nested `source` dependency, so upstream jsoncpp appears
  # nowhere in ANGLE's `deps` block — only the `jsoncpp_revision` variable
  # names it. It is still a revision DEPS owns, so it is still guarded.
  DEPS_VAR_ENTRIES = {
    "jsoncpp-source" => "jsoncpp_revision",
  }.freeze

  resource "chromium-build" do
    url "https://chromium.googlesource.com/chromium/src/build.git",
        revision: "a3081c7c05addf5baf9fda6db48532dda86d2daa"
  end

  resource "chromium-testing" do
    url "https://chromium.googlesource.com/chromium/src/testing.git",
        revision: "d7d69dd4b30636b9805fd9b67bbfeb0fe3dee0e8"
  end

  resource "vulkan-headers" do
    url "https://github.com/KhronosGroup/Vulkan-Headers.git",
        revision: "9fbc2a782ee3f8a4db64e7d991e23da75e893f44"
  end

  resource "chromium-zlib" do
    url "https://chromium.googlesource.com/chromium/src/third_party/zlib.git",
        revision: "9f9f52c60a14e8e772fb561029ae0a121fef7609"
  end

  # `third_party/zstd/src` is a gitlink to facebook/zstd. DEPS names
  # Chromium's mirror of it, so the mirror is what this resource fetches; the
  # mirror is a git-push mirror of upstream and carries the same commits, so
  # the revision below is also reachable from github.com/facebook/zstd.
  resource "chromium-zstd" do
    url "https://chromium.googlesource.com/external/github.com/facebook/zstd.git",
        revision: "10da6ba6de05e29169261fa4b68eb99239f770dd"
  end

  resource "chromium-jsoncpp" do
    url "https://chromium.googlesource.com/chromium/src/third_party/jsoncpp.git",
        revision: "f62d44704b4da6014aa231cfc116e7fd29617d2a"
  end

  resource "jsoncpp-source" do
    url "https://github.com/open-source-parsers/jsoncpp.git",
        revision: "42e892d96e47b1f6e29844cc705e148ec4856448"
  end

  resource "spirv-headers" do
    url "https://github.com/KhronosGroup/SPIRV-Headers.git",
        revision: "fef168c54ed2e37c314eb251806aaf9877f38465"
  end

  resource "spirv-tools" do
    url "https://github.com/KhronosGroup/SPIRV-Tools.git",
        revision: "28f99f74a2a922ff85fc8fd966d6b3d6a45be795"
  end

  resource "astc-encoder" do
    url "https://github.com/ARM-software/astc-encoder.git",
        revision: "2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b"
  end

  # Every dependency arrives as a checksummed `resource` above and is staged
  # locally; ANGLE's submodules are skipped (NoSubmoduleGitDownloadStrategy)
  # and the build is gn + ninja on the system toolchain. Nothing fetches at
  # build time, so make that offline invariant a hard guarantee.
  deny_network_access!

  def install
    ohai "Staging Chromium build dependencies..."

    # ANGLE's DEPS file is the source of truth for the revisions staged below.
    # Assert before staging anything: the guard reads the DEPS file that is
    # already in the fetched source tree, so it costs no network access, and
    # it turns a silently-stale Chromium tree into a loud failure. See
    # ../lib/deps_guard.rb for the rationale.
    deps_text = deps_file.read
    assert_deps_revisions!(deps_text, staged_deps_revisions)
    assert_deps_var_revisions!(deps_text, staged_deps_var_revisions)

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

    # `third_party/zstd` is a plain directory in ANGLE's own tree (it holds
    # the BUILD.gn), with the upstream sources in the `src` gitlink below it.
    # Only the gitlink has to be staged; the BUILD.gn comes with the checkout.
    (buildpath/"third_party/zstd/src").mkpath
    resource("chromium-zstd").stage do
      (buildpath/"third_party/zstd/src").install Dir["*"]
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
    # Chromium's bundled clang. These patches apply to the staged Chromium
    # `build` tree, so the revision to re-verify them against is the
    # `chromium-build` resource's revision — not ANGLE's own. `url` tracks
    # `main`, so re-verify when bumping.
    #
    # Every patch below is REQUIRED to match. `inreplace`'s *block* form and
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
    python3 = formula_opt_bin("python@3.15")/"python3.15"
    ln_s python3, buildpath/"third_party/cpython3/host/bin/python3"
    ln_s python3, buildpath/"third_party/cpython3/host/bin/python"

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

    # `gn gen` succeeds even when a staged dependency is missing: it only
    # writes the build graph, and the graph names source files without
    # checking that they exist. The failure then surfaces in ninja, as an
    # opaque "missing and no known rule to make it" — after the DEPS guard
    # above has already said everything it can. Catch it here instead, and
    # name the tree that has to be staged.
    assert_staged_trees_present!(buildpath/"out/Release/compile_commands.json",
                                  buildpath/"out/Release", buildpath)

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

  # ANGLE's DEPS file, in the fetched source tree.
  #
  # It is checked into ANGLE's own repository, so it is always present after
  # the source fetch and needs no network access to read.
  def deps_file
    buildpath/"DEPS"
  end

  # The revisions this formula stages, keyed by the DEPS entry name that
  # upstream uses for them.
  #
  # `DEPS_ENTRIES` maps the resource name to the DEPS key; the revision comes
  # from the resource's own `revision:` so the two cannot drift apart: a
  # resource block that is bumped without updating DEPS_ENTRIES is a build
  # failure (the resource would be missing from this map), and a resource
  # block that is bumped while DEPS still names the old revision is also a
  # build failure (the guard compares the two).
  def staged_deps_revisions
    DEPS_ENTRIES.to_h do |resource_name, deps_entry|
      revision = resource(resource_name).specs[:revision]
      raise "#{resource_name} does not pin a revision" if revision.nil?

      [deps_entry, revision]
    end
  end

  # The revisions this formula stages that DEPS pins through a variable.
  #
  # Same shape as `staged_deps_revisions`, but keyed by the DEPS variable name
  # instead of a `deps` entry name — see `DEPS_VAR_ENTRIES` for why these
  # dependencies need their own map.
  def staged_deps_var_revisions
    DEPS_VAR_ENTRIES.to_h do |resource_name, var_name|
      revision = resource(resource_name).specs[:revision]
      raise "#{resource_name} does not pin a revision" if revision.nil?

      [var_name, revision]
    end
  end

  # Assert every DEPS-variable-pinned revision still matches.
  def assert_deps_var_revisions!(deps_text, staged)
    staged.each do |var_name, revision|
      assert_deps_var_revision!(deps_text, var_name, revision)
    end
  end

  # Replace every occurrence of `pattern` with `replacement` in `path`, raising
  # when it does not match.
  #
  # `url` tracks ANGLE's `main` branch, so its build files move underneath us.
  # `inreplace`'s *block* form and `String#gsub!` both no-op silently on a
  # miss, which turns an upstream reshuffle into either a baffling build
  # failure or a toolchain that was never patched at all. (The three-argument
  # `inreplace` form does raise on a miss, but with a generic message that
  # does not say which patch failed.) This makes the miss explicit.
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
