#!/usr/bin/env bash
# =============================================================================
# freeview_resseg.sh -- Inspect RESSEG cavity segmentation on post-op T1w
# =============================================================================
#
# Opens Freeview with the post-op T1w overlaid with:
#   - RESSEG cavity segmentation     (deep-learning prediction)
#   - Pipeline cavity mask            (tumor-prior / SynthSeg difference)
#   - Pre-op tumor mask (T1w space)   (for spatial comparison)
#   - Perilesional zone               (if available)
#   - Warped pre-op T1w               (to assess cavity extent)
#
# Designed for comparing the RESSEG result against the existing pipeline
# cavity mask and the pre-op tumor footprint.
#
# Usage:
#   bash scripts/freeview_resseg.sh --subject PAT16
#   bash scripts/freeview_resseg.sh --subject PAT16 --all
#
# Options:
#   --subject SUB   Subject ID (required, e.g. PAT16)
#   --all           Also load displacement and Jacobian maps
#   --no-compare    Only show RESSEG overlay, skip pipeline masks
#
# QC checklist:
#   1. Does the RESSEG mask cover the visible cavity on T1w?
#   2. Does it bleed into healthy tissue or ventricles?
#   3. How does it compare to the pipeline cavity mask (spatial overlap)?
#   4. Is it contained within / near the pre-op tumor footprint?
#   5. Are the mask boundaries smooth and anatomically plausible?
# =============================================================================

set -euo pipefail

SUBJECT=""
SHOW_ALL=false
NO_COMPARE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)    SUBJECT="$2";       shift 2 ;;
        --all)        SHOW_ALL=true;      shift ;;
        --no-compare) NO_COMPARE=true;    shift ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_resseg.sh --subject SUB [--all] [--no-compare]"
            echo ""
            echo "  --subject SUB   Subject ID (required, e.g. PAT16)"
            echo "  --all           Also load displacement and Jacobian maps"
            echo "  --no-compare    Only show RESSEG overlay, skip pipeline masks"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"
FMRIPREP="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}"
REG="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}"
LONG_DIR="${REG}/longitudinal"
RESSEG_DIR="${PROJECT_DIR}/derivatives/resseg/sub-${SUBJECT}"
TUMOR_DIR="${BIDS}/derivatives/tumor_masks/sub-${SUBJECT}/anat"

# Post-op T1w (prefer fMRIPrep-processed, fall back to raw BIDS)
POST_T1W="${FMRIPREP}/ses-postop/anat/sub-${SUBJECT}_ses-postop_desc-preproc_T1w.nii.gz"
[[ ! -f "$POST_T1W" ]] && POST_T1W="${BIDS}/sub-${SUBJECT}/ses-postop/anat/sub-${SUBJECT}_ses-postop_T1w.nii.gz"

# RESSEG cavity mask
RESSEG_CAVITY="${RESSEG_DIR}/sub-${SUBJECT}_ses-postop_T1w_cavity.nii.gz"

# Pipeline cavity mask (from register_longitudinal.sh)
PIPELINE_CAVITY="${LONG_DIR}/cavity_mask_postop.nii.gz"

# Pre-op tumor mask (native T1w space)
TUMOR_MASK="${TUMOR_DIR}/sub-${SUBJECT}_space_T1_label-tumor.nii.gz"
TUMOR_BINARY="${TUMOR_DIR}/sub-${SUBJECT}_space_T1_label-tumor_binary.nii.gz"

# Additional overlays
PERILESIONAL="${LONG_DIR}/perilesional.nii.gz"
CAVITY_CSF="${LONG_DIR}/cavity_csf.nii.gz"
WARPED_T1W="${LONG_DIR}/T1w_preop_in_postop.nii.gz"
DISP_MAG="${LONG_DIR}/displacement_magnitude.nii.gz"
JACOBIAN="${LONG_DIR}/jacobian_preop_to_postop.nii.gz"

# ---- Verify RESSEG output exists -------------------------------------------
if [[ ! -f "$RESSEG_CAVITY" ]]; then
    echo "ERROR: RESSEG cavity mask not found at:"
    echo "  ${RESSEG_CAVITY}"
    echo ""
    echo "Run RESSEG first:"
    echo "  export KMP_DUPLICATE_LIB_OK=TRUE"
    echo "  resseg ${POST_T1W} -o ${RESSEG_CAVITY}"
    exit 1
