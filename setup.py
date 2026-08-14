"""Purpose: copy the PeTTa runtime into wheels built from pyproject.toml.
Owns:
  - build_py_with_runtime writes only beneath setuptools' build directory;
    the wheel gate builds and boots that copy outside the checkout
    [source .github/workflows/checks.yml:116]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import shutil
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py

HERE = Path(__file__).resolve().parent

# Runtime resources living outside the package that must ship inside the wheel,
# mapped to their destination under petta/_runtime/ (preserving the src/ and
# lib/ sibling layout that metta.pl relies on for library_path).
RUNTIME_RESOURCES = {
    "src": "src",
    "lib": "lib",
    "python/helper.pl": "python/helper.pl",
    "python/petta/shim.pl": "python/petta/shim.pl",
}


class build_py_with_runtime(build_py):
    """Build Python modules, then copy the runtime tree beside them."""

    def run(self):
        super().run()
        runtime_root = Path(self.build_lib) / "petta" / "_runtime"
        for src_rel, dst_rel in RUNTIME_RESOURCES.items():
            src = HERE / src_rel
            dst = runtime_root / dst_rel
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)


setup(
    cmdclass={"build_py": build_py_with_runtime},
)
