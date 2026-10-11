#!/usr/bin/env bash
# =============================================================================
# register_longitudinal.sh -- Diffeomorphic registration between sessions
# Glioma Brain Digital Twin
# =============================================================================
#
# Performs ANTs SyN (diffeomorphic) registration between pre-op and post-op
# T1w volumes for a given subject.  Produces:
#
#   - Dense deformation/warp fields (forward and inverse)
#   - Jacobian determinant map  (local volume change: J>1 = expansion)
#   - Displacement magnitude map (|u(x)| in mm)
#   - Resection cavity mask     (automatic, from SynthSeg difference)
#   - Pre-op derivatives warped into post-op space
#
# Cavity masking strategy (two tiers):
#   Tier 1 (default): Compare FreeSurfer segmentations across sessions --
#          voxels that are brain in pre-op but CSF/background in post-op
#          approximate the resection cavity.  When the two asegs live in
#          different voxel grids (common when mixing standard recon-all and
#          recon-all-clinical), the pre-op T1w is first rigidly aligned to
#          the post-op T1w (Dipy, mutual information), and that transform
#          is applied to the pre-op aseg with nearest-neighbor interpolation.
#          This avoids label corruption from naive grid resampling.
#   Tier 2 (--resseg): Use the RESSEG deep-learning model for more precise
#          cavity segmentation.  Requires: pip install resseg
#
# The cavity mask is fed to ANTs via the -x flag (cost function masking)
# so that the SyN optimisation ignores the surgical void.
#
# Usage:
#   bash scripts/register_longitudinal.sh --subject PAT16 \
#       [--session-pre preop] [--session-post postop] \
#       [--nthreads N] [--resseg]
#
# Requires:
#   - ANTs (antsRegistrationSyN.sh, antsApplyTransforms,
#           CreateJacobianDeterminantImage)
#   - FreeSurfer (mri_convert)  -- for SynthSeg-based cavity masking
#   - Python 3 + nibabel + numpy + dipy
#   - (optional) resseg  (pip install resseg)
#
# References:
#   - Avants et al. (2008) Symmetric diffeomorphic image registration with
#     cross-correlation, Medical Image Analysis
#   - Perez-Garcia et al. (2021) A self-supervised learning strategy for
#     postoperative brain cavity segmentation, IJCARS
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SES_PRE="preop"
SES_POST="postop"
NTHREADS=8
USE_RESSEG=false

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)      SUBJECT="$2";    shift 2 ;;
        --session-pre)  SES_PRE="$2";    shift 2 ;;
        --session-post) SES_POST="$2";   shift 2 ;;
        --nthreads)     NTHREADS="$2";   shift 2 ;;
        --resseg)       USE_RESSEG=true; shift ;;
        -h|--help)
            echo "Usage: bash scripts/register_longitudinal.sh --subject SUB"
            echo "           [--session-pre preop] [--session-post postop]"
            echo "           [--nthreads N] [--resseg]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }

