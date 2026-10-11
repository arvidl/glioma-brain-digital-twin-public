#!/usr/bin/env bash
# =============================================================================
# run_freesurfer_clinical.sh -- FreeSurfer recon-all-clinical for pathological
#                               anatomy (tumor, resection cavity, edema)
# Glioma Brain Digital Twin
# =============================================================================
#
# Uses recon-all-clinical (SynthSeg + SynthDist + SynthSR) instead of standard
# recon-all.  Advantages for glioma patients:
#
#   - SynthSeg is robust to pathological anatomy (tumors, resection cavities,
#     mass effect, edema) where atlas-based priors in standard recon-all fail
#   - SynthDist predicts signed distance functions for surface placement,
#     avoiding intensity-driven errors near lesion boundaries
#   - SynthSR synthesizes a clean 1mm MPRAGE for visualization
#   - Works on any MRI contrast and resolution without retraining
#   - Faster than standard recon-all (~1-2h vs 6-8h)
#
# The output directory structure is nearly identical to standard recon-all,
# so downstream scripts (fMRIPrep BBR, co-registration, FE meshing) work
# without modification.
#
# Tested with:
#   - FreeSurfer 8.1.0 on Apple Silicon (MBP M4 Max, 128 GB unified memory)
#
# Usage:
#   bash scripts/run_freesurfer_clinical.sh --subject PAT16 --session preop [--threads N]
#
# When to use this vs. standard recon-all:
#   - POST-OP sessions:     Always use recon-all-clinical (resection cavity)
#   - PRE-OP with tumor:    Recommended (tumor may distort anatomy)
#   - Normal anatomy:       Standard recon-all gives better cortical thickness
#
# References:
#   - Gopinath et al. (2025) Medical Image Analysis
#     "Recon-all-clinical: Cortical surface reconstruction and analysis of
#     heterogeneous clinical brain MRI"
#   - Billot et al. (2023) Medical Image Analysis, SynthSeg
#   - Iglesias et al. (2023) Science Advances, SynthSR
#
# Prerequisites:
#   - FreeSurfer >= 7.4 (8.1.0 recommended) with recon-all-clinical.sh
#   - source $FREESURFER_HOME/SetUpFreeSurfer.sh
#   - Valid license at $FREESURFER_HOME/license.txt (or ~/license.txt,
#     or project root license.txt, or set FS_LICENSE)
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
THREADS=8
OUTPUT_SUFFIX="_clinical"

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)  SUBJECT="$2"; shift 2 ;;
        --session)  SESSION="$2"; shift 2 ;;
        --threads)  THREADS="$2"; shift 2 ;;
        --no-suffix) OUTPUT_SUFFIX=""; shift ;;
        -h|--help)
            echo "Usage: bash scripts/run_freesurfer_clinical.sh --subject SUB --session SES [--threads N] [--no-suffix]"
            echo ""
            echo "Options:"
            echo "  --subject SUB    Subject ID (e.g. PAT16)"
            echo "  --session SES    Session label (e.g. preop, postop)"
            echo "  --threads N      Number of CPU threads (default: 8)"
            echo "  --no-suffix      Name output same as standard recon-all (no '_clinical' suffix)"
            echo "                   Use when recon-all-clinical is the sole reconstruction"
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
FS_SUBJ_ID="sub-${SUBJECT}_ses-${SESSION}${OUTPUT_SUFFIX}"

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

# ---- Validate ---------------------------------------------------------------
if [[ ! -f "${T1W}" ]]; then
    echo "ERROR: T1w not found at ${T1W}"
    exit 1
fi

