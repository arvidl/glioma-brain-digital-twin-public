#!/usr/bin/env python3
"""
compute_fc.py
─────────────
Compute functional connectivity (FC) matrices from fMRIPrep BOLD outputs
and aparc+aseg parcellation (Desikan-Killiany atlas).

Usage
-----
python scripts/compute_fc.py --subject PAT16 --project-dir .
python scripts/compute_fc.py --subject PAT16 --session preop --project-dir .
"""

import argparse
import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from scipy import signal

try:
    from nilearn.image import resample_to_img
except ImportError:
    resample_to_img = None

# ── Desikan-Killiany ROI definitions ─────────────────────────────────────────

DK_CORTICAL = {
    1001: "L-bankssts", 1002: "L-caudalanteriorcingulate",
    1003: "L-caudalmiddlefrontal", 1005: "L-cuneus",
    1006: "L-entorhinal", 1007: "L-fusiform",
    1008: "L-inferiorparietal", 1009: "L-inferiortemporal",
    1010: "L-isthmuscingulate", 1011: "L-lateraloccipital",
    1012: "L-lateralorbitofrontal", 1013: "L-lingual",
    1014: "L-medialorbitofrontal", 1015: "L-middletemporal",
    1016: "L-parahippocampal", 1017: "L-paracentral",
    1018: "L-parsopercularis", 1019: "L-parsorbitalis",
    1020: "L-parstriangularis", 1021: "L-pericalcarine",
    1022: "L-postcentral", 1023: "L-posteriorcingulate",
    1024: "L-precentral", 1025: "L-precuneus",
    1026: "L-rostralanteriorcingulate", 1027: "L-rostralmiddlefrontal",
    1028: "L-superiorfrontal", 1029: "L-superiorparietal",
    1030: "L-superiortemporal", 1031: "L-supramarginal",
    1032: "L-frontalpole", 1033: "L-temporalpole",
    1034: "L-transversetemporal", 1035: "L-insula",
}
DK_CORTICAL.update(
    {k + 1000: name.replace("L-", "R-") for k, name in list(DK_CORTICAL.items())}
)

DK_SUBCORTICAL = {
    10: "L-Thalamus", 11: "L-Caudate", 12: "L-Putamen",
    13: "L-Pallidum", 17: "L-Hippocampus", 18: "L-Amygdala",
    26: "L-Accumbens",
    49: "R-Thalamus", 50: "R-Caudate", 51: "R-Putamen",
    52: "R-Pallidum", 53: "R-Hippocampus", 54: "R-Amygdala",
    58: "R-Accumbens",
}

ALL_ROIS = {**DK_CORTICAL, **DK_SUBCORTICAL}

CONFOUND_COLS = [
    "trans_x", "trans_y", "trans_z", "rot_x", "rot_y", "rot_z",
    "trans_x_derivative1", "trans_y_derivative1", "trans_z_derivative1",
    "rot_x_derivative1", "rot_y_derivative1", "rot_z_derivative1",
    "a_comp_cor_00", "a_comp_cor_01", "a_comp_cor_02",
    "a_comp_cor_03", "a_comp_cor_04",
    "cosine00", "cosine01", "cosine02",
]


# ── Core functions ───────────────────────────────────────────────────────────

def load_bold_and_confounds(fmriprep_dir, sub, ses):
    func_dir = fmriprep_dir / f"sub-{sub}" / f"ses-{ses}" / "func"
    bold_files = sorted(func_dir.glob("*_space-T1w_desc-preproc_bold.nii.gz"))
    conf_files = sorted(func_dir.glob("*_desc-confounds_timeseries.tsv"))
    json_files = sorted(func_dir.glob("*_space-T1w_desc-preproc_bold.json"))

    if not bold_files:
        return None, None, None

    bold_img = nib.load(str(bold_files[0]))
    confounds = pd.read_csv(str(conf_files[0]), sep="\t") if conf_files else None

    tr = None
    if json_files:
        with open(json_files[0]) as f:
            tr = json.load(f).get("RepetitionTime")

    return bold_img, confounds, tr


def extract_roi_timeseries(bold_img, aparc_img, roi_labels, min_voxels=10):
    bold_data = np.asarray(bold_img.dataobj)
    aparc_data = np.asarray(aparc_img.dataobj).astype(int)

    # Resample parcellation to BOLD grid if shapes differ
    if aparc_data.shape[:3] != bold_data.shape[:3]:
        if resample_to_img is None:
            raise RuntimeError("nilearn required for grid resampling (pip install nilearn)")
        print(f"  Resampling aparc+aseg {aparc_img.shape} -> BOLD {bold_img.shape[:3]}")
        aparc_resampled = resample_to_img(aparc_img, nib.Nifti1Image(
            bold_data[..., 0], bold_img.affine), interpolation="nearest")
        aparc_data = np.asarray(aparc_resampled.dataobj).astype(int)

    n_vols = bold_data.shape[3]
    roi_ids = sorted(roi_labels.keys())
    roi_names = [roi_labels[r] for r in roi_ids]
    ts = np.full((n_vols, len(roi_ids)), np.nan)
    valid = []

    for i, roi_id in enumerate(roi_ids):
        mask = aparc_data == roi_id
        if mask.sum() >= min_voxels:
            ts[:, i] = bold_data[mask].mean(axis=0)
            valid.append(i)

    return ts, roi_names, valid


