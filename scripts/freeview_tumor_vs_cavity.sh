#!/usr/bin/env bash
# =============================================================================
# freeview_tumor_vs_cavity.sh -- Compare pre-op tumor mask with post-op cavity
# =============================================================================
#
# Three modes:
#   --side-by-side  (default)  Two Freeview windows, each mask on its own
#                              native T1w -- no registration confounds.
#   --overlay                  Single Freeview window with affine-warped tumor
#                              mask overlaid on the post-op T1w alongside the
#                              cavity mask.
#   --screenshot FILE          Like --overlay, but also saves a screenshot to
#                              FILE (PNG) for reproducible figure generation.
#
# The cavity mask display name is read from .cavity_method (tumor_prior,
# synthseg, or resseg) so the Freeview label reflects the actual method.
#
# Usage:
#   bash scripts/freeview_tumor_vs_cavity.sh --subject PAT16
#   bash scripts/freeview_tumor_vs_cavity.sh --subject PAT16 --overlay
#   bash scripts/freeview_tumor_vs_cavity.sh --subject PAT16 --overlay \
#       --screenshot figures/qc_tumor_vs_cavity_PAT16.png
#
# QC checklist:
#   1. Does the tumor mask match the visible lesion in pre-op T1w?
#   2. Does the cavity mask trace the CSF-filled void in post-op T1w?
#   3. Are the shapes/sizes clinically consistent (cavity <= tumor)?
#   4. Do both masks co-localize in overlay mode?
# =============================================================================

set -euo pipefail

SUBJECT=""
MODE="side-by-side"
SCREENSHOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --side-by-side) MODE="side-by-side"; shift ;;
        --overlay) MODE="overlay"; shift ;;
        --screenshot) SCREENSHOT="$2"; MODE="overlay"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_tumor_vs_cavity.sh --subject SUB [--side-by-side|--overlay]"
            echo "       [--screenshot FILE.png]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LONG_DIR="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/longitudinal"
FMRIPREP="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}"
BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"
TUMOR_DIR="${BIDS}/derivatives/tumor_masks/sub-${SUBJECT}/anat"

# ---- Ensure ANTs is on PATH ------------------------------------------------
if ! command -v antsApplyTransforms &>/dev/null; then
    CONDA_BASE=$(conda info --base 2>/dev/null || echo "/opt/anaconda3")
    if [[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]]; then
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        for env_name in finse26 cas-workshop; do
            if conda env list 2>/dev/null | grep -q "${env_name}"; then
                conda activate "${env_name}"
                if command -v antsApplyTransforms &>/dev/null; then
                    echo "Activated conda environment: ${env_name}"
                    break
                fi
                conda deactivate
            fi
        done
    fi
    if ! command -v antsApplyTransforms &>/dev/null; then
        echo "ERROR: ANTs not found. Install via: conda install -c conda-forge ants"
        exit 1
    fi
fi

# ---- Locate inputs ----------------------------------------------------------
POST_T1W="${FMRIPREP}/ses-postop/anat/sub-${SUBJECT}_ses-postop_desc-preproc_T1w.nii.gz"
if [[ ! -f "${POST_T1W}" ]]; then
    POST_T1W="${BIDS}/sub-${SUBJECT}/ses-postop/anat/sub-${SUBJECT}_ses-postop_T1w.nii.gz"
fi

PRE_T1W="${FMRIPREP}/ses-preop/anat/sub-${SUBJECT}_ses-preop_desc-preproc_T1w.nii.gz"

TUMOR_PROB="${TUMOR_DIR}/sub-${SUBJECT}_space_T1_label-tumor.nii.gz"
TUMOR_BIN="${TUMOR_DIR}/sub-${SUBJECT}_space_T1_label-tumor_binary.nii.gz"
CAVITY="${LONG_DIR}/cavity_mask_postop.nii.gz"
WARPED_T1W="${LONG_DIR}/T1w_preop_in_postop.nii.gz"

WARP="${LONG_DIR}/preop_to_postop_1Warp.nii.gz"
AFFINE="${LONG_DIR}/preop_to_postop_0GenericAffine.mat"

# Pick the best available tumor mask (binary preferred, then probabilistic)
TUMOR_SRC=""
if [[ -f "${TUMOR_BIN}" ]]; then
    TUMOR_SRC="${TUMOR_BIN}"
elif [[ -f "${TUMOR_PROB}" ]]; then
    TUMOR_SRC="${TUMOR_PROB}"
fi

# ---- Read cavity method tag for display name --------------------------------
CAVITY_METHOD_FILE="${LONG_DIR}/.cavity_method"
CAVITY_METHOD="unknown"
if [[ -f "${CAVITY_METHOD_FILE}" ]]; then
    CAVITY_METHOD=$(cat "${CAVITY_METHOD_FILE}" | tr -d '[:space:]')
fi

CAVITY_DISPLAY_NAME="cavity_${CAVITY_METHOD}"
echo "  Cavity mask method: ${CAVITY_METHOD} -> display name: ${CAVITY_DISPLAY_NAME}"

for f in "${POST_T1W}" "${CAVITY}" "${WARP}" "${AFFINE}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required file not found: $f"
        echo "  Run register_longitudinal.sh --subject ${SUBJECT} first."
        exit 1
    fi
done

if [[ -z "${TUMOR_SRC}" ]]; then
    echo "WARNING: No tumor mask found for sub-${SUBJECT}."
    echo "  Expected: ${TUMOR_BIN}"
    echo "  Will show cavity mask only."
fi

