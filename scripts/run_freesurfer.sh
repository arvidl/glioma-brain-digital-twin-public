#!/usr/bin/env bash
# =============================================================================
# run_freesurfer.sh -- FreeSurfer recon-all for glioma digital twin pipeline
# Glioma Brain Digital Twin
# =============================================================================
#
# Run FreeSurfer recon-all on a T1w volume for a given subject and session.
# The resulting surfaces and segmentation volumes are used by fMRIPrep (BBR),
# downstream co-registration, and FE mesh generation.
#
# Tested with:
#   - FreeSurfer 8.1.0 on Apple Silicon (MBP M4 Max, 128 GB unified memory)
#
# Usage:
#   bash scripts/run_freesurfer.sh --subject PAT16 --session preop [--threads N]
#   bash scripts/run_freesurfer.sh --subject PAT16 --session preop --extra-seg-only
#
# Prerequisites:
#   - FreeSurfer 8.1.0 installed and $FREESURFER_HOME set
#   - source $FREESURFER_HOME/SetUpFreeSurfer.sh
#   - Valid license at $FREESURFER_HOME/license.txt (or ~/license.txt,
#     or project root license.txt, or set FS_LICENSE)
#   - For additional segmentations: Matlab Runtime R2019b
#     Install with:  fs_install_mcr R2019b
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
THREADS=8
EXTRA_SEG_ONLY=false

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)        SUBJECT="$2"; shift 2 ;;
        --session)        SESSION="$2"; shift 2 ;;
        --threads)        THREADS="$2"; shift 2 ;;
        --extra-seg-only) EXTRA_SEG_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: bash scripts/run_freesurfer.sh --subject SUB --session SES [--threads N] [--extra-seg-only]"
            echo ""
            echo "Options:"
            echo "  --subject SUB      Subject ID (e.g. PAT16)"
            echo "  --session SES      Session label (e.g. preop, postop)"
            echo "  --threads N        Number of CPU threads (default: 8)"
            echo "  --extra-seg-only   Skip recon-all, only run additional segmentations"
            echo "                     (brainstem, thalamic nuclei, hippocampal subfields)"
            echo ""
            echo "For additional segmentations, install the Matlab Runtime first:"
            echo "  fs_install_mcr R2019b"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop"
SUBJECTS_DIR="${PROJECT_DIR}/derivatives/freesurfer"
T1W="${BIDS_DIR}/sub-${SUBJECT}/ses-${SESSION}/anat/sub-${SUBJECT}_ses-${SESSION}_T1w.nii.gz"
FS_SUBJ_ID="sub-${SUBJECT}_ses-${SESSION}"

# FreeSurfer license: look in common locations
if [[ -z "${FS_LICENSE:-}" ]]; then
    for candidate in \
        "${PROJECT_DIR}/license.txt" \
        "${FREESURFER_HOME:-/dev/null}/license.txt" \
        "${HOME}/license.txt" \
        "${HOME}/freesurfer/license.txt"; do
        if [[ -f "${candidate}" ]]; then
            export FS_LICENSE="${candidate}"
            break
        fi
    done
fi

if [[ -z "${FS_LICENSE:-}" ]]; then
    echo "ERROR: FreeSurfer license not found."
    echo "  Place license.txt in the project root, ~/license.txt, or set FS_LICENSE."
    exit 1
fi

# ---- Validate inputs --------------------------------------------------------
if [[ ! -f "${T1W}" ]]; then
    echo "ERROR: T1w not found at ${T1W}"
    exit 1
fi

mkdir -p "${SUBJECTS_DIR}"
export SUBJECTS_DIR

# ---- Print info -------------------------------------------------------------
FS_VERSION="unknown"
if command -v recon-all &>/dev/null; then
    FS_VERSION=$(recon-all --version 2>/dev/null | head -1 || echo "unknown")
fi

