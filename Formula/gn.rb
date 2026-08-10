class Gn < Formula
  desc "Meta-build system that generates build files for Ninja"
  homepage "https://gn.googlesource.com/gn"
  url "https://gn.googlesource.com/gn.git",
      branch: "main"
  version "2025.11.24"
  license "BSD-3-Clause"

  depends_on "ninja" => :build
  depends_on "python@3.13" => :build

  def install
    python3 = Formula["python@3.13"].opt_bin/"python3.13"
    system python3, "build/gen.py"
    # Build only the `gn` target, not the default target set: the default set
    # includes check_formatter, which shells out to `cipd` (absent on GitHub
    # runners) and fails the build.
    system "ninja", "-C", "out", "gn"
    bin.install "out/gn"
  end

  test do
    (testpath/"test.gn").write <<~EOS
      print("Hello from gn")
    EOS
    system bin/"gn", "format", "test.gn"
  end
end
