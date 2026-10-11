#!/usr/bin/env bash
# =============================================================================
# register_to_t1w.sh -- Bring all derivatives into native T1w space
# Glioma Brain Digital Twin
# =============================================================================
#
# After preprocessing, outputs live in different coordinate spaces:
#   - FreeSurfer: conformed T1w (256^3, RAS-permuted)
#   - fMRIPrep:   native T1w (scanner orientation)
#   - QSIPrep:    ACPC (axis-aligned)
#
# This script registers everything into the fMRIPrep native T1w space,
# which is the reference frame for the FE mesh.
#
# Steps:
#   1. Compute rigid (6-DOF) ACPC -> T1w registration via FLIRT
#   2. Apply to DTI scalar maps (FA, MD, AD, RD)
#   3. Apply to fOD images (WM, GM, CSF) with SH reorientation
#   4. Transform whole-brain tractography streamlines
#   5. Convert FreeSurfer volumes to T1w-space NIfTI
#   6. (Optional) Resample fMRIPrep BOLD to T1w space
#
# Requires:
#   - FSL (flirt, applywarp)
#   - MRtrix3 (transformconvert, mrtransform, mrconvert)
#   - FreeSurfer (mri_convert)
#   - ANTs (antsApplyTransforms)
#
# Usage:
#   bash scripts/register_to_t1w.sh --subject PAT16 --session preop \
#       [--nthreads N] [--bold]
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
NTHREADS=8
DO_BOLD=false

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)   SUBJECT="$2";  shift 2 ;;
        --session)   SESSION="$2";  shift 2 ;;
        --nthreads)  NTHREADS="$2"; shift 2 ;;
        --bold)      DO_BOLD=true;  shift ;;
        -h|--help)
            echo "Usage: bash scripts/register_to_t1w.sh --subject SUB --session SES"
            echo "           [--nthreads N] [--bold]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ---- Ensure tools are on PATH ----------------------------------------------
for tool in antsApplyTransforms mrconvert mri_convert; do
    if ! command -v "${tool}" &>/dev/null; then
        CONDA_BASE=$(conda info --base 2>/dev/null || echo "/opt/anaconda3")
        if [[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]]; then
            source "${CONDA_BASE}/etc/profile.d/conda.sh"
            for env_name in finse26 cas-workshop; do
                if conda env list 2>/dev/null | grep -q "${env_name}"; then
                    conda activate "${env_name}"
                    echo "Activated conda environment: ${env_name}"
                    break 2
                fi
            done
        fi
    fi
done

export PATH="${HOME}/mrtrix3/bin:${FREESURFER_HOME:-/Applications/freesurfer/8.1.0}/bin:${PATH}"

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"

FMRIPREP_ANAT="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/anat"
FMRIPREP_FUNC="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/func"
QSIPREP_DWI="${PROJECT_DIR}/derivatives/qsiprep/sub-${SUBJECT}/ses-${SESSION}/dwi"
MRTRIX_DIR="${PROJECT_DIR}/derivatives/mrtrix_recon/sub-${SUBJECT}/ses-${SESSION}"
FS_DIR="${PROJECT_DIR}/derivatives/freesurfer/${SUB_SES}"

# Reference image: fMRIPrep preprocessed T1w
T1W_REF="${FMRIPREP_ANAT}/${SUB_SES}_desc-preproc_T1w.nii.gz"

# ACPC-space DWI reference (source for registration)
DWI_REF="${QSIPREP_DWI}/${SUB_SES}_space-ACPC_dwiref.nii.gz"
# Fall back to T1w-space naming
if [[ ! -f "${DWI_REF}" ]]; then
    DWI_REF="${QSIPREP_DWI}/${SUB_SES}_space-T1w_dwiref.nii.gz"
fi

OUT_DIR="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/ses-${SESSION}"
XFM_DIR="${OUT_DIR}/transforms"

# Add tools to PATH
export PATH="${HOME}/mrtrix3/bin:${PATH}"
export FSLDIR="${FSLDIR:-$HOME/fsl}"
export PATH="${FSLDIR}/share/fsl/bin:${PATH}"
export FREESURFER_HOME="${FREESURFER_HOME:-/Applications/freesurfer/8.1.0}"

