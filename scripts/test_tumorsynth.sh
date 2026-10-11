#!/usr/bin/env bash
# =============================================================================
# test_tumorsynth.sh -- Run TumorSynth on all T1w images for feasibility test
# Glioma Brain Digital Twin
# =============================================================================
#
# Preprocesses (skull-strip + SRI-24 registration) and runs TumorSynth
# whole-tumor segmentation on T1w images (PAT16 × pre/post-op).
#
# Prerequisites:
#   - conda environment 'nnUNet_v1.7' (see scripts/install_tumorsynth.sh)
#   - FreeSurfer 8.1.0 (mri_synthstrip, mri_robust_register, mri_convert)
#   - TumorSynth repo at tools/TumorSynth/
#
# Usage:
#   conda activate nnUNet_v1.7
#   bash scripts/test_tumorsynth.sh [--threads N] [--subject SUB] [--session SES]
#
# Outputs (per subject/session):
#   derivatives/tumorsynth/sub-{SUB}/ses-{SES}/
#     sub-{SUB}_ses-{SES}_T1w_skullstripped.nii.gz
#     sub-{SUB}_ses-{SES}_T1w_sri24.nii.gz
#     sub-{SUB}_ses-{SES}_T1w_sri24_to_native.lta
#     sub-{SUB}_ses-{SES}_tumorsynth_wholetumor_sri24.nii.gz
#     sub-{SUB}_ses-{SES}_tumorsynth_wholetumor.nii.gz  (native space)
#     sub-{SUB}_ses-{SES}_tumorsynth_tumor_mask.nii.gz  (binary, label 18)
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop"
OUT_ROOT="${PROJECT_DIR}/derivatives/tumorsynth"
TOOLS_DIR="${PROJECT_DIR}/tools"
TUMORSYNTH_SCRIPT="${TOOLS_DIR}/TumorSynth/mri_TumorSynth"
NNUNET_ROOT="${HOME}/nnUNet"

THREADS=8
FILTER_SUBJECT=""
FILTER_SESSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threads)  THREADS="$2";        shift 2 ;;
        --subject)  FILTER_SUBJECT="$2"; shift 2 ;;
        --session)  FILTER_SESSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/test_tumorsynth.sh [--threads N] [--subject SUB] [--session SES]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---- Verify prerequisites ---------------------------------------------------
if [[ ! -f "${TUMORSYNTH_SCRIPT}" ]]; then
    echo "ERROR: TumorSynth script not found at: ${TUMORSYNTH_SCRIPT}"
    echo "  Run: bash scripts/install_tumorsynth.sh"
    exit 1
fi

if ! command -v mri_synthstrip &>/dev/null; then
    echo "ERROR: mri_synthstrip not found. Ensure FreeSurfer is sourced."
    exit 1
fi

# Locate SRI-24 template (ships with FreeSurfer or download)
SRI24_TEMPLATE=""
for candidate in \
    "${FREESURFER_HOME:-}/average/sri24/t1/T1_RAI.nii" \
    "${FREESURFER_HOME:-}/average/mni305.cor.mgz" \
    "${TOOLS_DIR}/sri24_T1.nii.gz"; do
    if [[ -f "${candidate}" ]]; then
        SRI24_TEMPLATE="${candidate}"
        break
    fi
done

if [[ -z "${SRI24_TEMPLATE}" ]]; then
    echo "WARNING: SRI-24 template not found in FreeSurfer."
    echo "  Downloading SRI-24 T1 template ..."
    mkdir -p "${TOOLS_DIR}"
    # Use mni305.cor.mgz as fallback (FreeSurfer standard space)
    if [[ -f "${FREESURFER_HOME:-}/average/mni305.cor.mgz" ]]; then
        SRI24_TEMPLATE="${FREESURFER_HOME}/average/mni305.cor.mgz"
        echo "  Using mni305.cor.mgz as registration target."
    else
        echo "ERROR: No suitable template found. Set FREESURFER_HOME."
        exit 1
    fi
fi

echo "============================================================"
echo " TumorSynth Feasibility Test"
echo "============================================================"
echo " BIDS dir      : ${BIDS_DIR}"
echo " Output root   : ${OUT_ROOT}"
echo " Template      : ${SRI24_TEMPLATE}"
echo " Threads       : ${THREADS}"
echo "============================================================"
echo ""

SUBJECTS="PAT16"
SESSIONS="preop postop"

[[ -n "${FILTER_SUBJECT}" ]] && SUBJECTS="${FILTER_SUBJECT}"
[[ -n "${FILTER_SESSION}" ]] && SESSIONS="${FILTER_SESSION}"

START_TOTAL=$(date +%s)

