class Gn < Formula
  desc "Meta-build system that generates build files for Ninja"
  homepage "https://gn.googlesource.com/gn"
  url "https://gn.googlesource.com/gn.git",
      branch: "main"
  version "main"
  license "BSD-3-Clause"

  depends_on "ninja" => :build
  depends_on "python@3.14" => :build

  # gen.py + ninja build only the `gn` target (the cipd-backed targets are
  # excluded), so the build is fully offline. Enforce it.
  deny_network_access!

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
    # `gn format` prints nothing on its own stream (no status message, no
    # quiet flag); it reports only failures. So it cannot be asserted on output
    # — the assertion must be on the file. Round-trip: an already-formatted
    # file must come back byte-identical, which proves the binary linked, ran,
    # parsed the source and re-emitted it unchanged. Any real formatting
    # change (or a parse failure) turns this into a mismatch.
    system bin/"gn", "format", "test.gn"
    assert_equal (testpath/"test.gn").read, "print(\"Hello from gn\")\n"
  end
end
