"""
mri_utils.py
────────────
MRI image loading, resampling, and basic visualisation helpers.

Usage
-----
>>> from scripts.utils.mri_utils import load_nifti, plot_anat_with_overlay
>>> img, data, affine = load_nifti("sub-PAT16_T1w.nii.gz")
"""

from __future__ import annotations
from pathlib import Path
from typing import Optional, Sequence, Tuple

import numpy as np

try:
    import nibabel as nib
except ImportError:
    raise ImportError("nibabel is required: pip install nibabel")

try:
    import matplotlib.pyplot as plt
    import matplotlib.gridspec as gridspec
except ImportError:
    raise ImportError("matplotlib is required")


# ─── I/O ─────────────────────────────────────────────────────────────────────

def load_nifti(path: str | Path) -> Tuple[nib.Nifti1Image, np.ndarray, np.ndarray]:
    """Load a NIfTI file and return (img, data, affine).

    Returns
    -------
    img    : nibabel NIfTI image object
    data   : numpy array of voxel values
    affine : 4×4 affine matrix (voxel-to-world)
    """
    img = nib.load(str(path))
    return img, np.asarray(img.dataobj), img.affine


def save_nifti(data: np.ndarray, affine: np.ndarray, path: str | Path) -> None:
    """Save a numpy array as NIfTI."""
    img = nib.Nifti1Image(data.astype(np.float32), affine)
    nib.save(img, str(path))


def get_affine(path: str | Path) -> np.ndarray:
    """Return the affine of a NIfTI without loading the full data."""
    return nib.load(str(path)).affine


def get_voxel_size(path: str | Path) -> np.ndarray:
    """Return voxel size in mm."""
    return nib.load(str(path)).header.get_zooms()[:3]


# ─── Resampling / masking ─────────────────────────────────────────────────────

def resample_to_target(
    source_path: str | Path,
    target_path: str | Path,
    interpolation: str = "linear",
) -> nib.Nifti1Image:
    """Resample source image to the voxel grid of target image.

    Uses nilearn.image.resample_to_img.
    interpolation : 'linear' | 'nearest' | 'continuous'
    """
    try:
        from nilearn.image import resample_to_img
    except ImportError:
        raise ImportError("nilearn is required for resampling")
    return resample_to_img(str(source_path), str(target_path), interpolation=interpolation)


def apply_mask(img: nib.Nifti1Image, mask_img: nib.Nifti1Image) -> np.ndarray:
    """Apply a binary mask and return 1-D masked voxel array."""
    try:
        from nilearn.masking import apply_mask as _apply_mask
    except ImportError:
        raise ImportError("nilearn is required")
    return _apply_mask(img, mask_img)


# ─── rsHRF parameter maps ────────────────────────────────────────────────────

_RSHRF_PARAMS = ("FWHM", "Height", "Time2peak")


def load_rshrf_maps(
    bids_root: str | Path,
    subject: str,
    session: str,
    params: Sequence[str] = _RSHRF_PARAMS,
) -> dict[str, Tuple[np.ndarray, np.ndarray]]:
    """Load rsHRF parameter NIfTI maps.

    Returns dict mapping param name -> (data_array, affine).
    """
    rsHRF_dir = (
        Path(bids_root) / "derivatives" / "rsHRF" / f"sub-{subject}"
    )
    prefix = f"sub-{subject}_ses-{session}_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold"
    result = {}
    for param in params:
        p = rsHRF_dir / f"{prefix}_{param}.nii.gz"
        if p.exists():
            img = nib.load(str(p))
            result[param] = (np.asarray(img.dataobj), img.affine)
    return result


def load_tumor_mask(
    bids_root: str | Path,
    subject: str,
    space: str = "MNI",
) -> Tuple[np.ndarray, np.ndarray]:
    """Load a binary tumor mask.

    Parameters
    ----------
    space : 'MNI' or 'T1'

    Returns (mask_data, affine).
    """
    p = (
        Path(bids_root) / "derivatives" / "tumor_masks"
        / f"sub-{subject}" / "anat"
        / f"sub-{subject}_space_{space}_label-tumor.nii.gz"
    )
    img = nib.load(str(p))
    return np.asarray(img.dataobj), img.affine


# ─── Diffusion helpers ────────────────────────────────────────────────────────

