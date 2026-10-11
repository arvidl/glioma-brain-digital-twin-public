#!/usr/bin/env bash
# =============================================================================
# freeview_dti.sh -- Inspect DTI scalar maps and tractography in Freeview
# =============================================================================
#
# Opens FA, MD, AD, RD maps (in T1w space if available, otherwise raw)
# and whole-brain tractography (.trk) if present.
#
# Usage:
#   bash scripts/freeview_dti.sh --subject PAT16 --session preop
# =============================================================================

set -euo pipefail

SUBJECT=""
SESSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_dti.sh --subject SUB --session SES"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REG="${PROJECT_DIR}/derivatives/registered_t1w/sub-${SUBJECT}/ses-${SESSION}"
RAW="${PROJECT_DIR}/derivatives/mrtrix_recon/sub-${SUBJECT}/ses-${SESSION}"

# Prefer T1w-space versions, fall back to raw
ARGS=()

add_map() {
    local name="$1" cmap="$2"
    local t1w_path="${REG}/${name}_space-T1w.nii.gz"
    local raw_path="${RAW}/${name}.nii.gz"
    if [[ -f "${t1w_path}" ]]; then
        ARGS+=(-v "${t1w_path}:name=${name}_T1w:colormap=${cmap}")
    elif [[ -f "${raw_path}" ]]; then
        ARGS+=(-v "${raw_path}:name=${name}_raw:colormap=${cmap}")
    else
        echo "SKIP: ${name} (not found)"
    fi
}

add_map fa jet
add_map md cool
add_map ad autumn
add_map rd winter

# Also load T1w as underlay if available
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"
T1W="${PROJECT_DIR}/derivatives/fmriprep/sub-${SUBJECT}/ses-${SESSION}/anat/${SUB_SES}_desc-preproc_T1w.nii.gz"
[[ -f "${T1W}" ]] && ARGS+=(-v "${T1W}:name=T1w:visible=0")

# Tractography (.trk in T1w space)
TRK_100K="${REG}/whole_brain_space-T1w_100k.trk"
TRK_FULL="${REG}/whole_brain_space-T1w.trk"
if [[ -f "${TRK_100K}" ]]; then
    ARGS+=(-tract "${TRK_100K}")
    echo "Tractography: $(basename "${TRK_100K}")"
elif [[ -f "${TRK_FULL}" ]]; then
    ARGS+=(-tract "${TRK_FULL}")
    echo "Tractography: $(basename "${TRK_FULL}")"
else
    echo "SKIP: tractography .trk (not found -- convert .tck with tck2trk.py)"
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "ERROR: No DTI maps found. Run the pipeline first."
    exit 1
fi

echo "============================================================"
echo " Freeview: DTI + tractography -- sub-${SUBJECT} ses-${SESSION}"
echo "============================================================"
echo " FA: WM should be bright (0.4-0.8), GM dim (0.1-0.3)"
echo " MD: CSF bright, WM/GM intermediate"
echo " Toggle T1w underlay for anatomical reference"
echo " Tracts: colour by direction (red=L-R, green=A-P, blue=S-I)"
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched (PID: $!). Close when done."