# =============================================================================
# Side-by-side mode: two independent Freeview windows
# =============================================================================
if [[ "${MODE}" == "side-by-side" ]]; then

    echo ""
    echo "============================================================"
    echo " Freeview: Tumor vs Cavity (side-by-side) -- sub-${SUBJECT}"
    echo "============================================================"
    echo ""
    echo " Window 1 (PRE-OP):  T1w + tumor mask (Aerts method)"
    echo " Window 2 (POST-OP): T1w + cavity mask (${CAVITY_METHOD})"
    echo ""
    echo " Each mask is shown on its own native anatomy."
    echo " Navigate to the same anatomical landmark in both windows"
    echo " to compare tumor extent vs cavity."
    echo ""
    echo " QC:"
    echo "   - Does the tumor overlay match the visible lesion?"
    echo "   - Does the cavity overlay trace the dark CSF void?"
    echo "   - Are shapes/sizes clinically consistent?"
    echo "============================================================"

    # Window 1: Pre-op T1w + tumor mask
    ARGS_PRE=()
    if [[ -f "${PRE_T1W}" ]]; then
        ARGS_PRE+=(-v "${PRE_T1W}:name=T1w_preop")
    else
        PRE_T1W_BIDS="${BIDS}/sub-${SUBJECT}/ses-preop/anat/sub-${SUBJECT}_ses-preop_T1w.nii.gz"
        [[ -f "${PRE_T1W_BIDS}" ]] && ARGS_PRE+=(-v "${PRE_T1W_BIDS}:name=T1w_preop")
    fi
    if [[ -n "${TUMOR_SRC}" ]]; then
        ARGS_PRE+=(-v "${TUMOR_SRC}:name=tumor_mask:colormap=heat:opacity=0.45")
    fi

    if [[ ${#ARGS_PRE[@]} -gt 0 ]]; then
        echo ""
        echo "Launching Window 1 (pre-op) ..."
        freeview "${ARGS_PRE[@]}" &
        sleep 1
    fi

    # Window 2: Post-op T1w + cavity mask
    ARGS_POST=()
    ARGS_POST+=(-v "${POST_T1W}:name=T1w_postop")
    ARGS_POST+=(-v "${CAVITY}:name=${CAVITY_DISPLAY_NAME}:colormap=heat:opacity=0.45")

    echo "Launching Window 2 (post-op) ..."
    freeview "${ARGS_POST[@]}" &

    echo ""
    echo "Two Freeview windows launched. Arrange side by side."
    echo "Close both when done."

# =============================================================================
# Overlay mode: single Freeview with affine-warped tumor + cavity
# =============================================================================
else

    # Warp tumor mask with AFFINE ONLY -- the SyN warp field is unreliable
    # inside the resection cavity (excluded from cost function).
    TUMOR_WARPED="${LONG_DIR}/tumor_preop_in_postop.nii.gz"

    if [[ -n "${TUMOR_SRC}" ]]; then
        echo "Warping tumor mask to post-op space (affine only) ..."
        antsApplyTransforms \
            -d 3 \
            -i "${TUMOR_SRC}" \
            -r "${POST_T1W}" \
            -o "${TUMOR_WARPED}" \
            -t "${AFFINE}" \
            -n Linear
        echo "  -> ${TUMOR_WARPED}"
    fi

    echo ""
    echo "============================================================"
    echo " Freeview: Tumor vs Cavity (overlay) -- sub-${SUBJECT}"
    echo "============================================================"

    ARGS=()
    ARGS+=(-v "${POST_T1W}:name=T1w_postop")
    [[ -f "$WARPED_T1W" ]] && ARGS+=(-v "${WARPED_T1W}:name=T1w_preop_warped:visible=0")
    [[ -f "$PRE_T1W" ]] && ARGS+=(-v "${PRE_T1W}:name=T1w_preop_native:visible=0")
    ARGS+=(-v "${CAVITY}:name=${CAVITY_DISPLAY_NAME}:colormap=green_red:opacity=0.40")
    if [[ -f "${TUMOR_WARPED}" ]]; then
        ARGS+=(-v "${TUMOR_WARPED}:name=tumor_preop_warped:colormap=heat:opacity=0.40")
    fi

    echo ""
    echo " Layers:"
    echo "   T1w_postop          -- Post-op anatomy (base)"
    echo "   ${CAVITY_DISPLAY_NAME}  -- Resection cavity (green) [method: ${CAVITY_METHOD}]"
    echo "   tumor_preop_warped  -- Tumor, affine-warped (red/heat)"
    echo ""
    echo " Note: tumor is aligned with affine only (no SyN near cavity)."
    echo "============================================================"

    if [[ -n "${SCREENSHOT}" ]]; then
        # Ensure output directory exists
        mkdir -p "$(dirname "${SCREENSHOT}")"
        echo ""
        echo " Screenshot mode: will save to ${SCREENSHOT}"
        echo " Navigate to the desired slice, then use:"
        echo "   File > Save Screenshot As... > ${SCREENSHOT}"
        echo " Or use the Freeview -ss flag for automated capture:"
        echo ""
        SCREENSHOT_ABS="$(cd "$(dirname "${SCREENSHOT}")" && pwd)/$(basename "${SCREENSHOT}")"
        freeview "${ARGS[@]}" \
            -viewport sagittal \
            -ss "${SCREENSHOT_ABS}" &
        FVPID=$!
        sleep 5
        if [[ -f "${SCREENSHOT_ABS}" ]]; then
            echo " Screenshot saved: ${SCREENSHOT_ABS}"
        else
            echo " Freeview launched (PID ${FVPID})."
            echo " Save screenshot manually: File > Save Screenshot As..."
        fi
    else
        freeview "${ARGS[@]}" &
        echo "Freeview launched. Close when done."
    fi
fi
