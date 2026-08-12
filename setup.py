"""Purpose: package the petta and pettorch Python libraries with the PeTTa
runtime bundled, so pip install petta needs no separate checkout and no
PETTA_PATH; petta[torch] adds the PyTorch integration's dependency.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import os
import shutil

from setuptools import setup
from setuptools.command.build_py import build_py

HERE = os.path.abspath(os.path.dirname(__file__))

# Runtime resources living outside the package that must ship inside the wheel,
# mapped to their destination under petta/_runtime/ (preserving the src/ and
# lib/ sibling layout that metta.pl relies on for library_path).
RUNTIME_RESOURCES = {
    "src": "src",
    "lib": "lib",
    os.path.join("python", "helper.pl"): os.path.join("python", "helper.pl"),
    os.path.join("python", "petta", "shim.pl"): os.path.join("python", "petta", "shim.pl"),
}


class build_py_with_runtime(build_py):
    def run(self):
        super().run()
        runtime_root = os.path.join(self.build_lib, "petta", "_runtime")
        for src_rel, dst_rel in RUNTIME_RESOURCES.items():
            src = os.path.join(HERE, src_rel)
            dst = os.path.join(runtime_root, dst_rel)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)


setup(
    name="petta",
    version="0.2.0",
    packages=["petta", "petta.integrations", "pettorch"],
    package_dir={"": "python"},
    package_data={"petta": ["shim.pl"]},
    include_package_data=True,
    cmdclass={"build_py": build_py_with_runtime},
    entry_points={"console_scripts": ["petta=petta.cli:main"]},
    install_requires=[
        "janus-swi",
    ],
    extras_require={
        # PyTorch builds differ by hardware; the extra names the dependency
        # and leaves the build choice with the installer.
        "torch": ["torch", "array-api-compat"],
        "test": ["pytest", "hypothesis"],
        "arrays": ["array-api-compat"],
    },
    description="MeTTa in Python on the PeTTa engine, with a deep PyTorch integration",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    url="https://github.com/trueagi-io/PeTTa",
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Prolog",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Intended Audience :: Science/Research",
    ],
    python_requires=">=3.10",
)
