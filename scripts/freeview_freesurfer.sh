#!/usr/bin/env bash
# =============================================================================
# freeview_freesurfer.sh -- Inspect FreeSurfer recon-all outputs in Freeview
# =============================================================================
#
# Opens T1, aparc+aseg overlay, and cortical surfaces for a given
# subject and session.
#
# Usage:
#   bash scripts/freeview_freesurfer.sh --subject PAT16 --session preop
# =============================================================================

set -euo pipefail

SUBJECT=""
SESSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject) SUBJECT="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/freeview_freesurfer.sh --subject SUB --session SES"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session required"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FS="${PROJECT_DIR}/derivatives/freesurfer/sub-${SUBJECT}_ses-${SESSION}"
FS_CLIN="${PROJECT_DIR}/derivatives/freesurfer/sub-${SUBJECT}_ses-${SESSION}_clinical"
HAS_CLINICAL=false
[[ -d "${FS_CLIN}/mri" ]] && HAS_CLINICAL=true

if [[ ! -d "${FS}/mri" && "${HAS_CLINICAL}" == false ]]; then
    echo "ERROR: No FreeSurfer output found for sub-${SUBJECT} ses-${SESSION}"
    echo "  Expected: ${FS}  or  ${FS_CLIN}"
    echo "  Run: bash scripts/run_freesurfer.sh --subject ${SUBJECT} --session ${SESSION}"
    exit 1
fi

BIDS="${PROJECT_DIR}/data/BIDS_preop_postop"
BIDS_T1W="${BIDS}/sub-${SUBJECT}/ses-${SESSION}/anat/sub-${SUBJECT}_ses-${SESSION}_T1w.nii.gz"

ARGS=()

# ---- Base layer: original BIDS T1w ----
[[ -f "${BIDS_T1W}" ]] && ARGS+=(-v "${BIDS_T1W}:name=T1w_BIDS")

# ---- Standard recon-all outputs ----
if [[ -d "${FS}/mri" ]]; then
    [[ -f "${FS}/mri/T1.mgz" ]] && \
        ARGS+=(-v "${FS}/mri/T1.mgz:name=T1_FS:visible=0")
    [[ -f "${FS}/mri/aparc+aseg.mgz" ]] && \
        ARGS+=(-v "${FS}/mri/aparc+aseg.mgz:colormap=lut:opacity=0.4:name=aparc+aseg")
    [[ -f "${FS}/mri/wm.mgz" ]] && \
        ARGS+=(-v "${FS}/mri/wm.mgz:colormap=heat:opacity=0.3:visible=0:name=WM_mask")
    [[ -f "${FS}/surf/lh.white" ]] && \
        ARGS+=(-f "${FS}/surf/lh.white:edgecolor=blue:name=lh.white")
    [[ -f "${FS}/surf/rh.white" ]] && \
        ARGS+=(-f "${FS}/surf/rh.white:edgecolor=blue:name=rh.white")
    [[ -f "${FS}/surf/lh.pial" ]] && \
        ARGS+=(-f "${FS}/surf/lh.pial:edgecolor=red:name=lh.pial")
    [[ -f "${FS}/surf/rh.pial" ]] && \
        ARGS+=(-f "${FS}/surf/rh.pial:edgecolor=red:name=rh.pial")
fi

