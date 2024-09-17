"""Bungeegum: Android in memory execution toolkit"""

try:
    from _version import __version__
except ImportError:
    try:
        from ._version import __version__
    except ImportError:
        __version__ = "unknown"
