#!/usr/bin/env bash
# =============================================================================
# create_postop_masks.sh -- Generate post-operative cavity and perilesional masks
# Glioma Brain Digital Twin
# =============================================================================
#
# For brain mechanics FE modeling, the post-operative brain requires distinct
# material property assignments for (a) the CSF-filled resection cavity and
# (b) the perilesional zone (edema, gliosis, altered tissue around the cavity).
#
# Method:
#   1. Load the existing cavity ROI mask (from register_longitudinal.sh,
#      based on dilated pre-op tumor prior)
#   2. Load the post-op T1w and post-op FreeSurfer aparc+aseg
#   3. Compute a CSF intensity threshold from ventricular voxels (label 4, 43)
#   4. Within the cavity ROI, classify voxels:
#      - CSF-like intensity (below ventricle p75) -> resection cavity
#      - Tissue-like intensity (above threshold)  -> perilesional zone
#   5. Morphological cleanup: fill holes, remove small components
#   6. Save separate binary masks in native T1w space
#
# Prerequisites:
#   - Completed longitudinal registration (register_longitudinal.sh)
#   - Post-op FreeSurfer recon-all-clinical segmentation
#   - conda environment with nibabel, numpy, scipy (e.g. finse26)
#
# Usage:
#   conda activate finse26
#   bash scripts/create_postop_masks.sh [--subject SUB]
#
# Outputs (per subject, in derivatives/registered_t1w/sub-{SUB}/longitudinal/):
#   cavity_csf.nii.gz        -- Binary mask of CSF-filled resection cavity
#   perilesional.nii.gz      -- Binary mask of perilesional zone
#   postop_masks_report.txt  -- Volume summary and threshold info
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop"
DERIV_DIR="${PROJECT_DIR}/derivatives"
FILTER_SUBJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) FILTER_SUBJECT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/create_postop_masks.sh [--subject SUB]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SUBJECTS="PAT16"
if [[ -n "${FILTER_SUBJECT}" ]]; then
    SUBJECTS="${FILTER_SUBJECT}"
fi

echo "============================================================"
echo " Create Post-operative Cavity & Perilesional Masks"
echo "============================================================"
echo ""

for SUB in ${SUBJECTS}; do
    echo "────────────────────────────────────────────────────────────"
    echo "  sub-${SUB}"
    echo "────────────────────────────────────────────────────────────"

    LONG_DIR="${DERIV_DIR}/registered_t1w/sub-${SUB}/longitudinal"
    CAVITY_ROI="${LONG_DIR}/cavity_mask_postop.nii.gz"
    T1W="${BIDS_DIR}/sub-${SUB}/ses-postop/anat/sub-${SUB}_ses-postop_T1w.nii.gz"
    ASEG="${DERIV_DIR}/freesurfer/sub-${SUB}_ses-postop/mri/aparc+aseg.mgz"

    OUT_CAVITY="${LONG_DIR}/cavity_csf.nii.gz"
    OUT_PERI="${LONG_DIR}/perilesional.nii.gz"
    OUT_REPORT="${LONG_DIR}/postop_masks_report.txt"

    # Check prerequisites
    for f in "${CAVITY_ROI}" "${T1W}" "${ASEG}"; do
        if [[ ! -f "${f}" ]]; then
            echo "  SKIP: missing ${f}"
            continue 2
        fi
    done

    python << PYEOF
import sys
import numpy as np
import nibabel as nib
from nibabel.processing import resample_from_to
from scipy import ndimage

t1w_img = nib.load("${T1W}")
t1w = t1w_img.get_fdata()
vox_vol = float(np.abs(np.linalg.det(t1w_img.affine[:3, :3])))

# Load cavity ROI (from longitudinal registration, tumor-prior based)
cav_roi_img = nib.load("${CAVITY_ROI}")
cav_roi = np.asarray(cav_roi_img.dataobj) > 0.5

# Load post-op aparc+aseg and resample to T1w grid
aseg_img = nib.load("${ASEG}")
aseg_in_t1w = resample_from_to(aseg_img, t1w_img, order=0)
aseg = np.asarray(aseg_in_t1w.dataobj).astype(int)

# Ventricular CSF reference intensity (labels 4=L-Lat-Vent, 43=R-Lat-Vent)
vent_mask = np.isin(aseg, [4, 43])
vent_vals = t1w[vent_mask]
if len(vent_vals) < 100:
    print("  ERROR: too few ventricle voxels for intensity reference")
    sys.exit(1)

csf_threshold = float(np.percentile(vent_vals, 75))
vent_median = float(np.median(vent_vals))

# Step 1: Seed cavity voxels within the tumor-prior ROI
cavity_seeds = cav_roi & (t1w <= csf_threshold) & (t1w > 0)

# Also include SynthSeg-labeled CSF within the ROI
synthseg_csf_in_roi = cav_roi & (aseg == 24) & (t1w <= csf_threshold * 1.2)
cavity_seeds = cavity_seeds | synthseg_csf_in_roi

