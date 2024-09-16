import os
from setuptools import setup

# Retrieve the version from an environment variable
VERSION = os.environ.get("VERSION")
FRIDA_VERSION = os.environ.get("FRIDA_VERSION")

setup(
    name="bungeegum",
    version=VERSION,
    author="Zetier",
    description="Tool for executing an ELF or shellcode from within the context of an Android app",
    install_requires=[
        "frida==" + FRIDA_VERSION,
        "adbutils==1.2.*",
        "importlib-resources==5.12.*",
    ],
    python_requires=">=3.10",
    classifiers=[
        "Intended Audience :: Developers",
        "License :: OSI Approved :: GNU General Public License v2 (GPLv2)",
        "Natural Language :: English",
        "Programming Language :: Python :: 3.10",
    ],
    keywords=["bungeegum", "android", "testing"],
    packages=["bungeegum"],
    package_dir={"bungeegum": "src/bungeegum"},
    package_data={"bungeegum": ["*.js", "*.apk"]},
    entry_points={"console_scripts": ["bungeegum = bungeegum.bg:main"]},
)