# ---- Clinical recon-all outputs (if _clinical dir exists) ----
if [[ "${HAS_CLINICAL}" == true ]]; then
    [[ -f "${FS_CLIN}/mri/synthSR.mgz" ]] && \
        ARGS+=(-v "${FS_CLIN}/mri/synthSR.mgz:name=synthSR_clin:visible=0")
    [[ -f "${FS_CLIN}/mri/synthseg.mgz" ]] && \
        ARGS+=(-v "${FS_CLIN}/mri/synthseg.mgz:colormap=lut:opacity=0.4:visible=0:name=synthseg_clin")
    [[ -f "${FS_CLIN}/mri/aparc+aseg.mgz" ]] && \
        ARGS+=(-v "${FS_CLIN}/mri/aparc+aseg.mgz:colormap=lut:opacity=0.4:visible=0:name=aparc+aseg_clin")
    [[ -f "${FS_CLIN}/surf/lh.white" ]] && \
        ARGS+=(-f "${FS_CLIN}/surf/lh.white:edgecolor=cyan:visible=0:name=lh.white_clin")
    [[ -f "${FS_CLIN}/surf/rh.white" ]] && \
        ARGS+=(-f "${FS_CLIN}/surf/rh.white:edgecolor=cyan:visible=0:name=rh.white_clin")
    [[ -f "${FS_CLIN}/surf/lh.pial" ]] && \
        ARGS+=(-f "${FS_CLIN}/surf/lh.pial:edgecolor=yellow:visible=0:name=lh.pial_clin")
    [[ -f "${FS_CLIN}/surf/rh.pial" ]] && \
        ARGS+=(-f "${FS_CLIN}/surf/rh.pial:edgecolor=yellow:visible=0:name=rh.pial_clin")
fi

# ---- Also handle a single-output clinical dir (post-op, no suffix) ----
if [[ -d "${FS}/mri" && "${HAS_CLINICAL}" == false ]]; then
    [[ -f "${FS}/mri/synthSR.mgz" ]] && \
        ARGS+=(-v "${FS}/mri/synthSR.mgz:name=synthSR:visible=0")
    [[ -f "${FS}/mri/synthseg.mgz" ]] && \
        ARGS+=(-v "${FS}/mri/synthseg.mgz:colormap=lut:opacity=0.4:visible=0:name=synthseg")
fi

echo "============================================================"
echo " Freeview: FreeSurfer QC -- sub-${SUBJECT} ses-${SESSION}"
echo "============================================================"
if [[ "${HAS_CLINICAL}" == true ]]; then
    echo ""
    echo " COMPARISON MODE: standard vs clinical"
    echo ""
    echo " Standard recon-all (primary):"
    echo "   T1_FS          -- FreeSurfer conformed T1"
    echo "   aparc+aseg     -- Parcellation overlay"
    echo "   lh/rh.white    -- WM surface (blue)"
    echo "   lh/rh.pial     -- Pial surface (red)"
    echo ""
    echo " Clinical recon-all (comparison, hidden by default):"
    echo "   synthSR_clin       -- SynthSR super-resolved MPRAGE"
    echo "   synthseg_clin      -- SynthSeg segmentation"
    echo "   aparc+aseg_clin    -- Clinical parcellation"
    echo "   lh/rh.white_clin   -- WM surface (cyan)"
    echo "   lh/rh.pial_clin    -- Pial surface (yellow)"
    echo ""
    echo " QC workflow:"
    echo "   1. Navigate to peri-tumoral region"
    echo "   2. Toggle aparc+aseg <-> aparc+aseg_clin (segmentation quality)"
    echo "   3. Toggle lh.pial <-> lh.pial_clin (surface placement near tumor)"
    echo "   4. Compare WM surfaces: blue (standard) vs cyan (clinical)"
else
    echo " Layers (toggle in sidebar):"
    echo "   T1w_BIDS       -- Original BIDS T1w (base layer)"
    echo "   T1_FS          -- FreeSurfer conformed T1 (standard recon-all)"
    echo "   synthSR        -- SynthSR MPRAGE (recon-all-clinical)"
    echo "   aparc+aseg     -- Parcellation overlay"
    echo "   synthseg       -- SynthSeg segmentation (clinical)"
    echo ""
    echo " Check: pial (red) follows cortical ribbon"
    echo "        white (blue) follows WM/GM boundary"
    echo "        aparc+aseg labels are anatomically plausible"
fi
echo "============================================================"

freeview "${ARGS[@]}" &
echo "Freeview launched (PID: $!). Close when done."