# ---- Verify inputs ----------------------------------------------------------
echo "============================================================"
echo " Register all derivatives to native T1w space"
echo "============================================================"
echo " Subject     : sub-${SUBJECT}"
echo " Session     : ses-${SESSION}"
echo " Reference   : ${T1W_REF}"
echo " DWI ref     : ${DWI_REF}"
echo " MRtrix dir  : ${MRTRIX_DIR}"
echo " Output      : ${OUT_DIR}"
echo " Threads     : ${NTHREADS}"
echo " BOLD        : ${DO_BOLD}"
echo "============================================================"

for f in "$T1W_REF" "$DWI_REF"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required input not found: $f"
        exit 1
    fi
done

mkdir -p "${OUT_DIR}" "${XFM_DIR}"
START_TIME=$(date +%s)

# =============================================================================
# Step 1: Compute rigid ACPC -> T1w registration
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 1/6: Computing ACPC -> T1w rigid registration ..."

FSL_MAT="${XFM_DIR}/acpc_to_t1w_flirt.mat"
MRTRIX_XFM="${XFM_DIR}/acpc_to_t1w_mrtrix.txt"

if [[ ! -f "${FSL_MAT}" ]]; then
    flirt \
        -in "${DWI_REF}" \
        -ref "${T1W_REF}" \
        -dof 6 \
        -omat "${FSL_MAT}" \
        -out "${XFM_DIR}/dwiref_in_T1w.nii.gz"
    echo "  FSL matrix: ${FSL_MAT}"
    echo "  Visual check: ${XFM_DIR}/dwiref_in_T1w.nii.gz"
else
    echo "  (cached)"
fi

# Convert FSL matrix to MRtrix3 format (needed for tcktransform)
if [[ ! -f "${MRTRIX_XFM}" ]]; then
    transformconvert "${FSL_MAT}" \
        "${DWI_REF}" "${T1W_REF}" \
        flirt_import "${MRTRIX_XFM}"
    echo "  MRtrix3 transform: ${MRTRIX_XFM}"
else
    echo "  (cached)"
fi

# =============================================================================
# Step 2: Register DTI scalar maps to T1w space
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 2/6: Registering DTI scalar maps to T1w space ..."

for MAP in fa md ad rd; do
    SRC="${MRTRIX_DIR}/${MAP}.nii.gz"
    DST="${OUT_DIR}/${MAP}_space-T1w.nii.gz"
    if [[ ! -f "$SRC" ]]; then
        echo "  WARNING: ${MAP}.nii.gz not found, skipping"
        continue
    fi
    if [[ ! -f "$DST" ]]; then
        flirt \
            -in "${SRC}" \
            -ref "${T1W_REF}" \
            -applyxfm -init "${FSL_MAT}" \
            -out "${DST}"
        echo "  ${MAP} -> ${DST}"
    else
        echo "  ${MAP} (cached)"
    fi
done

# =============================================================================
# Step 3: Register fOD images to T1w space (with SH reorientation)
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 3/6: Registering fOD images to T1w space ..."

for TISSUE in wm gm csf; do
    SRC="${MRTRIX_DIR}/${TISSUE}_fod_norm.mif"
    DST="${OUT_DIR}/${TISSUE}_fod_norm_space-T1w.mif"
    if [[ ! -f "$SRC" ]]; then
        echo "  WARNING: ${TISSUE}_fod_norm.mif not found, skipping"
        continue
    fi
    if [[ ! -f "$DST" ]]; then
        if [[ "$TISSUE" == "wm" ]]; then
            REORIENT_FLAG="-reorient_fod yes"
        else
            REORIENT_FLAG="-reorient_fod no"
        fi
        mrtransform "${SRC}" "${DST}" \
            -linear "${MRTRIX_XFM}" \
            ${REORIENT_FLAG} \
            -template "${T1W_REF}" \
            -nthreads "${NTHREADS}" -force
        echo "  ${TISSUE}_fod -> ${DST}"
    else
        echo "  ${TISSUE}_fod (cached)"
    fi
done

# =============================================================================
# Step 4: Transform whole-brain tractography to T1w space
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 4/6: Transforming tractography to T1w space ..."

TCK_SRC="${MRTRIX_DIR}/whole_brain.tck"
TCK_DST="${OUT_DIR}/whole_brain_space-T1w.tck"
TRANSFORM_SCRIPT="${PROJECT_DIR}/scripts/transform_tck.py"

if [[ ! -f "${TCK_SRC}" ]]; then
    echo "  WARNING: whole_brain.tck not found, skipping"