def clean_timeseries(ts, confounds, tr, valid_rois,
                     bandpass=(0.01, 0.1), fd_thresh=0.5):
    available_cols = [c for c in CONFOUND_COLS if c in confounds.columns]
    X = confounds[available_cols].fillna(0).values

    ts_clean = ts.copy()
    for i in valid_rois:
        y = ts[:, i]
        if np.isnan(y).any():
            continue
        X_design = np.column_stack([X, np.ones(len(y))])
        beta = np.linalg.lstsq(X_design, y, rcond=None)[0]
        residual = y - X_design @ beta

        if tr and bandpass:
            nyq = 0.5 / tr
            low, high = bandpass[0] / nyq, min(bandpass[1] / nyq, 0.99)
            if low < high:
                b, a = signal.butter(3, [low, high], btype="band")
                residual = signal.filtfilt(b, a, residual)

        ts_clean[:, i] = residual

    n_scrubbed = 0
    if "framewise_displacement" in confounds.columns:
        fd = confounds["framewise_displacement"].fillna(0).values
        bad = fd > fd_thresh
        n_scrubbed = int(bad.sum())
        ts_clean[bad, :] = np.nan

    return ts_clean, n_scrubbed


def compute_fc(ts_clean, valid_rois):
    good_tps = ~np.any(np.isnan(ts_clean[:, valid_rois]), axis=1)
    ts_good = ts_clean[good_tps][:, valid_rois]

    if ts_good.shape[0] < 30:
        print(f"  WARNING: only {ts_good.shape[0]} clean volumes -- too few for FC")
        return None, None

    fc = np.corrcoef(ts_good.T)
    np.fill_diagonal(fc, 0)
    fc_z = np.arctanh(np.clip(fc, -0.999, 0.999))
    return fc, fc_z


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--session", default=None, help="preop, postop, or omit for both")
    parser.add_argument("--project-dir", required=True, type=Path)
    args = parser.parse_args()

    project = args.project_dir.resolve()
    fmriprep_dir = project / "derivatives" / "fmriprep"
    reg_dir = project / "derivatives" / "registered_t1w"
    conn_dir = project / "derivatives" / "connectivity"

    sessions = [args.session] if args.session else ["preop", "postop"]
    sub = args.subject

    print("=" * 60)
    print(f" Functional Connectivity: sub-{sub}")
    print("=" * 60)

    for ses in sessions:
        print(f"\n--- ses-{ses} ---")

        bold_img, confounds, tr = load_bold_and_confounds(fmriprep_dir, sub, ses)
        if bold_img is None:
            print("  BOLD not found, skipping")
            continue

        aparc_path = reg_dir / f"sub-{sub}" / f"ses-{ses}" / "aparc+aseg_space-T1w.nii.gz"
        if not aparc_path.exists():
            print(f"  aparc+aseg not found: {aparc_path}")
            continue

        aparc_img = nib.load(str(aparc_path))
        print(f"  BOLD: {bold_img.shape}, TR={tr}s")
        print(f"  aparc+aseg: {aparc_img.shape}")
        print(f"  Confounds: {len(confounds.columns)} columns")

        # Extract ROI time series
        ts, names, valid = extract_roi_timeseries(bold_img, aparc_img, ALL_ROIS)
        print(f"  ROIs with data: {len(valid)}/{len(ALL_ROIS)}")
        print(f"  Timepoints: {ts.shape[0]}")

        # Clean time series
        ts_clean, n_scrub = clean_timeseries(ts, confounds, tr, valid)
        print(f"  Scrubbed volumes (FD > 0.5mm): {n_scrub}/{ts.shape[0]}")

        # Compute FC
        fc, fc_z = compute_fc(ts_clean, valid)
        if fc is None:
            continue

        valid_names = [names[i] for i in valid]
        print(f"  FC matrix: {fc.shape}")
        print(f"  FC range: [{fc.min():.3f}, {fc.max():.3f}]")
        print(f"  Mean |FC|: {np.abs(fc).mean():.3f}")

        # Save
        out_dir = conn_dir / f"sub-{sub}" / f"ses-{ses}"
        out_dir.mkdir(parents=True, exist_ok=True)

        np.save(out_dir / "fc_pearson.npy", fc)
        np.save(out_dir / "fc_fisher_z.npy", fc_z)
        np.save(out_dir / "roi_timeseries.npy", ts_clean[:, valid])
        with open(out_dir / "fc_roi_names.json", "w") as f:
            json.dump(valid_names, f, indent=2)

        print(f"  Saved to: {out_dir}")

    print("\n" + "=" * 60)
    print(" FC computation complete")
    print("=" * 60)


if __name__ == "__main__":
    main()