def load_bvals_bvecs(
    bval_path: str | Path, bvec_path: str | Path
) -> Tuple[np.ndarray, np.ndarray]:
    """Load b-values and b-vectors using dipy."""
    try:
        from dipy.io import read_bvals_bvecs
    except ImportError:
        raise ImportError("dipy is required: pip install dipy")
    bvals, bvecs = read_bvals_bvecs(str(bval_path), str(bvec_path))
    return bvals, bvecs


def compute_dti_metrics(
    dwi_path: str | Path,
    bval_path: str | Path,
    bvec_path: str | Path,
    mask_path: Optional[str | Path] = None,
) -> dict[str, np.ndarray]:
    """Fit a DTI model and return FA, MD, AD, RD maps.

    Returns
    -------
    dict with keys 'FA', 'MD', 'AD', 'RD'  (all in image space)
    """
    from dipy.io.image import load_nifti as dipy_load
    from dipy.io import read_bvals_bvecs
    from dipy.core.gradients import gradient_table
    from dipy.reconst.dti import TensorModel

    data, affine = dipy_load(str(dwi_path))
    bvals, bvecs = read_bvals_bvecs(str(bval_path), str(bvec_path))
    gtab = gradient_table(bvals, bvecs)

    mask = None
    if mask_path:
        mask, _ = dipy_load(str(mask_path))
        mask = mask.astype(bool)

    model = TensorModel(gtab)
    fit   = model.fit(data, mask=mask)

    return {
        "FA": fit.fa,
        "MD": fit.md,
        "AD": fit.ad,
        "RD": fit.rd,
    }


# ─── Visualisation ────────────────────────────────────────────────────────────

def plot_anat_slices(
    anat_path: str | Path,
    n_cuts: int = 5,
    display_mode: str = "ortho",
    title: str = "",
    figsize: tuple = (14, 4),
) -> plt.Figure:
    """Plot anatomy slices using nilearn.plotting.

    display_mode : 'ortho' | 'x' | 'y' | 'z' | 'mosaic'
    """
    try:
        from nilearn import plotting
    except ImportError:
        raise ImportError("nilearn is required")

    fig, ax = plt.subplots(1, 1, figsize=figsize)
    display = plotting.plot_anat(
        str(anat_path),
        display_mode=display_mode,
        cut_coords=n_cuts if display_mode != "ortho" else None,
        title=title,
        axes=ax,
        annotate=True,
        draw_cross=False,
    )
    return fig


def plot_anat_with_overlay(
    anat_path: str | Path,
    overlay_path: str | Path,
    threshold: float = 0.1,
    colorbar: bool = True,
    title: str = "",
    cmap: str = "hot",
    alpha: float = 0.8,
    figsize: tuple = (14, 4),
) -> plt.Figure:
    """Overlay a statistical or segmentation map on anatomy."""
    try:
        from nilearn import plotting
    except ImportError:
        raise ImportError("nilearn is required")

    fig, ax = plt.subplots(1, 1, figsize=figsize)
    plotting.plot_roi(
        str(overlay_path),
        bg_img=str(anat_path),
        title=title,
        colorbar=colorbar,
        cmap=cmap,
        alpha=alpha,
        axes=ax,
    )
    return fig


def plot_dti_metrics(
    metrics: dict[str, np.ndarray],
    affine: np.ndarray,
    slice_idx: Optional[int] = None,
    figsize: tuple = (14, 4),
) -> plt.Figure:
    """Plot FA, MD, AD, RD maps side by side at a given axial slice."""
    keys   = [k for k in ("FA", "MD", "AD", "RD") if k in metrics]
    cmaps  = {"FA": "inferno", "MD": "viridis", "AD": "plasma", "RD": "magma"}
    limits = {"FA": (0, 1), "MD": (0, 3e-3), "AD": (0, 3e-3), "RD": (0, 2e-3)}

    fig, axes = plt.subplots(1, len(keys), figsize=figsize)
    for ax, key in zip(axes, keys):
        vol = metrics[key]
        s   = vol.shape[2] // 2 if slice_idx is None else slice_idx
        im  = ax.imshow(vol[:, :, s].T, origin="lower",
                        cmap=cmaps[key], vmin=limits[key][0], vmax=limits[key][1])
        ax.set_title(key, fontsize=12, fontweight="bold")
        ax.axis("off")
        plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    return fig