if ! command -v recon-all-clinical.sh &>/dev/null; then
    echo "ERROR: recon-all-clinical.sh not found in PATH."
    echo "  Requires FreeSurfer >= 7.4. Verify with:"
    echo "    which recon-all-clinical.sh"
    echo "  If using FreeSurfer 8.1.0:"
    echo "    source \$FREESURFER_HOME/SetUpFreeSurfer.sh"
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
echo " FreeSurfer recon-all-clinical for glioma digital twin"
echo "============================================================"
echo " FreeSurfer    : ${FS_VERSION}"
echo " Subject       : sub-${SUBJECT}"
echo " Session       : ses-${SESSION}"
echo " T1w input     : ${T1W}"
echo " SUBJECTS_DIR  : ${SUBJECTS_DIR}"
echo " Output ID     : ${FS_SUBJ_ID}"
echo " License       : ${FS_LICENSE}"
echo " Threads       : ${THREADS}"
echo " Platform      : $(uname -m) / $(uname -s)"
echo "============================================================"
echo ""
echo " Uses SynthSeg (robust to pathology) + SynthDist (distance-"
echo " based surface placement) + SynthSR (1mm MPRAGE synthesis)."
echo " Recommended for post-op scans with resection cavities and"
echo " pre-op scans with significant tumor mass effect."
echo "============================================================"

START_TIME=$(date +%s)

# ---- Run recon-all-clinical -------------------------------------------------
echo ""

if [[ -f "${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/aparc+aseg.mgz" ]]; then
    echo "[$(date '+%H:%M:%S')] recon-all-clinical already complete for ${FS_SUBJ_ID} -- skipping"
else
    echo "[$(date '+%H:%M:%S')] Running recon-all-clinical ..."
    echo "  (typically 1-2 hours, faster than standard recon-all)"
    echo ""

    recon-all-clinical.sh \
        -i "${T1W}" \
        -subjid "${FS_SUBJ_ID}" \
        -threads "${THREADS}" \
        -sdir "${SUBJECTS_DIR}"
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo " recon-all-clinical finished in $(( ELAPSED / 3600 ))h $(( (ELAPSED % 3600) / 60 ))m"
echo " Output: ${SUBJECTS_DIR}/${FS_SUBJ_ID}/"
echo "============================================================"

# ---- Verify key outputs -----------------------------------------------------
KEY_FILES=(
    "mri/aparc+aseg.mgz"
    "mri/aseg.mgz"
    "mri/synthSR.mgz"
    "mri/synthseg.mgz"
    "mri/norm.mgz"
    "surf/lh.white"
    "surf/rh.white"
    "surf/lh.pial"
    "surf/rh.pial"
    "label/lh.aparc.annot"
    "label/rh.aparc.annot"
)

echo ""
echo "Key outputs:"
ALL_OK=true
for f in "${KEY_FILES[@]}"; do
    if [[ -f "${SUBJECTS_DIR}/${FS_SUBJ_ID}/${f}" ]]; then
        echo "  [OK] ${f}"
    else
        echo "  [--] ${f}  (MISSING)"
        ALL_OK=false
    fi
done

if [[ "${ALL_OK}" == false ]]; then
    echo ""
    echo "WARNING: Some expected outputs are missing."
    echo "  Check the FreeSurfer log for errors:"
    echo "    ${SUBJECTS_DIR}/${FS_SUBJ_ID}/scripts/recon-all-clinical.log"
fi

echo ""
echo "Clinical-specific outputs:"
echo "  SynthSeg segmentation : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/synthseg.mgz"
echo "  SynthSR MPRAGE        : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/synthSR.mgz"
echo "  SynthDist surfaces    : ${SUBJECTS_DIR}/${FS_SUBJ_ID}/mri/synthsurf.mgz"
echo ""
echo "Inspect with freeview:"
echo "  bash scripts/freeview_freesurfer.sh --subject ${SUBJECT} --session ${SESSION}"
if [[ -n "${OUTPUT_SUFFIX}" ]]; then
    echo ""
    echo "NOTE: Output uses suffix '${OUTPUT_SUFFIX}'. If recon-all-clinical is"
    echo "  the sole reconstruction, re-run with --no-suffix so downstream"
    echo "  scripts find outputs at the standard location."
fi