for SUB in ${SUBJECTS}; do
    for SES in ${SESSIONS}; do
        echo ""
        echo "────────────────────────────────────────────────────────────"
        echo "  sub-${SUB} / ses-${SES}"
        echo "────────────────────────────────────────────────────────────"

        T1W="${BIDS_DIR}/sub-${SUB}/ses-${SES}/anat/sub-${SUB}_ses-${SES}_T1w.nii.gz"
        if [[ ! -f "${T1W}" ]]; then
            echo "  SKIP: T1w not found: ${T1W}"
            continue
        fi

        OUT_DIR="${OUT_ROOT}/sub-${SUB}/ses-${SES}"
        mkdir -p "${OUT_DIR}"

        PREFIX="sub-${SUB}_ses-${SES}"
        SKULL_STRIPPED="${OUT_DIR}/${PREFIX}_T1w_skullstripped.nii.gz"
        T1W_SRI24="${OUT_DIR}/${PREFIX}_T1w_sri24.nii.gz"
        LTA_FILE="${OUT_DIR}/${PREFIX}_T1w_sri24_to_native.lta"
        SEG_SRI24="${OUT_DIR}/${PREFIX}_tumorsynth_wholetumor_sri24.nii.gz"
        SEG_NATIVE="${OUT_DIR}/${PREFIX}_tumorsynth_wholetumor.nii.gz"
        TUMOR_MASK="${OUT_DIR}/${PREFIX}_tumorsynth_tumor_mask.nii.gz"

        # Skip if final output exists
        if [[ -f "${TUMOR_MASK}" ]]; then
            echo "  (cached) ${TUMOR_MASK}"
            continue
        fi

        START=$(date +%s)

        # ── Step 1: Skull-strip ──────────────────────────────────────
        if [[ ! -f "${SKULL_STRIPPED}" ]]; then
            echo "  [1/4] Skull-stripping ..."
            mri_synthstrip -i "${T1W}" -o "${SKULL_STRIPPED}" --threads "${THREADS}" 2>/dev/null
        else
            echo "  [1/4] Skull-strip (cached)"
        fi

        # ── Step 2: Register to template ─────────────────────────────
        if [[ ! -f "${T1W_SRI24}" ]]; then
            echo "  [2/4] Registering to template ..."
            mri_robust_register \
                --mov "${SKULL_STRIPPED}" \
                --dst "${SRI24_TEMPLATE}" \
                --lta "${LTA_FILE}" \
                --mapmov "${T1W_SRI24}" \
                --satit \
                --iscale 2>/dev/null
        else
            echo "  [2/4] Registration (cached)"
        fi

        # ── Step 3: Run TumorSynth ───────────────────────────────────
        if [[ ! -f "${SEG_SRI24}" ]]; then
            echo "  [3/4] Running TumorSynth (--wholetumor --cpu) ..."
            bash "${TUMORSYNTH_SCRIPT}" \
                --i "${T1W_SRI24}" \
                --o "${SEG_SRI24}" \
                --wholetumor \
                --cpu \
                --nnUnet "${NNUNET_ROOT}" \
                --threads "${THREADS}"
        else
            echo "  [3/4] TumorSynth (cached)"
        fi

        # ── Step 4: Transform back to native T1w space + extract tumor ─
        echo "  [4/4] Resampling to native T1w space ..."

        python << PYEOF
import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to

seg_sri24 = nib.load("${SEG_SRI24}")
t1w_ref   = nib.load("${T1W}")

# Resample whole-tumor segmentation from SRI-24 to native T1w grid
seg_native = resample_from_to(seg_sri24, t1w_ref, order=0)
nib.save(seg_native, "${SEG_NATIVE}")

# Extract tumor-only binary mask (label 18 = whole tumor)
data = np.asarray(seg_native.dataobj).astype(int)
tumor = (data == 18).astype(np.uint8)
n_voxels = int(tumor.sum())
vox_vol = float(np.abs(np.linalg.det(t1w_ref.affine[:3, :3])))
vol_cm3 = n_voxels * vox_vol / 1000.0
print(f"  Tumor (label 18): {n_voxels} voxels, {vol_cm3:.1f} cm3")
if n_voxels == 0:
    print("  NOTE: No tumor detected by TumorSynth in this scan.")
out = nib.Nifti1Image(tumor, t1w_ref.affine, t1w_ref.header)
nib.save(out, "${TUMOR_MASK}")
PYEOF

        ELAPSED=$(( $(date +%s) - START ))
        echo "  Done in ${ELAPSED}s -> ${TUMOR_MASK}"
    done
done

ELAPSED_TOTAL=$(( $(date +%s) - START_TOTAL ))
echo ""
echo "============================================================"
echo " TumorSynth feasibility test complete in $(( ELAPSED_TOTAL / 60 ))m $(( ELAPSED_TOTAL % 60 ))s"
echo "============================================================"
echo ""
echo " Results:"
for SUB in ${SUBJECTS}; do
    for SES in ${SESSIONS}; do
        MASK="${OUT_ROOT}/sub-${SUB}/ses-${SES}/sub-${SUB}_ses-${SES}_tumorsynth_tumor_mask.nii.gz"
        if [[ -f "${MASK}" ]]; then
            echo "   ${MASK}"
        fi
    done
done
echo ""
echo " Compare with existing Aerts masks in NB14 (Section 5c)."
echo ""
echo " Quick Freeview inspection:"
echo "   freeview \\"
echo "     data/BIDS_preop_postop/sub-PAT16/ses-preop/anat/sub-PAT16_ses-preop_T1w.nii.gz \\"
echo "     derivatives/tumorsynth/sub-PAT16/ses-preop/sub-PAT16_ses-preop_tumorsynth_tumor_mask.nii.gz:colormap=heat:opacity=0.5 \\"
echo "     data/BIDS_preop_postop/derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_T1_label-tumor.nii.gz:colormap=jet:opacity=0.3"
