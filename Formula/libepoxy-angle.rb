class LibepoxyAngle < Formula
  desc "Library for handling OpenGL function pointer management"
  homepage "https://github.com/anholt/libepoxy"
  url "https://github.com/anholt/libepoxy.git",
      branch: "master",
      using:    :git
  version "master"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    rebuild 1
    sha256 cellar: :any, arm64_tahoe: "1470bbfaf110506a912b3324d17e76da83038abadd6abca68e1f247efa389ca5"
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
    (testpath/"test.c").write <<~EOS
      #include <epoxy/gl.h>
      #include <OpenGL/CGLContext.h>
      #include <OpenGL/CGLTypes.h>
      #include <OpenGL/OpenGL.h>
      int main() {
          CGLPixelFormatAttribute attribs[] = {0};
          CGLPixelFormatObj pix;
          int npix;
          CGLContextObj ctx;
          CGLChoosePixelFormat((const CGLPixelFormatAttribute *)attribs, &pix, &npix);
          CGLCreateContext(pix, NULL, &ctx);
          glClear(GL_COLOR_BUFFER_BIT);
          CGLReleasePixelFormat(pix);
          CGLReleaseContext(ctx);
          return 0;
      }
    EOS
    system ENV.cc, "test.c", "-L#{lib}", "-I#{include}/epoxy", "-lepoxy", "-framework", "OpenGL", "-o", "test"
    system "./test"
  end
end
