#!/usr/bin/env bash
# =============================================================================
# freeview_deformation.sh -- Inspect longitudinal deformation fields
# =============================================================================
#
# Opens Freeview with the post-op T1w overlaid with:
#   - Displacement magnitude map (|u(x)| in mm)
#   - Jacobian determinant map   (local volume change)
#   - Resection cavity mask
#   - Warped pre-op T1w          (for visual comparison)
#
# Usage:
#   bash scripts/freeview_deformation.sh --subject PAT16
#
# QC checklist:
#   1. Is the cavity mask reasonable?  (should fill the resection void)
#   2. Does the warped pre-op T1w align well with post-op anatomy?
#   3. Are high-displacement regions near the cavity (expected)?
#   4. Is the Jacobian near 1.0 in regions far from the lesion?
#   5. Do expanding regions (J > 1, e.g. ventricles) make clinical sense?
# =============================================================================

set -euo pipefail

SUBJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_deformation.sh --subject SUB"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LONG_DIR="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/longitudinal"
FMRIPREP="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}"
BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"

# Post-op T1w (reference anatomy)
POST_T1W="${FMRIPREP}/ses-postop/anat/sub-${SUBJECT}_ses-postop_desc-preproc_T1w.nii.gz"
if [[ ! -f "${POST_T1W}" ]]; then
    POST_T1W="${BIDS}/sub-${SUBJECT}/ses-postop/anat/sub-${SUBJECT}_ses-postop_T1w.nii.gz"
fi

# Deformation outputs
WARPED_T1W="${LONG_DIR}/T1w_preop_in_postop.nii.gz"
DISP_MAG="${LONG_DIR}/displacement_magnitude.nii.gz"
JACOBIAN="${LONG_DIR}/jacobian_preop_to_postop.nii.gz"
CAVITY="${LONG_DIR}/cavity_mask_postop.nii.gz"

echo "============================================================"
echo " Freeview: Longitudinal Deformation -- sub-${SUBJECT}"
echo "============================================================"

ARGS=()

# Post-op T1w as base layer
[[ -f "$POST_T1W" ]] && ARGS+=(-v "${POST_T1W}:name=T1w_postop")

# Warped pre-op T1w (toggle to check alignment)
[[ -f "$WARPED_T1W" ]] && ARGS+=(-v "${WARPED_T1W}:name=T1w_preop_warped:visible=0")

# Displacement magnitude (hot colormap, semi-transparent)
[[ -f "$DISP_MAG" ]] && ARGS+=(-v "${DISP_MAG}:name=displacement_mm:colormap=heat:heatscale=0,5,15:opacity=0.5:visible=0")

# Jacobian determinant (diverging colormap around 1.0)
[[ -f "$JACOBIAN" ]] && ARGS+=(-v "${JACOBIAN}:name=jacobian:colormap=jet:colorscale=0.5,1.5:opacity=0.5:visible=0")

# Cavity mask
[[ -f "$CAVITY" ]] && ARGS+=(-v "${CAVITY}:name=cavity_mask:colormap=heat:opacity=0.4:visible=0")

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "ERROR: No longitudinal outputs found.  Run register_longitudinal.sh first."
    exit 1
fi

echo ""
echo " Layers (toggle in sidebar):"
echo "   T1w_postop          -- Post-op anatomy (base layer)"
echo "   T1w_preop_warped    -- Pre-op T1w warped to post-op space"
echo "   displacement_mm     -- Displacement magnitude (mm)"
echo "   jacobian            -- Jacobian (J>1 = expansion, J<1 = contraction)"
echo "   cavity_mask         -- Detected resection cavity"
echo ""
echo " Tips:"
echo "   - Toggle T1w_preop_warped to check registration quality"
echo "   - High displacement near the cavity is expected"
echo "   - Jacobian > 1 in ventricles indicates post-op expansion"
echo "   - Jacobian < 1 near resection indicates tissue collapse"
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched. Close when done."
