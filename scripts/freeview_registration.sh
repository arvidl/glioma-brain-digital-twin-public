#!/usr/bin/env bash
# =============================================================================
# freeview_registration.sh -- Verify ACPC-to-T1w registration quality
# =============================================================================
#
# Opens T1w with DWI reference (b0) and FA overlay to check alignment.
#
# Usage:
#   bash scripts/freeview_registration.sh --subject PAT16 --session preop
# =============================================================================

set -euo pipefail

SUBJECT=""
SESSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_registration.sh --subject SUB --session SES"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"
ANAT="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/anat"
REG="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/ses-${SESSION}"

T1W="${ANAT}/${SUB_SES}_desc-preproc_T1w.nii.gz"
DWIREF="${REG}/transforms/dwiref_in_T1w.nii.gz"
FA="${REG}/fa_space-T1w.nii.gz"

ARGS=()

if [[ -f "$T1W" ]]; then
    ARGS+=(-v "${T1W}:name=T1w")
else
    echo "WARNING: T1w not found at ${T1W}"
fi

if [[ -f "$DWIREF" ]]; then
    ARGS+=(-v "${DWIREF}:name=DWI_ref_b0:colormap=heat:opacity=0.5")
else
    echo "WARNING: DWI ref not found at ${DWIREF}"
fi

if [[ -f "$FA" ]]; then
    ARGS+=(-v "${FA}:name=FA_T1w:colormap=jet:opacity=0.5:visible=0")
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "ERROR: No files found. Run the pipeline first."
    exit 1
fi

echo "============================================================"
echo " Freeview: Registration QC -- sub-${SUBJECT} ses-${SESSION}"
echo "============================================================"
echo " Check: DWI ref (b0) edges align with T1w cortical boundaries"
echo "        Toggle FA overlay to verify WM alignment"
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched (PID: $!). Close when done."
