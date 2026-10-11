"""
bids_utils.py
─────────────
Helpers for loading and querying a BIDS dataset using pybids.

Usage
-----
>>> from scripts.utils.bids_utils import load_bids_layout, get_t1w_path
>>> layout = load_bids_layout("data/BIDS_preop_postop")
>>> t1 = get_t1w_path(layout, subject="PAT16", session="preop")
"""

from __future__ import annotations
from pathlib import Path
from typing import Optional

try:
    from bids import BIDSLayout
except ImportError:
    raise ImportError("pybids is required: pip install pybids")


# ─── Layout ──────────────────────────────────────────────────────────────────

def load_bids_layout(bids_root: str | Path, validate: bool = False) -> "BIDSLayout":
    """Load a BIDS dataset.

    Parameters
    ----------
    bids_root : str | Path
        Path to BIDS dataset root (contains dataset_description.json).
    validate : bool
        Run pybids validation (slow; off by default).

    Returns
    -------
    BIDSLayout
    """
    bids_root = Path(bids_root).resolve()
    if not (bids_root / "dataset_description.json").exists():
        raise FileNotFoundError(f"No dataset_description.json found in {bids_root}")
    layout = BIDSLayout(str(bids_root), validate=validate)
    return layout


def bids_summary(layout: "BIDSLayout") -> dict:
    """Return a summary dict of the BIDS dataset."""
    subjects  = layout.get_subjects()
    sessions  = layout.get_sessions()
    datatypes = layout.get_datatypes()
    tasks     = layout.get_tasks()
    return {
        "subjects":  subjects,
        "sessions":  sessions,
        "datatypes": datatypes,
        "tasks":     tasks,
        "n_subjects": len(subjects),
        "n_sessions": len(sessions),
    }


# ─── Path helpers ─────────────────────────────────────────────────────────────

def get_t1w_path(
    layout: "BIDSLayout",
    subject: str,
    session: Optional[str] = None,
    return_json: bool = False,
) -> Path | tuple[Path, Path]:
    """Return path to T1w NIfTI (and optionally its JSON sidecar)."""
    filters = dict(subject=subject, suffix="T1w", extension=".nii.gz")
    if session:
        filters["session"] = session
    files = layout.get(**filters)
    if not files:
        raise FileNotFoundError(f"No T1w found for sub-{subject} ses-{session}")
    nii_path = Path(files[0].path)
    if return_json:
        json_path = nii_path.with_suffix("").with_suffix(".json")
        return nii_path, json_path
    return nii_path


def get_bold_path(
    layout: "BIDSLayout",
    subject: str,
    session: Optional[str] = None,
    task: str = "rest",
    return_json: bool = False,
) -> Path | tuple[Path, Path]:
    """Return path to BOLD fMRI NIfTI."""
    filters = dict(subject=subject, suffix="bold", task=task, extension=".nii.gz")
    if session:
        filters["session"] = session
    files = layout.get(**filters)
    if not files:
        raise FileNotFoundError(f"No BOLD found for sub-{subject} ses-{session} task-{task}")
    nii_path = Path(files[0].path)
    if return_json:
        json_path = nii_path.with_suffix("").with_suffix(".json")
        return nii_path, json_path
    return nii_path


def get_dwi_paths(
    layout: "BIDSLayout",
    subject: str,
    session: Optional[str] = None,
    acq: Optional[str] = None,
) -> dict[str, Path]:
    """Return dict with paths to DWI NIfTI, bval, bvec, and JSON.

    Parameters
    ----------
    acq : str | None
        Acquisition label, e.g. 'AP' or 'PA'.
    """
    filters = dict(subject=subject, suffix="dwi", extension=".nii.gz")
    if session:
        filters["session"] = session
    if acq:
        filters["acquisition"] = acq
    files = layout.get(**filters)
    if not files:
        raise FileNotFoundError(f"No DWI found for sub-{subject} ses-{session} acq-{acq}")
    nii_path = Path(files[0].path)
    stem = nii_path.with_suffix("").with_suffix("")  # strip .nii.gz
    return {
        "nii":  nii_path,
        "bval": stem.with_suffix(".bval"),
        "bvec": stem.with_suffix(".bvec"),
        "json": stem.with_suffix(".json"),
    }


def get_participants_df(layout: "BIDSLayout"):
    """Return participants.tsv as a pandas DataFrame."""
    import pandas as pd
    tsv = Path(layout.root) / "participants.tsv"
    if not tsv.exists():
        raise FileNotFoundError(f"participants.tsv not found in {layout.root}")
    return pd.read_csv(tsv, sep="\t")


# ─── Derivatives helpers ──────────────────────────────────────────────────────

def get_tvb_paths(bids_root: str | Path, subject: str, session: str) -> dict[str, Path]:
    """Return paths to TVB derivative files (SC, FC, HRF, ROIts)."""
    base = Path(bids_root) / "derivatives" / "TVB" / f"sub-{subject}" / f"ses-{session}"
    if not base.exists():
        raise FileNotFoundError(f"TVB derivatives not found: {base}")
    return {
        "SC":       base / "SC.zip",
        "SCthrAn":  base / "SCthrAn.mat",
        "FC":       base / "FC.mat",
        "HRF":      base / "HRF.csv",
        "ROIts":    base / "ROIts.dat",
    }


def get_tumor_mask_paths(
    bids_root: str | Path, subject: str, space: str = "T1"
) -> Path:
    """Return path to tumor mask (space='T1' or 'MNI')."""
    base = Path(bids_root) / "derivatives" / "tumor_masks" / f"sub-{subject}" / "anat"
    fname = f"sub-{subject}_space_{space}_label-tumor.nii.gz"
    p = base / fname
    if not p.exists():
        raise FileNotFoundError(f"Tumor mask not found: {p}")
    return p


def get_rshrf_paths(bids_root: str | Path, subject: str) -> dict[str, Path]:
    """Return dict of rsHRF parameter map paths (Height, FWHM, Time2peak)."""
    base = Path(bids_root) / "derivatives" / "rsHRF" / f"sub-{subject}"
    maps = {}
    for param in ("Height", "FWHM", "Time2peak"):
        files = list(base.glob(f"*{param}*.nii.gz"))
        if files:
            maps[param] = files  # may have multiple sessions
    return maps