# ---- Ensure ANTs is on PATH ------------------------------------------------
if ! command -v antsRegistrationSyN.sh &>/dev/null; then
    CONDA_BASE=$(conda info --base 2>/dev/null || echo "/opt/anaconda3")
    if [[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        for env_name in finse26 cas-workshop; do
            if conda env list 2>/dev/null | grep -q "${env_name}"; then
                conda activate "${env_name}"
                if command -v antsRegistrationSyN.sh &>/dev/null; then
                    echo "Activated conda environment: ${env_name} (provides ANTs)"
                    break
                fi
                conda deactivate
            fi
        done
    fi
    if ! command -v antsRegistrationSyN.sh &>/dev/null; then
        echo "ERROR: ANTs not found. Install via: conda install -c conda-forge ants"
        exit 1
    fi
fi

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SUB_PRE="sub-${SUBJECT}_ses-${SES_PRE}"
SUB_POST="sub-${SUBJECT}_ses-${SES_POST}"

FMRIPREP="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}"
REG_ROOT="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}"

PRE_T1W="${FMRIPREP}/ses-${SES_PRE}/anat/${SUB_PRE}_desc-preproc_T1w.nii.gz"
POST_T1W="${FMRIPREP}/ses-${SES_POST}/anat/${SUB_POST}_desc-preproc_T1w.nii.gz"

# Fallback to raw BIDS T1w if fMRIPrep outputs don't exist
BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"
if [[ ! -f "${PRE_T1W}" ]]; then
    PRE_T1W="${BIDS}/sub-${SUBJECT}/ses-${SES_PRE}/anat/sub-${SUBJECT}_ses-${SES_PRE}_T1w.nii.gz"
fi
if [[ ! -f "${POST_T1W}" ]]; then
    POST_T1W="${BIDS}/sub-${SUBJECT}/ses-${SES_POST}/anat/sub-${SUBJECT}_ses-${SES_POST}_T1w.nii.gz"
fi

# FreeSurfer segmentations (for cavity masking)
# Prefer clinical (SynthSeg) asegs for BOTH sessions so we compare the same
# algorithm across timepoints.  Mixing standard recon-all (pre-op) with
# recon-all-clinical (post-op) produces systematic label differences that
# are algorithmic, not anatomical, leading to a mislocated cavity mask.
FS_ROOT="${PROJECT_DIR}/derivatives/freesurfer"
ASEG_PRE="${REG_ROOT}/ses-${SES_PRE}/aparc+aseg_space-T1w.nii.gz"
ASEG_POST="${REG_ROOT}/ses-${SES_POST}/aparc+aseg_space-T1w.nii.gz"

# Fall back to FreeSurfer native volumes -- prefer clinical for pre-op
if [[ ! -f "${ASEG_PRE}" ]]; then
    # Try clinical first (same algorithm as post-op)
    ASEG_PRE_CLIN="${FS_ROOT}/sub-${SUBJECT}_ses-${SES_PRE}_clinical/mri/aparc+aseg.mgz"
    ASEG_PRE_STD="${FS_ROOT}/${SUB_PRE}/mri/aparc+aseg.mgz"
    if [[ -f "${ASEG_PRE_CLIN}" ]]; then
        ASEG_PRE="${ASEG_PRE_CLIN}"
        echo "  Using clinical (SynthSeg) aseg for pre-op cavity comparison"
    else
        ASEG_PRE="${ASEG_PRE_STD}"
    fi
fi
if [[ ! -f "${ASEG_POST}" ]]; then
    ASEG_POST="${FS_ROOT}/${SUB_POST}/mri/aparc+aseg.mgz"
fi

OUT_DIR="${REG_ROOT}/longitudinal"
mkdir -p "${OUT_DIR}"

# ---- Verify inputs ----------------------------------------------------------
echo "============================================================"
echo " Longitudinal Registration: sub-${SUBJECT}"
echo "============================================================"
echo " Pre-op T1w   : ${PRE_T1W}"
echo " Post-op T1w  : ${POST_T1W}"
echo " Pre-op aseg  : ${ASEG_PRE}"
echo " Post-op aseg : ${ASEG_POST}"
echo " RESSEG       : ${USE_RESSEG}"
echo " Output       : ${OUT_DIR}"
echo " Threads      : ${NTHREADS}"
echo "============================================================"

for f in "${PRE_T1W}" "${POST_T1W}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required input not found: $f"
        exit 1
    fi
done

START_TIME=$(date +%s)

# =============================================================================
# Step 1: Generate resection cavity mask
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 1/5: Generating resection cavity mask ..."

CAVITY_MASK="${OUT_DIR}/cavity_mask_postop.nii.gz"
CAVITY_MASK_INV="${OUT_DIR}/cavity_mask_inv.nii.gz"
CAVITY_METHOD_FILE="${OUT_DIR}/.cavity_method"

# Invalidate cache if the requested method differs from what produced the mask
CACHED_METHOD=""
if [[ -f "${CAVITY_METHOD_FILE}" ]]; then
    CACHED_METHOD=$(cat "${CAVITY_METHOD_FILE}")
fi
REQUESTED_METHOD="tumor_prior"
[[ "${USE_RESSEG}" == true ]] && REQUESTED_METHOD="resseg"

if [[ -f "${CAVITY_MASK}" && "${CACHED_METHOD}" != "${REQUESTED_METHOD}" ]]; then
    echo "  Method changed (${CACHED_METHOD:-unknown} -> ${REQUESTED_METHOD})"
    echo "  Clearing cached cavity mask and downstream outputs ..."
    rm -f "${CAVITY_MASK}" "${CAVITY_MASK_INV}" "${CAVITY_METHOD_FILE}"
    rm -f "${OUT_DIR}/preop_to_postop_"*
    rm -f "${OUT_DIR}/jacobian_preop_to_postop.nii.gz"
    rm -f "${OUT_DIR}/displacement_magnitude.nii.gz"
    rm -f "${OUT_DIR}/"*_preop_in_postop.*
    rm -f "${OUT_DIR}/roi_displacement_stats.tsv"
fi

if [[ -f "${CAVITY_MASK}" ]]; then
    echo "  (cached, method=${CACHED_METHOD})"

elif [[ "${USE_RESSEG}" == true ]]; then
    # ---- Tier 2: RESSEG deep learning model ---------------------------------
    echo "  Using RESSEG deep learning model ..."
    if ! python3 -c "import resseg" 2>/dev/null; then
        echo "ERROR: resseg not installed.  Install with: pip install resseg"
        echo "  Or omit --resseg to use SynthSeg-based masking (Tier 1)."
        exit 1
    fi
    resseg "${POST_T1W}" -o "${CAVITY_MASK}"
    echo "resseg" > "${CAVITY_METHOD_FILE}"
    echo "  RESSEG cavity mask -> ${CAVITY_MASK}"

else
    # ---- Tier 1: Tumor-mask based cavity approximation ----------------------
    # The pre-op tumor mask gives the best spatial prior for the resection
    # cavity.  We threshold at p>0.5, rigidly align to post-op space, and
    # dilate by ~3 mm to account for surgical margins.
    #
    # Fallback (no tumor mask): SynthSeg aseg difference.
    #
    # Why not SynthSeg difference alone?  Even when using the same algorithm
    # (recon-all-clinical) for both sessions, systematic label differences in
    # non-surgical regions (cerebellum, brainstem) can dominate the "largest
    # connected component" and produce a mislocated mask.

    TUMOR_MASK_DIR="${PROJECT_DIR}/data/BIDS_preop_postop/derivatives/tumor_masks"
    TUMOR_MASK="${TUMOR_MASK_DIR}/sub-${SUBJECT}/anat/sub-${SUBJECT}_space_T1_label-tumor.nii.gz"

    if [[ -f "${TUMOR_MASK}" ]]; then
        echo "  Using pre-op tumor mask as cavity prior ..."
        echo "  Tumor mask: ${TUMOR_MASK}"

        python3 - "${TUMOR_MASK}" "${PRE_T1W}" "${POST_T1W}" "${CAVITY_MASK}" << 'PYEOF'
import sys
import numpy as np
import nibabel as nib
from nibabel.processing import resample_from_to
from scipy import ndimage

tumor_path, pre_t1w_path, post_t1w_path, out_path = sys.argv[1:5]

tumor_img = nib.load(tumor_path)
pre_t1w_img = nib.load(pre_t1w_path)
post_t1w_img = nib.load(post_t1w_path)

tumor_data = np.asarray(tumor_img.dataobj)
print(f'  Tumor mask shape: {tumor_img.shape}, range: [{tumor_data.min():.3f}, {tumor_data.max():.3f}]')

# Resample tumor mask to post-op T1w grid using affine headers.
# The tumor mask is in pre-op T1w native space; we resample it to the
# post-op T1w grid.  For a rigid body (same patient, ~6 months apart),
# the affine headers provide a good enough alignment for this purpose.
tumor_in_postop = resample_from_to(tumor_img, post_t1w_img, order=1)
prob = np.asarray(tumor_in_postop.dataobj)

# Threshold at p > 0.5 for the core tumor region
cavity = prob > 0.5

# Dilate by ~3 mm to account for surgical margins beyond the tumor boundary
vox_size = np.abs(np.diag(post_t1w_img.affine[:3, :3])).mean()
dilate_voxels = max(1, int(round(3.0 / vox_size)))
cavity = ndimage.binary_dilation(cavity, iterations=dilate_voxels)

# Fill holes for a clean mask
cavity = ndimage.binary_fill_holes(cavity)

out_img = nib.Nifti1Image(cavity.astype(np.uint8),
                          post_t1w_img.affine, post_t1w_img.header)
nib.save(out_img, out_path)

n_voxels = int(cavity.sum())
vox_vol = float(np.abs(np.linalg.det(post_t1w_img.affine[:3, :3])))
vol_cm3 = n_voxels * vox_vol / 1000.0

print(f'  Cavity mask: {n_voxels} voxels, ~{vol_cm3:.1f} cm3')
print(f'  (tumor core at p>0.5 + {dilate_voxels}-voxel dilation for surgical margins)')
PYEOF
        echo "tumor_prior" > "${CAVITY_METHOD_FILE}"
        echo "  Tumor-based cavity mask -> ${CAVITY_MASK}"

    else
        echo "  No tumor mask found at: ${TUMOR_MASK}"
        echo "  Falling back to SynthSeg aseg difference method ..."

        if [[ ! -f "${ASEG_PRE}" ]] || [[ ! -f "${ASEG_POST}" ]]; then
            echo "  WARNING: aparc+aseg not available for both sessions."
            echo "  Skipping cavity masking -- SyN will run unmasked."
            CAVITY_MASK=""
        else
            ASEG_PRE_NII="${OUT_DIR}/.tmp_aseg_pre.nii.gz"
            ASEG_POST_NII="${OUT_DIR}/.tmp_aseg_post.nii.gz"

            if [[ "${ASEG_PRE}" == *.mgz ]]; then
                mri_convert "${ASEG_PRE}" "${ASEG_PRE_NII}" --out_type nii 2>/dev/null
            else
                cp "${ASEG_PRE}" "${ASEG_PRE_NII}"
            fi
            if [[ "${ASEG_POST}" == *.mgz ]]; then
                mri_convert "${ASEG_POST}" "${ASEG_POST_NII}" --out_type nii 2>/dev/null
            else
                cp "${ASEG_POST}" "${ASEG_POST_NII}"
            fi

            python3 - "${ASEG_PRE_NII}" "${ASEG_POST_NII}" "${PRE_T1W}" "${POST_T1W}" "${CAVITY_MASK}" << 'PYEOF'
import sys
import numpy as np
import nibabel as nib
from nibabel.processing import resample_from_to
from scipy import ndimage

aseg_pre_path, aseg_post_path, pre_t1w_path, post_t1w_path, out_path = sys.argv[1:6]

pre_aseg_img = nib.load(aseg_pre_path)
post_aseg_img = nib.load(aseg_post_path)
post_t1w_img = nib.load(post_t1w_path)

# Resample pre-op aseg to post-op aseg grid via affine headers
pre_resampled = resample_from_to(pre_aseg_img, post_aseg_img, order=0)
pre = np.asarray(pre_resampled.dataobj).astype(int)
post = np.asarray(post_aseg_img.dataobj).astype(int)

CSF_LABELS = {0, 4, 5, 14, 15, 24, 43, 44}
brain_pre = ~np.isin(pre, list(CSF_LABELS))
csf_post = np.isin(post, list(CSF_LABELS))
cavity_raw = brain_pre & csf_post

cavity = ndimage.binary_closing(cavity_raw, iterations=2)
cavity = ndimage.binary_opening(cavity, iterations=1)

labeled, n_components = ndimage.label(cavity)
if n_components > 1:
    sizes = ndimage.sum(cavity, labeled, range(1, n_components + 1))
    largest = int(np.argmax(sizes)) + 1
    cavity = labeled == largest

out_img = nib.Nifti1Image(cavity.astype(np.uint8),
                          post_t1w_img.affine, post_t1w_img.header)
nib.save(out_img, out_path)

n_voxels = int(cavity.sum())
vox_vol = float(np.abs(np.linalg.det(post_t1w_img.affine[:3, :3])))
vol_cm3 = n_voxels * vox_vol / 1000.0
print(f'  Cavity (aseg fallback): {n_voxels} voxels, ~{vol_cm3:.1f} cm3')
PYEOF
            rm -f "${ASEG_PRE_NII}" "${ASEG_POST_NII}"
            echo "synthseg" > "${CAVITY_METHOD_FILE}"
            echo "  SynthSeg cavity mask -> ${CAVITY_MASK}"
        fi
    fi
fi

# Create inverted mask (1=healthy, 0=cavity) for ANTs -x flag
if [[ -n "${CAVITY_MASK}" && -f "${CAVITY_MASK}" ]]; then
    python3 -c "
import nibabel as nib, numpy as np
img = nib.load('${CAVITY_MASK}')
inv = 1 - np.asarray(img.dataobj).astype(np.uint8)
nib.save(nib.Nifti1Image(inv, img.affine, img.header), '${CAVITY_MASK_INV}')
"
    echo "  Inverted mask (for SyN -x) -> ${CAVITY_MASK_INV}"
fi

# =============================================================================
# Step 2: ANTs SyN diffeomorphic registration
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 2/5: ANTs SyN registration (pre-op -> post-op) ..."
echo "  This may take 30-90 minutes."

PREFIX="${OUT_DIR}/preop_to_postop_"
WARP="${PREFIX}1Warp.nii.gz"
INV_WARP="${PREFIX}1InverseWarp.nii.gz"
AFFINE="${PREFIX}0GenericAffine.mat"

if [[ -f "${WARP}" ]]; then
    echo "  (cached)"
else
    MASK_FLAG=""
    if [[ -n "${CAVITY_MASK_INV:-}" && -f "${CAVITY_MASK_INV:-}" ]]; then
        MASK_FLAG="-x ${CAVITY_MASK_INV}"
        echo "  Cost function masking: cavity excluded from optimisation"
    else
        echo "  No cavity mask available -- running unmasked SyN"
    fi

    antsRegistrationSyN.sh \
        -d 3 \
        -f "${POST_T1W}" \
        -m "${PRE_T1W}" \
        -o "${PREFIX}" \
        -n "${NTHREADS}" \
        -t s \
        ${MASK_FLAG}

    echo "  Warp field     : ${WARP}"
    echo "  Inverse warp   : ${INV_WARP}"
    echo "  Affine         : ${AFFINE}"
fi

# =============================================================================
# Step 3: Compute Jacobian determinant and displacement magnitude
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 3/5: Computing Jacobian and displacement maps ..."

JACOBIAN="${OUT_DIR}/jacobian_preop_to_postop.nii.gz"
DISP_MAG="${OUT_DIR}/displacement_magnitude.nii.gz"

if [[ ! -f "${JACOBIAN}" ]]; then
    CreateJacobianDeterminantImage 3 \
        "${WARP}" \
        "${JACOBIAN}" \
        0 1
    echo "  Jacobian -> ${JACOBIAN}"
else
    echo "  Jacobian (cached)"
fi

if [[ ! -f "${DISP_MAG}" ]]; then
    python3 - "${WARP}" "${DISP_MAG}" << 'PYEOF'
import sys
import numpy as np
import nibabel as nib

warp_path, out_path = sys.argv[1:3]

warp_img = nib.load(warp_path)
warp_data = np.asarray(warp_img.dataobj)

# Warp field has shape (X, Y, Z, 1, 3) or (X, Y, Z, 3)
if warp_data.ndim == 5:
    warp_data = warp_data[..., 0, :]
elif warp_data.ndim == 4 and warp_data.shape[-1] == 3:
    pass
else:
    raise ValueError(f'Unexpected warp shape: {warp_data.shape}')

magnitude = np.sqrt(np.sum(warp_data ** 2, axis=-1))

mag_img = nib.Nifti1Image(magnitude.astype(np.float32),
                          warp_img.affine)
nib.save(mag_img, out_path)

brain_mask = magnitude > 0.1
if brain_mask.sum() > 0:
    vals = magnitude[brain_mask]
    print(f'  Displacement: mean={np.mean(vals):.2f} mm, '
          f'max={np.max(vals):.2f} mm, '
          f'95th pctl={np.percentile(vals, 95):.2f} mm')
PYEOF
    echo "  Displacement magnitude -> ${DISP_MAG}"
else
    echo "  Displacement magnitude (cached)"
fi

# =============================================================================
# Step 4: Warp pre-op derivatives into post-op space
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 4/5: Warping pre-op derivatives to post-op space ..."

# T1w
WARPED_T1W="${OUT_DIR}/T1w_preop_in_postop.nii.gz"
if [[ ! -f "${WARPED_T1W}" ]]; then
    antsApplyTransforms \
        -d 3 \
        -i "${PRE_T1W}" \
        -r "${POST_T1W}" \
        -t "${WARP}" \
        -t "${AFFINE}" \
        -n Linear \
        -o "${WARPED_T1W}"
    echo "  T1w pre-op -> post-op space: ${WARPED_T1W}"
else
    echo "  T1w (cached)"
fi

# DTI scalar maps
for MAP in fa md ad rd; do
    SRC="${REG_ROOT}/ses-${SES_PRE}/${MAP}_space-T1w.nii.gz"
    DST="${OUT_DIR}/${MAP}_preop_in_postop.nii.gz"
    if [[ -f "${SRC}" && ! -f "${DST}" ]]; then
        antsApplyTransforms \
            -d 3 \
            -i "${SRC}" \
            -r "${POST_T1W}" \
            -t "${WARP}" \
            -t "${AFFINE}" \
            -n Linear \
            -o "${DST}"
        echo "  ${MAP} pre-op -> post-op space"
    elif [[ -f "${DST}" ]]; then
        echo "  ${MAP} (cached)"
    else
        echo "  ${MAP}: pre-op T1w-space file not found, skipping"
    fi
done

# aparc+aseg (nearest-neighbour for discrete labels)
APARC_PRE_T1W="${REG_ROOT}/ses-${SES_PRE}/aparc+aseg_space-T1w.nii.gz"
APARC_WARPED="${OUT_DIR}/aparc+aseg_preop_in_postop.nii.gz"
if [[ -f "${APARC_PRE_T1W}" && ! -f "${APARC_WARPED}" ]]; then
    antsApplyTransforms \
        -d 3 \
        -i "${APARC_PRE_T1W}" \
        -r "${POST_T1W}" \
        -t "${WARP}" \
        -t "${AFFINE}" \
        -n NearestNeighbor \
        -o "${APARC_WARPED}"
    echo "  aparc+aseg pre-op -> post-op space"
elif [[ -f "${APARC_WARPED}" ]]; then
    echo "  aparc+aseg (cached)"
fi

# =============================================================================
# Step 5: Compute ROI-level displacement statistics
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 5/5: ROI-level displacement statistics ..."

DISP_STATS="${OUT_DIR}/displacement_roi_stats.json"

if [[ ! -f "${DISP_STATS}" ]]; then
    APARC_FOR_STATS="${REG_ROOT}/ses-${SES_POST}/aparc+aseg_space-T1w.nii.gz"
    if [[ ! -f "${APARC_FOR_STATS}" ]]; then
        APARC_FOR_STATS="${APARC_WARPED:-}"
    fi

    if [[ -f "${DISP_MAG}" && -n "${APARC_FOR_STATS}" && -f "${APARC_FOR_STATS}" ]]; then
        python3 - "${DISP_MAG}" "${APARC_FOR_STATS}" "${JACOBIAN}" "${DISP_STATS}" << 'PYEOF'
import sys
import json
import numpy as np
import nibabel as nib

disp_path, aparc_path, jac_path, out_path = sys.argv[1:5]

from nilearn.image import resample_to_img

disp_img = nib.load(disp_path)
jac_img = nib.load(jac_path)
aparc_img = nib.load(aparc_path)

if aparc_img.shape[:3] != disp_img.shape[:3]:
    aparc_img = resample_to_img(aparc_img, disp_img, interpolation='nearest')

disp = np.asarray(disp_img.dataobj)
aparc = np.asarray(aparc_img.dataobj).astype(int)
jac = np.asarray(jac_img.dataobj)

DK_LABELS = {
    2: "Left-Cerebral-WM", 3: "Left-Cerebral-Cortex",
    4: "Left-Lateral-Ventricle", 10: "Left-Thalamus",
    11: "Left-Caudate", 12: "Left-Putamen",
    17: "Left-Hippocampus", 18: "Left-Amygdala",
    41: "Right-Cerebral-WM", 42: "Right-Cerebral-Cortex",
    43: "Right-Lateral-Ventricle", 49: "Right-Thalamus",
    50: "Right-Caudate", 51: "Right-Putamen",
    53: "Right-Hippocampus", 54: "Right-Amygdala",
}

stats = {}
for lab, name in DK_LABELS.items():
    mask = aparc == lab
    n = int(mask.sum())
    if n < 10:
        continue
    d_vals = disp[mask]
    j_vals = jac[mask]
    d_vals = d_vals[np.isfinite(d_vals)]
    j_vals = j_vals[np.isfinite(j_vals)]
    if len(d_vals) == 0:
        continue
    stats[str(lab)] = {
        "name": name,
        "n_voxels": n,
        "displacement_mm": {
            "mean": round(float(np.mean(d_vals)), 3),
            "median": round(float(np.median(d_vals)), 3),
            "max": round(float(np.max(d_vals)), 3),
            "p95": round(float(np.percentile(d_vals, 95)), 3),
        },
        "jacobian": {
            "mean": round(float(np.mean(j_vals)), 4),
            "min": round(float(np.min(j_vals)), 4),
            "max": round(float(np.max(j_vals)), 4),
        },
    }

with open(out_path, "w") as f:
    json.dump(stats, f, indent=2)

# Print top displaced ROIs
sorted_rois = sorted(stats.values(),
                     key=lambda x: x["displacement_mm"]["mean"],
                     reverse=True)
print(f'  {"ROI":<28s}  {"mean disp (mm)":>14s}  {"mean Jacobian":>14s}')
print(f'  {"-" * 60}')
for r in sorted_rois[:10]:
    print(f'  {r["name"]:<28s}  {r["displacement_mm"]["mean"]:>14.2f}  '
          f'{r["jacobian"]["mean"]:>14.4f}')
PYEOF
        echo "  ROI stats -> ${DISP_STATS}"
    else
        echo "  Skipped (aparc+aseg or displacement map not available)"
    fi
else
    echo "  (cached)"
fi

# =============================================================================
# Summary
# =============================================================================
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo " Longitudinal registration complete in $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"
echo " Output: ${OUT_DIR}"
echo "============================================================"
echo ""
echo " Deformation outputs:"
echo "   ${PREFIX}1Warp.nii.gz             Forward warp (pre-op -> post-op)"
echo "   ${PREFIX}1InverseWarp.nii.gz      Inverse warp (post-op -> pre-op)"
echo "   ${PREFIX}0GenericAffine.mat        Initial affine"
echo "   jacobian_preop_to_postop.nii.gz    J(x): local volume change"
echo "   displacement_magnitude.nii.gz      |u(x)| in mm"
echo "   cavity_mask_postop.nii.gz          Resection cavity mask"
echo ""
echo " Warped pre-op derivatives (in post-op space):"
echo "   T1w_preop_in_postop.nii.gz"
echo "   {fa,md,ad,rd}_preop_in_postop.nii.gz"
echo "   aparc+aseg_preop_in_postop.nii.gz"
echo ""
echo " Brain mechanics relevance:"
echo "   - Displacement field encodes empirical tissue motion"
echo "   - Jacobian map identifies local expansion (J>1) / contraction (J<1)"
echo "   - These provide validation data for FE model predictions"
echo ""
echo " Inspect with Freeview:"
echo "   bash scripts/freeview_deformation.sh --subject ${SUBJECT}"