echo "============================================================"
echo " FreeSurfer segmentation for glioma digital twin"
echo "============================================================"
echo " FreeSurfer   : ${FS_VERSION}"
echo " Subject      : sub-${SUBJECT}"
echo " Session      : ses-${SESSION}"
echo " T1w input    : ${T1W}"
echo " SUBJECTS_DIR : ${SUBJECTS_DIR}"
echo " License      : ${FS_LICENSE}"
echo " Threads      : ${THREADS}"
echo " Platform     : $(uname -m) / $(uname -s)"
echo " Mode         : $(if ${EXTRA_SEG_ONLY}; then echo 'additional segmentations only'; else echo 'full recon-all + additional segmentations'; fi)"
echo "============================================================"

START_TIME=$(date +%s)

# ---- Step 1: recon-all ------------------------------------------------------
if [[ "${EXTRA_SEG_ONLY}" == false ]]; then
    if [[ -f "${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/aparc+aseg.mgz" ]]; then
        echo "[$(date '+%H:%M:%S')] recon-all already complete for ${FS_SUBJ_ID} -- skipping"
    else
        echo "[$(date '+%H:%M:%S')] Running FreeSurfer recon-all ..."
        recon-all \
            -s "${FS_SUBJ_ID}" \
            -i "${T1W}" \
            -all \
            -threads "${THREADS}"
    fi
else
    if [[ ! -f "${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/aparc+aseg.mgz" ]]; then
        echo "ERROR: recon-all output not found. Run without --extra-seg-only first."
        exit 1
    fi
    echo "[$(date '+%H:%M:%S')] Skipping recon-all (--extra-seg-only mode)"
fi

# ---- Step 2: Additional segmentations for mechanics -------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Running additional segmentations ..."
echo "  (Requires Matlab Runtime R2019b -- install with: fs_install_mcr R2019b)"
echo ""

MCR_AVAILABLE=true

echo "  Brainstem substructures ..."
if ! segmentBS.sh "${FS_SUBJ_ID}" "${SUBJECTS_DIR}" 2>&1; then
    echo "  WARNING: segmentBS.sh failed -- see note about Matlab Runtime above."
    MCR_AVAILABLE=false
fi

echo "  Thalamic nuclei ..."
if ! segmentThalamicNuclei.sh "${FS_SUBJ_ID}" "${SUBJECTS_DIR}" 2>&1; then
    echo "  WARNING: segmentThalamicNuclei.sh failed -- see note about Matlab Runtime above."
    MCR_AVAILABLE=false
fi

echo "  Hippocampal subfields ..."
if ! segmentHA_T1.sh "${FS_SUBJ_ID}" "${SUBJECTS_DIR}" 2>&1; then
    echo "  WARNING: segmentHA_T1.sh failed -- see note about Matlab Runtime above."
    MCR_AVAILABLE=false
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo "============================================================"
echo " FreeSurfer finished in $(( ELAPSED / 3600 ))h $(( (ELAPSED % 3600) / 60 ))m"
echo " Output: ${SUBJECTS_DIR}/${FS_SUBJ_ID}/"
echo "============================================================"

if [[ "${MCR_AVAILABLE}" == false ]]; then
    echo ""
    echo "NOTE: Additional segmentations failed (Matlab Runtime not found)."
    echo "  To fix, run:"
    echo "    fs_install_mcr R2019b"
    echo "  Then re-run additional segmentations only:"
    echo "    bash scripts/run_freesurfer.sh --subject ${SUBJECT} --session ${SESSION} --extra-seg-only"
fi

echo ""
echo "Key outputs for brain mechanics:"
echo "  Surfaces  : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/surf/{lh,rh}.{white,pial}"
echo "  Labels    : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/aparc+aseg.mgz"
echo "  Brain mask: ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/brainmask.mgz"
echo "  WM mask   : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/wm.mgz"
echo ""
echo "Inspect with freeview:"
echo "  freeview -v ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/T1.mgz \\"
echo "           -v ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/aparc+aseg.mgz:colormap=lut:opacity=0.4 \\"
echo "           -f ${SUBJECTS_DIR}/${FS_SUBJ_ID}/surf/lh.white:edgecolor=blue \\"
echo "           -f ${SUBJECTS_DIR}/${FS_SUBJ_ID}/surf/lh.pial:edgecolor=red"