elif [[ ! -f "${TCK_DST}" ]]; then
    if [[ ! -f "${TRANSFORM_SCRIPT}" ]]; then
        echo "  ERROR: ${TRANSFORM_SCRIPT} not found"
        exit 1
    fi
    python "${TRANSFORM_SCRIPT}" "${TCK_SRC}" "${MRTRIX_XFM}" "${TCK_DST}"
    echo "  Tractography -> ${TCK_DST}"
    SIFT2_SRC="${MRTRIX_DIR}/sift2_weights.txt"
    if [[ -f "${SIFT2_SRC}" ]]; then
        cp "${SIFT2_SRC}" "${OUT_DIR}/sift2_weights.txt"
        echo "  SIFT2 weights copied (per-streamline, space-invariant)"
    fi
else
    echo "  (cached)"
fi

# Create subsampled and Freeview-compatible versions
TCK_100K="${OUT_DIR}/whole_brain_space-T1w_100k.tck"
TRK_100K="${OUT_DIR}/whole_brain_space-T1w_100k.trk"

if [[ -f "${TCK_DST}" && ! -f "${TCK_100K}" ]]; then
    echo "  Subsampling to 100K streamlines for visualization ..."
    tckedit "${TCK_DST}" "${TCK_100K}" -number 100000 -force
    echo "  100K subset -> ${TCK_100K}"
fi

if [[ -f "${TCK_100K}" && ! -f "${TRK_100K}" ]]; then
    echo "  Converting to TrackVis .trk format (Freeview compatible) ..."
    python "${PROJECT_DIR}/scripts/tck2trk.py" \
        "${TCK_100K}" "${T1W_REF}" "${TRK_100K}"
    echo "  TrackVis -> ${TRK_100K}"
fi

# =============================================================================
# Step 5: Convert FreeSurfer volumes to T1w-space NIfTI
# =============================================================================
echo ""
echo "[$(date '+%H:%M:%S')] Step 5/6: Converting FreeSurfer volumes to T1w space ..."

FSNATIVE_TO_T1W="${FMRIPREP_ANAT}/${SUB_SES}_from-fsnative_to-T1w_mode-image_xfm.txt"

# aparc+aseg (nearest-neighbour interpolation for discrete labels)
APARC_SRC="${FS_DIR}/mri/aparc+aseg.mgz"
APARC_DST="${OUT_DIR}/aparc+aseg_space-T1w.nii.gz"
if [[ -f "${APARC_SRC}" && ! -f "${APARC_DST}" ]]; then
    APARC_TMP="${OUT_DIR}/.tmp_aparc+aseg.nii.gz"
    mri_convert "${APARC_SRC}" "${APARC_TMP}" --out_type nii 2>/dev/null || \
        mrconvert "${APARC_SRC}" "${APARC_TMP}" -force
    if [[ -f "${FSNATIVE_TO_T1W}" ]]; then
        antsApplyTransforms \
            -d 3 \
            -i "${APARC_TMP}" \
            -r "${T1W_REF}" \
            -t "${FSNATIVE_TO_T1W}" \
            -n NearestNeighbor \
            -o "${APARC_DST}"
    else
        echo "  WARNING: fsnative-to-T1w transform not found, using direct conversion"
        cp "${APARC_TMP}" "${APARC_DST}"
    fi
    rm -f "${APARC_TMP}"
    echo "  aparc+aseg -> ${APARC_DST}"
elif [[ -f "${APARC_DST}" ]]; then
    echo "  aparc+aseg (cached)"
else
    echo "  WARNING: aparc+aseg.mgz not found, skipping"
fi

# aseg (subcortical segmentation only)
ASEG_SRC="${FS_DIR}/mri/aseg.mgz"
ASEG_DST="${OUT_DIR}/aseg_space-T1w.nii.gz"
if [[ -f "${ASEG_SRC}" && ! -f "${ASEG_DST}" ]]; then
    ASEG_TMP="${OUT_DIR}/.tmp_aseg.nii.gz"
    mri_convert "${ASEG_SRC}" "${ASEG_TMP}" --out_type nii 2>/dev/null || \
        mrconvert "${ASEG_SRC}" "${ASEG_TMP}" -force
    if [[ -f "${FSNATIVE_TO_T1W}" ]]; then
        antsApplyTransforms \
            -d 3 \
            -i "${ASEG_TMP}" \
            -r "${T1W_REF}" \
            -t "${FSNATIVE_TO_T1W}" \
            -n NearestNeighbor \
            -o "${ASEG_DST}"
    else
        cp "${ASEG_TMP}" "${ASEG_DST}"
    fi
    rm -f "${ASEG_TMP}"
    echo "  aseg -> ${ASEG_DST}"
