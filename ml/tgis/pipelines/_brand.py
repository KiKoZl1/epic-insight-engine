from __future__ import annotations

import os

DEFAULT_BRAND_NAME = "UEFNToolkit"
DEFAULT_CANONICAL_DOMAIN = "uefntoolkit.com"
DEFAULT_OPENROUTER_REFERER = f"https://{DEFAULT_CANONICAL_DOMAIN}"
DEFAULT_OPENROUTER_TITLE = f"{DEFAULT_BRAND_NAME}-TGIS"


def openrouter_referer() -> str:
    return (os.getenv("OPENROUTER_REFERER", DEFAULT_OPENROUTER_REFERER) or DEFAULT_OPENROUTER_REFERER).strip()


def openrouter_title() -> str:
    return (os.getenv("OPENROUTER_TITLE", DEFAULT_OPENROUTER_TITLE) or DEFAULT_OPENROUTER_TITLE).strip()
