__version__ = "unknown"
try:
    from _version import __version__
except ImportError:
    from ._version import __version__
finally:
    pass