elif [[ -f "${ASEG_DST}" ]]; then
    echo "  aseg (cached)"
else
    echo "  WARNING: aseg.mgz not found, skipping"
fi

# brain.mgz (skull-stripped T1w from FreeSurfer, linear interpolation)
BRAIN_SRC="${FS_DIR}/mri/brain.mgz"
BRAIN_DST="${OUT_DIR}/brain_fs_space-T1w.nii.gz"
if [[ -f "${BRAIN_SRC}" && ! -f "${BRAIN_DST}" ]]; then
    BRAIN_TMP="${OUT_DIR}/.tmp_brain.nii.gz"
    mri_convert "${BRAIN_SRC}" "${BRAIN_TMP}" --out_type nii 2>/dev/null || \
        mrconvert "${BRAIN_SRC}" "${BRAIN_TMP}" -force
    if [[ -f "${FSNATIVE_TO_T1W}" ]]; then
        antsApplyTransforms \
            -d 3 \
            -i "${BRAIN_TMP}" \
            -r "${T1W_REF}" \
            -t "${FSNATIVE_TO_T1W}" \
            -n Linear \
            -o "${BRAIN_DST}"
    else
        cp "${BRAIN_TMP}" "${BRAIN_DST}"
    fi
    rm -f "${BRAIN_TMP}"
    echo "  brain.mgz -> ${BRAIN_DST}"
elif [[ -f "${BRAIN_DST}" ]]; then
    echo "  brain.mgz (cached)"
else
    echo "  WARNING: brain.mgz not found, skipping"
fi

# =============================================================================
# Step 6 (optional): Resample BOLD timeseries to T1w space
# =============================================================================
if [[ "${DO_BOLD}" == true ]]; then
    echo ""
    echo "[$(date '+%H:%M:%S')] Step 6/6: Resampling BOLD to T1w space ..."
    echo ""
    echo "  NOTE: For production use, rerun fMRIPrep with --output-spaces T1w"
    echo "  to get properly resampled BOLD data with all corrections composed."
    echo ""
    echo "    bash scripts/run_fmriprep.sh --subject ${SUBJECT} --session ${SESSION}"
    echo ""
else
    echo ""
    echo "[$(date '+%H:%M:%S')] Step 6/6: BOLD resampling skipped (use --bold to enable)"
fi

# =============================================================================
# Summary
# =============================================================================
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo " Co-registration complete in $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"
echo " Output: ${OUT_DIR}"
echo "============================================================"
echo ""
echo "T1w-space outputs for FE mesh generation:"
echo ""
echo "  DTI scalar maps:"
echo "    fa_space-T1w.nii.gz   -- fractional anisotropy"
echo "    md_space-T1w.nii.gz   -- mean diffusivity"
echo "    ad_space-T1w.nii.gz   -- axial diffusivity"
echo "    rd_space-T1w.nii.gz   -- radial diffusivity"
echo ""
echo "  Fiber orientation distributions:"
echo "    wm_fod_norm_space-T1w.mif  -- WM fODFs (SH reoriented)"
echo "    gm_fod_norm_space-T1w.mif  -- GM component"
echo "    csf_fod_norm_space-T1w.mif -- CSF component"
echo ""
echo "  Tractography:"
echo "    whole_brain_space-T1w.tck      -- 10M streamlines (mrview)"
echo "    whole_brain_space-T1w_100k.tck -- 100K subset (mrview)"
echo "    whole_brain_space-T1w_100k.trk -- 100K subset (Freeview)"
echo "    sift2_weights.txt              -- SIFT2 weights (unchanged)"
echo ""
echo "  FreeSurfer segmentations:"
echo "    aparc+aseg_space-T1w.nii.gz -- parcellation + segmentation"
echo "    aseg_space-T1w.nii.gz       -- subcortical segmentation"
echo "    brain_fs_space-T1w.nii.gz   -- skull-stripped brain"
echo ""
echo "  Transforms:"
echo "    transforms/acpc_to_t1w_flirt.mat   -- FSL format"
echo "    transforms/acpc_to_t1w_mrtrix.txt  -- MRtrix3 format"
echo "    transforms/dwiref_in_T1w.nii.gz    -- visual QC overlay"
echo ""
echo "All outputs are in fMRIPrep native T1w space, ready for"
echo "FE mesh material property assignment."
