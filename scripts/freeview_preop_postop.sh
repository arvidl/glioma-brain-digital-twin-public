#!/usr/bin/env bash
# =============================================================================
# freeview_preop_postop.sh -- Side-by-side pre-op vs post-op comparison
# =============================================================================
#
# Opens TWO Freeview instances: one for pre-op and one for post-op,
# positioned side by side on screen for visual comparison.
#
# Alternatively, loads both timepoints into a single Freeview with
# different colormaps for toggling.
#
# Usage:
#   bash scripts/freeview_preop_postop.sh --subject PAT16 [--split]
#
# Options:
#   --split    Open two separate Freeview windows (default: single window)
# =============================================================================

set -euo pipefail

SUBJECT=""
SPLIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --split)   SPLIT=true;   shift ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_preop_postop.sh --subject SUB [--split]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"
FMRIPREP="${PROJECT_DIR}/derivatives/fmriprep"
REG="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}"

# Pre-op paths
PRE_T1W="${BIDS}/sub-${SUBJECT}/ses-preop/anat/sub-${SUBJECT}_ses-preop_T1w.nii.gz"
PRE_T1W_PROC="${FMRIPREP}/sub-${SUBJECT}/ses-preop/anat/sub-${SUBJECT}_ses-preop_desc-preproc_T1w.nii.gz"
PRE_FA="${REG}/ses-preop/fa_space-T1w.nii.gz"
PRE_APARC="${REG}/ses-preop/aparc+aseg_space-T1w.nii.gz"

# Post-op paths
POST_T1W="${BIDS}/sub-${SUBJECT}/ses-postop/anat/sub-${SUBJECT}_ses-postop_T1w.nii.gz"
POST_T1W_PROC="${FMRIPREP}/sub-${SUBJECT}/ses-postop/anat/sub-${SUBJECT}_ses-postop_desc-preproc_T1w.nii.gz"
POST_FA="${REG}/ses-postop/fa_space-T1w.nii.gz"
POST_APARC="${REG}/ses-postop/aparc+aseg_space-T1w.nii.gz"

# Delta maps (if available)
DELTA_FA="${REG}/preop_vs_postop/delta_fa_space-T1w.nii.gz"
DELTA_MD="${REG}/preop_vs_postop/delta_md_space-T1w.nii.gz"

# Tumor masks
TUMOR_PRE="${BIDS}/derivatives/tumor_masks/sub-${SUBJECT}/anat/sub-${SUBJECT}_ses-preop_space_T1_label-tumor.nii.gz"
TUMOR_POST="${BIDS}/derivatives/tumor_masks/sub-${SUBJECT}/anat/sub-${SUBJECT}_ses-postop_space_T1_label-tumor.nii.gz"

echo "============================================================"
echo " Freeview: Pre-op vs Post-op -- sub-${SUBJECT}"
echo "============================================================"

if [[ "${SPLIT}" == true ]]; then
    # Two separate windows
    PRE_ARGS=()
    POST_ARGS=()

    # Use processed T1w if available, else raw
    PRE_SRC="${PRE_T1W_PROC}"; [[ ! -f "$PRE_SRC" ]] && PRE_SRC="${PRE_T1W}"
    POST_SRC="${POST_T1W_PROC}"; [[ ! -f "$POST_SRC" ]] && POST_SRC="${POST_T1W}"

    [[ -f "$PRE_SRC" ]] && PRE_ARGS+=(-v "${PRE_SRC}:name=T1w_preop")
    [[ -f "$PRE_FA" ]] && PRE_ARGS+=(-v "${PRE_FA}:name=FA_preop:colormap=jet:opacity=0.5:visible=0")
    [[ -f "$PRE_APARC" ]] && PRE_ARGS+=(-v "${PRE_APARC}:name=aparc_preop:colormap=lut:opacity=0.3:visible=0")
    [[ -f "$TUMOR_PRE" ]] && PRE_ARGS+=(-v "${TUMOR_PRE}:name=tumor_preop:colormap=heat:opacity=0.5")

    [[ -f "$POST_SRC" ]] && POST_ARGS+=(-v "${POST_SRC}:name=T1w_postop")
    [[ -f "$POST_FA" ]] && POST_ARGS+=(-v "${POST_FA}:name=FA_postop:colormap=jet:opacity=0.5:visible=0")
    [[ -f "$POST_APARC" ]] && POST_ARGS+=(-v "${POST_APARC}:name=aparc_postop:colormap=lut:opacity=0.3:visible=0")
    [[ -f "$TUMOR_POST" ]] && POST_ARGS+=(-v "${TUMOR_POST}:name=tumor_postop:colormap=heat:opacity=0.5")

    echo " Opening two Freeview windows (pre-op left, post-op right)"
    echo "============================================================"

    freeview "${PRE_ARGS[@]}" &
    sleep 1
    freeview "${POST_ARGS[@]}" &