fi

# ---- Build Freeview command -------------------------------------------------
ARGS=()

add_vol() {
    local path="$1" opts="$2"
    if [[ -f "$path" ]]; then
        ARGS+=(-v "${path}:${opts}")
        return 0
    fi
    return 1
}

# Layer 1: Post-op T1w (base anatomy)
add_vol "$POST_T1W" "name=T1w_postop" || {
    echo "ERROR: Post-op T1w not found"; exit 1
}

# Layer 2: RESSEG cavity mask (green, semi-transparent -- primary target)
add_vol "$RESSEG_CAVITY" \
    "name=RESSEG_cavity:colormap=heat:heatscale=0,0.5,1:opacity=0.45"

if [[ "$NO_COMPARE" == false ]]; then
    # Layer 3: Pipeline cavity mask (blue-tinted via jet, lower opacity)
    add_vol "$PIPELINE_CAVITY" \
        "name=Pipeline_cavity:colormap=jet:colorscale=0,1:opacity=0.35:visible=0" || true

    # Layer 4: Pre-op tumor probability map
    if ! add_vol "$TUMOR_MASK" \
        "name=Tumor_preop:colormap=jet:colorscale=0,1:opacity=0.35:visible=0"; then
        add_vol "$TUMOR_BINARY" \
            "name=Tumor_preop_bin:colormap=jet:colorscale=0,1:opacity=0.35:visible=0" || true
    fi

    # Layer 5: Perilesional zone
    add_vol "$PERILESIONAL" \
        "name=Perilesional:colormap=nih:opacity=0.3:visible=0" || true

    # Layer 6: CSF-filled cavity
    add_vol "$CAVITY_CSF" \
        "name=Cavity_CSF:colormap=heat:opacity=0.35:visible=0" || true

    # Layer 7: Warped pre-op T1w (toggle to see what was removed)
    add_vol "$WARPED_T1W" \
        "name=T1w_preop_warped:visible=0" || true
fi

if [[ "$SHOW_ALL" == true ]]; then
    add_vol "$DISP_MAG" \
        "name=Displacement_mm:colormap=heat:heatscale=0,5,15:opacity=0.45:visible=0" || true
    add_vol "$JACOBIAN" \
        "name=Jacobian:colormap=jet:colorscale=0.5,1.5:opacity=0.45:visible=0" || true
fi

# ---- Print summary ---------------------------------------------------------
echo "============================================================"
echo " Freeview: RESSEG Cavity Inspection -- sub-${SUBJECT}"
echo "============================================================"
echo ""
echo " Layers (toggle in sidebar):"
echo "   T1w_postop          Post-op anatomy (base)"
echo "   RESSEG_cavity       RESSEG deep-learning cavity mask"

if [[ "$NO_COMPARE" == false ]]; then
    [[ -f "$PIPELINE_CAVITY" ]] && \
    echo "   Pipeline_cavity     Cavity mask from the pipeline (tumor-prior)"
    [[ -f "$TUMOR_MASK" || -f "$TUMOR_BINARY" ]] && \
    echo "   Tumor_preop         Pre-op tumor probability / binary mask"
    [[ -f "$PERILESIONAL" ]] && \
    echo "   Perilesional        Perilesional zone mask"
    [[ -f "$CAVITY_CSF" ]] && \
    echo "   Cavity_CSF          CSF-filled cavity region"
    [[ -f "$WARPED_T1W" ]] && \
    echo "   T1w_preop_warped    Pre-op T1w warped to post-op space"
fi

if [[ "$SHOW_ALL" == true ]]; then
    [[ -f "$DISP_MAG" ]] && \
    echo "   Displacement_mm     Displacement field magnitude (mm)"
    [[ -f "$JACOBIAN" ]] && \
    echo "   Jacobian            Volume change (J>1=expansion, J<1=contraction)"
fi

echo ""
echo " QC tips:"
echo "   - Toggle RESSEG_cavity to check coverage of the surgical void"
echo "   - Turn on Pipeline_cavity to compare spatial overlap"
echo "   - Turn on Tumor_preop to verify cavity is within tumor footprint"
echo "   - Toggle T1w_preop_warped to see pre-op anatomy in post-op space"
echo "   - Use Ctrl+click to place cursor at cavity boundary"
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched (PID: $!). Close when done."
