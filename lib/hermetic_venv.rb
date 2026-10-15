# typed: false
# frozen_string_literal: true

# Build a Python virtualenv that never touches the network.
#
# Homebrew builds are expected to be hermetic: `deny_network_access!` is used by
# homebrew-core's qemu formula, and a formula that fetches during `install` is
# not. `deny_network_access!` is what actually enforces it (it fails the build),
# not `brew audit` — audit does not detect network access. A bare `pip install
# .` of an sdist violates that: a Python 3.12+ venv ships no setuptools, so pip
# builds the package in an isolated environment and downloads the build backend
# from PyPI.
#
# The approach here is to install the build backend from a pinned, checksummed
# `py3-none-any` wheel resource into a local wheelhouse, then install the real
# packages with `--no-index --no-build-isolation`:
#
#   * `--no-index` makes pip refuse PyPI outright, so a missing file is a hard
#     error rather than a silent network fetch.
#   * `--no-build-isolation` makes pip use the setuptools already installed in
#     the venv instead of provisioning its own.
#   * `--no-deps` keeps pip from resolving dependencies over the network; the
#     formulae install every runtime dependency as its own resource.
#
# Mixed into a Formula that declares `setuptools` and `wheel` resources.
module HermeticVenv
  # The interpreter `brew` links into the venv's bin.
  PYTHON = "python@3.14"

  # Create a venv at `path`, install the build backend from the given resource
  # names, and return the venv's interpreter.
  def hermetic_venv(path, build_backend)
    venv_python = path/"bin/python"
    # Derive the versioned binary name from PYTHON (Homebrew's python@3.x kegs
    # ship only python3.x in bin; the unversioned names live in libexec/bin),
    # so bumping the constant above updates both.
    python_bin = formula_opt_bin(PYTHON)/"python#{Formula[PYTHON].version.major_minor}"
    system python_bin, "-m", "venv", path

    wheelhouse = path/"wheelhouse"
    wheelhouse.mkpath
    build_backend.each do |name|
      resource(name).stage { wheelhouse.install Dir["*"] }
    end

    # --no-index is the load-bearing part: it turns a missing wheel into a
    # build failure instead of a silent download.
    system venv_python, "-m", "pip", "install",
           "--no-index", "--find-links", wheelhouse, *build_backend
    venv_python
  end

  # Install the named sdist resource into the venv.
  def hermetic_pip_install(venv_python, sdist)
    resource(sdist).stage do
      system venv_python, "-m", "pip", "install",
             "--no-index", "--no-build-isolation", "--no-deps", "."
    end
  end

  # Where the venv's pure-Python packages live.
  #
  # Ask `sysconfig` rather than hardcoding `lib/python3.14/site-packages`, so
  # bumping the `PYTHON` constant above cannot silently drop everything the
  # formula put on `PYTHONPATH`.
  def venv_site_packages(venv_python)
    Pathname.new(
      Utils.safe_popen_read(venv_python.to_s, "-c",
                            "import sysconfig; print(sysconfig.get_paths()['purelib'])").strip,
    )
  end
end
