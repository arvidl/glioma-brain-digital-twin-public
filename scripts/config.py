"""
Centralized path configuration for the Finse 2026 glioma digital twin project.

Usage
-----
>>> from scripts.config import REPO_ROOT, BIDS_ROOT
>>> print(BIDS_ROOT / "participants.tsv")
"""

from __future__ import annotations

import os
from pathlib import Path


def _find_repo_root() -> Path:
    """Locate repository root by walking up from CWD until pyproject.toml is found."""
    env = os.environ.get("FINSE_REPO_ROOT")
    if env:
        return Path(env).resolve()

    p = Path.cwd().resolve()
    for _ in range(10):
        if (p / "pyproject.toml").exists() and (p / "notebooks").is_dir():
            return p
        if p == p.parent:
            break
        p = p.parent

    return Path(__file__).resolve().parent.parent


REPO_ROOT: Path = _find_repo_root()
DATA_ROOT: Path = REPO_ROOT / "data"
BIDS_ROOT: Path = DATA_ROOT / "BIDS_preop_postop"
DERIVATIVES_ROOT: Path = BIDS_ROOT / "derivatives"

SUBJECTS: list[str] = ["PAT16"]
SESSIONS: list[str] = ["preop", "postop"]