else
    # Single window with both timepoints
    ARGS=()

    # Pre-op T1w
    PRE_SRC="${PRE_T1W_PROC}"; [[ ! -f "$PRE_SRC" ]] && PRE_SRC="${PRE_T1W}"
    [[ -f "$PRE_SRC" ]] && ARGS+=(-v "${PRE_SRC}:name=T1w_preop")

    # Post-op T1w
    POST_SRC="${POST_T1W_PROC}"; [[ ! -f "$POST_SRC" ]] && POST_SRC="${POST_T1W}"
    [[ -f "$POST_SRC" ]] && ARGS+=(-v "${POST_SRC}:name=T1w_postop:visible=0")

    # FA maps
    [[ -f "$PRE_FA" ]] && ARGS+=(-v "${PRE_FA}:name=FA_preop:colormap=jet:opacity=0.5:visible=0")
    [[ -f "$POST_FA" ]] && ARGS+=(-v "${POST_FA}:name=FA_postop:colormap=jet:opacity=0.5:visible=0")

    # Delta maps
    [[ -f "$DELTA_FA" ]] && ARGS+=(-v "${DELTA_FA}:name=delta_FA:colormap=heat:opacity=0.5:visible=0")
    [[ -f "$DELTA_MD" ]] && ARGS+=(-v "${DELTA_MD}:name=delta_MD:colormap=heat:opacity=0.5:visible=0")

    # Deformation outputs (from register_longitudinal.sh)
    LONG_DIR="${REG}/longitudinal"
    DISP_MAG="${LONG_DIR}/displacement_magnitude.nii.gz"
    JACOBIAN="${LONG_DIR}/jacobian_preop_to_postop.nii.gz"
    CAVITY="${LONG_DIR}/cavity_mask_postop.nii.gz"
    [[ -f "$DISP_MAG" ]] && ARGS+=(-v "${DISP_MAG}:name=displacement_mm:colormap=heat:heatscale=0,5,15:opacity=0.5:visible=0")
    [[ -f "$JACOBIAN" ]] && ARGS+=(-v "${JACOBIAN}:name=jacobian:colormap=jet:colorscale=0.5,1.5:opacity=0.5:visible=0")
    [[ -f "$CAVITY" ]] && ARGS+=(-v "${CAVITY}:name=cavity_mask:colormap=heat:opacity=0.4:visible=0")

    # Tumor masks
    [[ -f "$TUMOR_PRE" ]] && ARGS+=(-v "${TUMOR_PRE}:name=tumor_preop:colormap=heat:opacity=0.5:visible=0")
    [[ -f "$TUMOR_POST" ]] && ARGS+=(-v "${TUMOR_POST}:name=tumor_postop:colormap=heat:opacity=0.5:visible=0")

    # Parcellation
    [[ -f "$PRE_APARC" ]] && ARGS+=(-v "${PRE_APARC}:name=aparc_preop:colormap=lut:opacity=0.3:visible=0")

    echo " Toggle layers in the sidebar to compare pre-op vs post-op."
    echo " Delta maps show post-op minus pre-op changes."
    echo "============================================================"

    freeview "${ARGS[@]}" &
fi

echo "Freeview launched. Close when done."
