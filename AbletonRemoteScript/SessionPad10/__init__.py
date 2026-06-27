# __init__.py
# Required for Ableton Live to recognize this directory as a Remote Script package.
# Live calls create_instance() from this module.

from __future__ import absolute_import, division

from .SessionPad import create_instance

__all__ = ["create_instance"]
