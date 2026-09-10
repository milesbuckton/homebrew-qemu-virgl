class Gn < Formula
  desc "Meta-build system that generates build files for Ninja"
  homepage "https://gn.googlesource.com/gn"
  url "https://gn.googlesource.com/gn.git",
      branch: "main"
  version "master"
  license "BSD-3-Clause"

  depends_on "ninja" => :build
  depends_on "python@3.14" => :build

  def install
    python3 = formula_opt_bin("python@3.14")/"python3.14"
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
