class LibepoxyAngle < Formula
  desc "Library for handling OpenGL function pointer management"
  homepage "https://github.com/anholt/libepoxy"
  url "https://github.com/anholt/libepoxy.git",
      branch: "master"
  version "master"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    sha256 cellar: :any, arm64_golden_gate: "74b2c0822f10362c814501a8adad8e1afc96ad744c02fc54fbfe532ad1a604ab"
  end

  # keg_only: this tap intentionally replaces the standard `libepoxy` and both
  # ship headers at include/epoxy/*. Installing ours into /opt/homebrew would
  # collide with the core formula's keg whenever the user has one (a core
  # `qemu` install brings it in). Consumers find it via the explicit -I/-L
  # and PKG_CONFIG_PATH set in the qemu-virgl/virglrenderer formulae. The
  # reason is a plain string because no keg_only symbol fits — and
  # :provided_by_macos_or_another_formula, used here previously, does not
  # exist in Homebrew at all (only :provided_by_macos/:shadowed_by_macos do).
  keg_only "it shadows the core libepoxy formula's headers and library"

  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  # Keep in lockstep with HermeticVenv::PYTHON; style.yml's lockstep check
  # enforces it (a drift would otherwise surface 30 minutes into a publish).
  depends_on "python@3.15" => :build
  # dlopens the tap's Metal-backed ANGLE; macOS only.
  depends_on :macos
  depends_on "milesbuckton/qemu-virgl/libangle"

  # meson + ninja against a Homebrew-provided ANGLE, with no subprojects, so
  # the build never needs the network. Make that explicit.
  deny_network_access!

  def install
    mkdir "build" do
      system "meson", *std_meson_args,
             "-Dc_args=-I#{formula_opt_prefix("milesbuckton/qemu-virgl/libangle")}/include",
             "-Dc_link_args=-L#{formula_opt_prefix("milesbuckton/qemu-virgl/libangle")}/lib",
             "-Degl=yes", "-Dx11=false",
             ".."
      system "ninja", "-v"
      system "ninja", "install", "-v"
    end
  end

  test do
    angle = formula_opt_prefix("milesbuckton/qemu-virgl/libangle")

    (testpath/"test.c").write <<~EOS
      #include <epoxy/egl.h>
      #include <stdio.h>

      int main(void) {
        /*
         * This libepoxy is built with -Degl=yes against ANGLE, and it resolves
         * its entry points lazily from a library constructor. epoxy_has_egl()
         * therefore reports whether the EGL resolver actually bound, which is
         * both deterministic (no window server needed) and a real check: a
         * build that could not find EGL reports false here.
         */
        if (!epoxy_has_egl()) {
          fprintf(stderr, "epoxy_has_egl() is false: EGL was not resolved\\n");
          return 1;
        }
        printf("epoxy_has_egl: yes\\n");
        return 0;
      }
    EOS

    # -Wl,-rpath keeps the test binary runnable on Homebrew versions that give
    # the installed dylib an @rpath install name and rely on an rpath to
    # resolve it; current Homebrew uses absolute $(brew --prefix)/opt paths.
    # -I#{include} (not #{include}/epoxy): the test includes <epoxy/egl.h>,
    # and the headers live at include/epoxy/*.h.
    #
    # The ANGLE rpath is load-bearing, not belt-and-braces: libepoxy dlopens
    # the leaf name "libEGL.dylib" from a constructor and has no LC_RPATH of
    # its own (the formula passes -L, not -rpath, at build time). dlopen
    # searches the rpaths of every loaded image, so the test binary must carry
    # ANGLE's lib dir — the same reason qemu-virgl links with
    # -Wl,-rpath,#{angle_prefix}/lib. Without it epoxy_has_egl() is false.
    system ENV.cc, "test.c",
           "-I#{include}", "-I#{angle}/include",
           "-L#{lib}", "-Wl,-rpath,#{lib}",
           "-Wl,-rpath,#{angle}/lib",
           "-lepoxy", "-o", "test"
    assert_match "epoxy_has_egl: yes", shell_output("./test")
  end
end
