class LibepoxyAngle < Formula
  desc "Library for handling OpenGL function pointer management"
  homepage "https://github.com/anholt/libepoxy"
  url "https://github.com/anholt/libepoxy.git",
      branch: "master",
      using:  :git
  version "master"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    sha256 cellar: :any, arm64_golden_gate: "a5bdd5810402baf826a427da4ab10b6236cbb23fe72ed77be635f9d2cf2045ab"
  end

  keg_only :provided_by_macos_or_another_formula

  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.14" => :build
  depends_on "milesbuckton/qemu-virgl/libangle"

  # keg_only: this tap intentionally replaces the standard `libepoxy` and both
  # ship headers at include/epoxy/*. Installing ours into /opt/homebrew would
  # collide with the standard formula (pulled in transitively by qemu-virgl).
  # Consumers find it via the explicit -I/-L and PKG_CONFIG_PATH set in the
  # qemu-virgl/virglrenderer formulae.

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
