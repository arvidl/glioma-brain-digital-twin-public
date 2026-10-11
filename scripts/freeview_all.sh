#!/usr/bin/env bash
# =============================================================================
# freeview_all.sh -- Unified viewer: all modalities in native T1w space
# =============================================================================
#
# Opens Freeview with all co-registered outputs for a given subject/session:
#   - Structural: T1w, aparc+aseg
#   - Diffusion:  DWI ref (b0), FA, MD, AD, RD
#   - Tractography: 100K streamlines (.trk)
#   - Functional: BOLD reference, 4D BOLD (if available)
#
# Most layers start invisible; toggle visibility in the layer panel.
#
# Usage:
#   bash scripts/freeview_all.sh --subject PAT16 --session preop
# =============================================================================

set -euo pipefail

SUBJECT=""
SESSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_all.sh --subject SUB --session SES"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"

ANAT="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/anat"
FUNC="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/func"
REG="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/ses-${SESSION}"

# Reference T1w
T1W="${ANAT}/${SUB_SES}_desc-preproc_T1w.nii.gz"

# Segmentation
APARC="${REG}/aparc+aseg_space-T1w.nii.gz"

# DWI reference
DWIREF="${REG}/transforms/dwiref_in_T1w.nii.gz"

# DTI scalar maps
FA="${REG}/fa_space-T1w.nii.gz"
MD="${REG}/md_space-T1w.nii.gz"
AD="${REG}/ad_space-T1w.nii.gz"
RD="${REG}/rd_space-T1w.nii.gz"

# Tractography (TrackVis format)
TRK="${REG}/whole_brain_space-T1w_100k.trk"

# Functional
BOLDREF="${FUNC}/${SUB_SES}_task-rest_space-T1w_boldref.nii.gz"
BOLD="${FUNC}/${SUB_SES}_task-rest_space-T1w_desc-preproc_bold.nii.gz"

# Build args, skipping missing files
ARGS=()

add_vol() {
    local path="$1" opts="$2"
    if [[ -f "$path" ]]; then
        ARGS+=(-v "${path}:${opts}")
    else
        echo "SKIP: $(basename "$path")"
    fi
}

add_vol "$T1W"     "name=T1w"
add_vol "$APARC"   "name=aparc+aseg:colormap=lut:opacity=0.3"
add_vol "$DWIREF"  "name=DWI_ref_b0:colormap=heat:opacity=0.5:visible=0"
add_vol "$FA"      "name=FA:colormap=jet:opacity=0.5:visible=0"
add_vol "$MD"      "name=MD:colormap=jet:opacity=0.5:visible=0"
add_vol "$AD"      "name=AD:colormap=jet:opacity=0.5:visible=0"
add_vol "$RD"      "name=RD:colormap=jet:opacity=0.5:visible=0"
add_vol "$BOLDREF" "name=BOLD_ref:colormap=heat:opacity=0.5:visible=0"
add_vol "$BOLD"    "name=BOLD_4D:colormap=heat:opacity=0.5:visible=0"

if [[ -f "$TRK" ]]; then
    ARGS+=(-tract "$TRK")
else
    echo "SKIP: $(basename "$TRK" 2>/dev/null || echo 'tractography')"
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "ERROR: No files found. Run the pipeline first."
    exit 1
fi

echo "============================================================"
echo " Freeview: All modalities -- sub-${SUBJECT} ses-${SESSION}"
echo "============================================================"
echo " Toggle layer visibility in the layer panel (left sidebar)."
echo " Use the frame slider (bottom) to scrub through 4D BOLD."
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched (PID: $!). Close when done."
