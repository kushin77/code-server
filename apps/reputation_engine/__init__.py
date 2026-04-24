#!/usr/bin/env python3
# @file apps/reputation-engine/__init__.py
# @module reputation-engine

import os
import sys

_package_dir = os.path.dirname(__file__)
if _package_dir not in sys.path:
    sys.path.insert(0, _package_dir)

__version__ = "1.0.0"
