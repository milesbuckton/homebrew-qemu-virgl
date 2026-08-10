class LibepoxyAngle < Formula
  desc "Library for handling OpenGL function pointer management"
  homepage "https://github.com/anholt/libepoxy"
  url "https://github.com/anholt/libepoxy.git",
      revision: "e98617e62e74a835d4e403cd270afaf296afe839",
      using: :git
  version "2025.03.08.1"
  license "MIT"

  bottle do
    root_url "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
    rebuild 1
    sha256 cellar: :any, arm64_tahoe: "9021d8b6ccdd3c003f04239c2ffcbef5c76d750f8cf0e9a29519d1da6eb19432"
    sha256 cellar: :any, tahoe:       "9883c52cb9b520225dff532563eb949391d6fabda17d02e045ff25ab2cb3e594"
  end

  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.13" => :build
  depends_on "milesbuckton/qemu-virgl/libangle"

  # keg_only: this tap intentionally replaces the standard `libepoxy` and both
  # ship headers at include/epoxy/*. Installing ours into /opt/homebrew would
  # collide with the standard formula (pulled in transitively by qemu-virgl).
  # Consumers find it via the explicit -I/-L and PKG_CONFIG_PATH set in the
  # qemu-virgl/virglrenderer formulae.
  keg_only :provided_by_macos_or_another_formula

  # Waiting for upstreaming of https://github.com/akihikodaki/libepoxy/tree/macos
  patch :p1 do
    url "https://raw.githubusercontent.com/milesbuckton/homebrew-qemu-virgl/refs/heads/main/Patches/libepoxy-v03.diff"
    sha256 "24abc33e17b37a1fa28925c52b93d9c07e8ec5bb488edda2b86492be979c1fc4"
  end

  def install
    mkdir "build" do
      system "meson", *std_meson_args,
             "-Dc_args=-I#{Formula["milesbuckton/qemu-virgl/libangle"].opt_prefix}/include",
             "-Dc_link_args=-L#{Formula["milesbuckton/qemu-virgl/libangle"].opt_prefix}/lib",
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
    system "ls", "-lh", "test"
    system "file", "test"
    system "./test"
  end
end
