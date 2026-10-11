"""
Pytest configuration and shared fixtures for Finse 2026 test suite.
"""

import os
from pathlib import Path

import pytest


def _find_repo_root() -> Path:
    """Walk up from CWD to find the repository root (contains pyproject.toml)."""
    p = Path(__file__).resolve().parent
    for _ in range(10):
        if (p / "pyproject.toml").exists():
            return p
        if p == p.parent:
            break
        p = p.parent
    return Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def bids_root():
    """Return the BIDS dataset root path."""
    default = _find_repo_root() / "data" / "BIDS_preop_postop"
    return Path(os.environ.get("FINSE_BIDS_ROOT", str(default)))


@pytest.fixture(scope="session")
def data_exists(bids_root):
    """Check if BIDS dataset exists."""
    return bids_root.exists()


@pytest.fixture(scope="session")
def subject_ids():
    """Return list of subject IDs in the study."""
    return ["PAT16"]


@pytest.fixture(scope="session")
def bids_layout(bids_root, data_exists):
    """Return a BIDSLayout instance if dataset exists, else None."""
    if not data_exists:
        return None

    try:
        from bids import BIDSLayout

        layout = BIDSLayout(str(bids_root), validate=False)
        return layout
    except Exception as e:
        pytest.skip(f"Could not initialize BIDSLayout: {e}")


@pytest.fixture
def synthetic_nifti_path(tmp_path):
    """
    Create a synthetic NIfTI file for testing.
    Returns path to a small 3D NIfTI image.
    """
    import nibabel as nib
    import numpy as np

    # Create 10x10x10 random data
    data = np.random.randn(10, 10, 10).astype(np.float32)

    # Identity affine
    affine = np.eye(4)
    affine[0, 3] = -4.5  # center
    affine[1, 3] = -4.5
    affine[2, 3] = -4.5

    img = nib.Nifti1Image(data, affine)
    fpath = tmp_path / "synthetic.nii.gz"
    nib.save(img, fpath)

    return fpath
