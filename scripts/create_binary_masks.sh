#!/usr/bin/env bash
# =============================================================================
# create_binary_masks.sh -- Standardize Aerts probabilistic tumor masks
# Glioma Brain Digital Twin
# =============================================================================
#
# Converts the Aerts et al. probabilistic tumor masks (Gaussian-smoothed,
# values 0–~1.2) into clean binary masks by thresholding at p > 0.5 and
# applying morphological cleanup (fill holes, remove small components).
#
# This ensures all downstream consumers use consistent binary masks rather
# than ad-hoc thresholding scattered across scripts and notebooks.
#
# Input:  derivatives/tumor_masks/sub-{SUB}/anat/sub-{SUB}_space_{SPACE}_label-tumor.nii.gz
# Output: derivatives/tumor_masks/sub-{SUB}/anat/sub-{SUB}_space_{SPACE}_label-tumor_binary.nii.gz
#
# Usage:
#   conda activate finse26
#   bash scripts/create_binary_masks.sh [--threshold T] [--min-volume V]
#
# Options:
#   --threshold T    Probability threshold (default: 0.5)
#   --min-volume V   Minimum component volume in cm³ to keep (default: 1.0)
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MASKS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop/derivatives/tumor_masks"

THRESHOLD=0.5
MIN_VOLUME=1.0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --min-volume) MIN_VOLUME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/create_binary_masks.sh [--threshold T] [--min-volume V]"
            echo "  --threshold T    Probability threshold (default: 0.5)"
            echo "  --min-volume V   Min component volume in cm³ (default: 1.0)"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "============================================================"
echo " Create Standardized Binary Tumor Masks"
echo "============================================================"
echo " Source:    ${MASKS_DIR}"
echo " Threshold: p > ${THRESHOLD}"
echo " Min volume: ${MIN_VOLUME} cm³"
echo "============================================================"
echo ""

python << PYEOF
import sys
import os
import glob
import numpy as np
import nibabel as nib
from scipy import ndimage

masks_dir = "${MASKS_DIR}"
threshold = ${THRESHOLD}
min_vol_cm3 = ${MIN_VOLUME}

prob_files = sorted(glob.glob(os.path.join(masks_dir, "sub-*/anat/*_label-tumor.nii.gz")))

# Exclude already-binarized files
prob_files = [f for f in prob_files if "_binary" not in f]

if not prob_files:
    print("ERROR: No probabilistic tumor masks found.")
    sys.exit(1)

print(f"Found {len(prob_files)} probabilistic mask(s)\n")

for prob_path in prob_files:
    basename = os.path.basename(prob_path)
    out_name = basename.replace("_label-tumor.nii.gz", "_label-tumor_binary.nii.gz")
    out_path = os.path.join(os.path.dirname(prob_path), out_name)

    print(f"  {basename}")

    img = nib.load(prob_path)
    prob = np.asarray(img.dataobj, dtype=np.float32)

    # Threshold
    binary = (prob > threshold).astype(np.uint8)

    # Fill holes
    binary = ndimage.binary_fill_holes(binary).astype(np.uint8)

    # Remove small connected components
    vox_vol = float(np.abs(np.linalg.det(img.affine[:3, :3])))
    min_voxels = int(np.ceil(min_vol_cm3 * 1000.0 / vox_vol))

    labeled, n_components = ndimage.label(binary)
    for comp_id in range(1, n_components + 1):
        comp_size = int((labeled == comp_id).sum())
        if comp_size < min_voxels:
            binary[labeled == comp_id] = 0
            print(f"    Removed component {comp_id}: {comp_size} voxels "
                  f"({comp_size * vox_vol / 1000.0:.2f} cm³ < {min_vol_cm3} cm³)")

    # Summary
    n_voxels = int(binary.sum())
    vol_cm3 = n_voxels * vox_vol / 1000.0

    # Probability stats within the binary mask
    if n_voxels > 0:
        masked_prob = prob[binary > 0]
        p_mean = float(masked_prob.mean())
        p_min = float(masked_prob.min())
        p_max = float(masked_prob.max())
        print(f"    -> {n_voxels} voxels, {vol_cm3:.1f} cm³")
        print(f"       Probability within mask: mean={p_mean:.3f}, min={p_min:.3f}, max={p_max:.3f}")
    else:
        print(f"    -> WARNING: empty mask after thresholding!")

    out_img = nib.Nifti1Image(binary, img.affine, img.header)
    out_img.header.set_data_dtype(np.uint8)
    nib.save(out_img, out_path)
    print(f"    Saved: {out_name}")
    print()

print("Done.")
PYEOF

echo ""
echo "Binary masks created.  Downstream consumers should use *_label-tumor_binary.nii.gz"
echo ""
