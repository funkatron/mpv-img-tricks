"""Allow ``python -m mpv_img_tricks``."""

from __future__ import annotations

import sys

from mpv_img_tricks.cli import main

if __name__ == "__main__":
    sys.exit(main())