# Step 2: Expand search — dilate ROI by ~5mm to catch CSF voxels just
# outside the tumor-prior boundary (the cavity may extend beyond the
# pre-op tumor footprint due to surgical margins and brain shift)
mean_vox = float(np.abs(np.diag(t1w_img.affine[:3, :3])).mean())
dilate_vox = max(1, int(round(5.0 / mean_vox)))
expanded_roi = ndimage.binary_dilation(cav_roi, iterations=dilate_vox)

# All CSF-like voxels in the expanded region
csf_in_expanded = expanded_roi & (t1w > 0) & (t1w <= csf_threshold)

# Step 3: Keep only CSF voxels connected to the original seeds
# (prevents picking up distant CSF like ventricles or sulci)
combined = (csf_in_expanded | cavity_seeds).astype(np.uint8)
labeled, n_comp = ndimage.label(combined)
seed_labels = set(np.unique(labeled[cavity_seeds])) - {0}
cavity_csf = np.zeros_like(combined, dtype=np.uint8)
for lbl in seed_labels:
    cavity_csf[labeled == lbl] = 1

# Step 4: Fill holes (no closing — closing over-expands the cavity)
cavity_csf = ndimage.binary_fill_holes(cavity_csf).astype(np.uint8)

# Step 5: Perilesional = ROI voxels that are tissue-like, excluding cavity
perilesional = (cav_roi & (t1w > csf_threshold) & ~cavity_csf.astype(bool)).astype(np.uint8)
perilesional = ndimage.binary_fill_holes(perilesional).astype(np.uint8)

# Remove small components (< 0.5 cm³) from both masks
min_voxels = int(np.ceil(0.5 * 1000.0 / vox_vol))
for mask_name, mask_data in [("cavity_csf", cavity_csf), ("perilesional", perilesional)]:
    lab, nc = ndimage.label(mask_data)
    for cid in range(1, nc + 1):
        if int((lab == cid).sum()) < min_voxels:
            mask_data[lab == cid] = 0
    if mask_name == "cavity_csf":
        cavity_csf = mask_data
    else:
        perilesional = mask_data

# Volume calculations
n_cav = int(cavity_csf.sum())
n_peri = int(perilesional.sum())
vol_cav = n_cav * vox_vol / 1000.0
vol_peri = n_peri * vox_vol / 1000.0
vol_roi = int(cav_roi.sum()) * vox_vol / 1000.0

# Intensity stats within each zone
cav_intensities = t1w[cavity_csf > 0] if n_cav > 0 else np.array([0])
peri_intensities = t1w[perilesional > 0] if n_peri > 0 else np.array([0])

report = f"""Post-operative Mask Report: sub-${SUB}
{'='*50}
Cavity ROI (tumor prior):  {vol_roi:.1f} cm³
Ventricle CSF reference:   median={vent_median:.0f}, p75={csf_threshold:.0f}
CSF intensity threshold:   {csf_threshold:.0f}

Resection cavity (CSF):    {n_cav} voxels, {vol_cav:.1f} cm³
  T1w intensity:           mean={cav_intensities.mean():.0f}, median={np.median(cav_intensities):.0f}
Perilesional zone:         {n_peri} voxels, {vol_peri:.1f} cm³
  T1w intensity:           mean={peri_intensities.mean():.0f}, median={np.median(peri_intensities):.0f}

Cavity/ROI ratio:          {vol_cav/vol_roi*100:.1f}%
"""

print(report)

# Save masks
for data, path in [(cavity_csf, "${OUT_CAVITY}"), (perilesional, "${OUT_PERI}")]:
    out_img = nib.Nifti1Image(data.astype(np.uint8), t1w_img.affine, t1w_img.header)
    out_img.header.set_data_dtype(np.uint8)
    nib.save(out_img, path)

# Save report
with open("${OUT_REPORT}", "w") as f:
    f.write(report)

print(f"  Saved: cavity_csf.nii.gz ({vol_cav:.1f} cm³)")
print(f"  Saved: perilesional.nii.gz ({vol_peri:.1f} cm³)")
print(f"  Saved: postop_masks_report.txt")
PYEOF

    echo ""
done

echo "============================================================"
echo " Post-op masks complete."
echo "============================================================"
echo ""
echo " Freeview QC:"
echo "   freeview \\"
echo "     data/BIDS_preop_postop/sub-PAT16/ses-postop/anat/sub-PAT16_ses-postop_T1w.nii.gz \\"
echo "     derivatives/registered_t1w/sub-PAT16/longitudinal/cavity_csf.nii.gz:colormap=heat:opacity=0.5 \\"
echo "     derivatives/registered_t1w/sub-PAT16/longitudinal/perilesional.nii.gz:colormap=jet:opacity=0.3"
echo ""
