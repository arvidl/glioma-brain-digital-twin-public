#!/usr/bin/env bash
# =============================================================================
# run_qsiprep.sh -- QSIPrep preprocessing for glioma digital twin pipeline
# Glioma Brain Digital Twin
# =============================================================================
#
# Runs QSIPrep on the multi-shell diffusion data for a given subject and
# session, producing preprocessed DWI in T1w space at 1.0 mm resolution
# (matching the T1w grid for FE mesh mapping).
#
# The glioma dataset has AP+PA DWI pairs, enabling proper susceptibility
# distortion correction via the reverse phase-encoding b0 images.
#
# After preprocessing, the script optionally runs MRtrix3 reconstruction
# (CSD, DTI, tractography) if --recon is specified.
#
# Usage:
#   bash scripts/run_qsiprep.sh --subject PAT16 --session preop \
#       [--container docker|singularity|none] [--nthreads N] [--mem-mb M]
#       [--recon] [--output-resolution R]
#
# Prerequisites:
#   - QSIPrep >= 1.1 in the cas-qsiprep conda environment:
#       conda env create -f environment/environment_qsiprep.yml
#   - FreeSurfer license file
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
CONTAINER="none"
NTHREADS=8
MEM_MB=16000
RUN_RECON=false
OUTPUT_RES="1.0"

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)           SUBJECT="$2";    shift 2 ;;
        --session)           SESSION="$2";     shift 2 ;;
        --container)         CONTAINER="$2";   shift 2 ;;
        --nthreads)          NTHREADS="$2";    shift 2 ;;
        --mem-mb)            MEM_MB="$2";      shift 2 ;;
        --recon)             RUN_RECON=true;    shift ;;
        --output-resolution) OUTPUT_RES="$2";  shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/run_qsiprep.sh --subject SUB --session SES"
            echo "           [--container docker|singularity|none]"
            echo "           [--nthreads N] [--mem-mb M]"
            echo "           [--recon] [--output-resolution R]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop"
OUTPUT_DIR="${PROJECT_DIR}/derivatives/qsiprep"
WORK_DIR="${PROJECT_DIR}/work/qsiprep"
FS_DIR="${PROJECT_DIR}/derivatives/freesurfer"

# FreeSurfer license
FS_LICENSE=""
for candidate in \
    "${PROJECT_DIR}/license.txt" \
    "${FREESURFER_HOME:-/dev/null}/license.txt" \
    "${HOME}/license.txt" \
    "${HOME}/freesurfer/license.txt"; do
    if [[ -f "${candidate}" ]]; then
        FS_LICENSE="${candidate}"
        break
    fi
done

if [[ -z "${FS_LICENSE}" ]]; then
    echo "ERROR: FreeSurfer license not found."
    echo "  Place license.txt in the project root or set FREESURFER_HOME."
    exit 1
fi

# ---- BIDS session filter ----------------------------------------------------
FILTER_FILE="${WORK_DIR}/bids_filter_${SUBJECT}_${SESSION}.json"
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"
cat > "${FILTER_FILE}" << FILTEREOF
{
  "dwi":  {"datatype": "dwi",  "session": "${SESSION}", "suffix": "dwi"},
  "t1w":  {"datatype": "anat", "session": "${SESSION}", "suffix": "T1w"}
}
FILTEREOF

# ---- Build QSIPrep command ---------------------------------------------------
QSIPREP_ARGS=(
    "${BIDS_DIR}"
    "${OUTPUT_DIR}"
    participant
    --participant-label "${SUBJECT}"
    --bids-filter-file "${FILTER_FILE}"
    --output-resolution "${OUTPUT_RES}"
    --nthreads "${NTHREADS}"
    --mem-mb "${MEM_MB}"
    --fs-license-file "${FS_LICENSE}"
    --work-dir "${WORK_DIR}"
    --notrack
)

echo "============================================================"
echo " QSIPrep -- multi-shell diffusion preprocessing"
echo "============================================================"
echo " Subject         : sub-${SUBJECT}"
echo " Session         : ses-${SESSION}"
echo " BIDS dir        : ${BIDS_DIR}"
echo " Output dir      : ${OUTPUT_DIR}"
echo " Work dir        : ${WORK_DIR}"
echo " Container       : ${CONTAINER}"
echo " Threads         : ${NTHREADS}"
echo " Memory          : ${MEM_MB} MB"
echo " Output res      : ${OUTPUT_RES} mm"
echo " SDC method      : reverse-PE (AP+PA b0 pairs)"
echo " Reconstruction  : ${RUN_RECON}"
echo "============================================================"

START_TIME=$(date +%s)

run_qsiprep() {
    local args=("$@")
    case "${CONTAINER}" in
        docker)
            local docker_args=(
                /data
                /out
                participant
                --participant-label "${SUBJECT}"
                --bids-filter-file /work/bids_filter_${SUBJECT}_${SESSION}.json
                --output-resolution "${OUTPUT_RES}"
                --nthreads "${NTHREADS}"
                --mem-mb "${MEM_MB}"
                --fs-license-file /opt/freesurfer/license.txt
                --work-dir /work
                --notrack
                --stop-on-first-crash
            )
            docker run --rm --platform linux/amd64 \
                -v "${BIDS_DIR}":/data:ro \
                -v "${OUTPUT_DIR}":/out \
                -v "${WORK_DIR}":/work \
                -v "${FS_LICENSE}":/opt/freesurfer/license.txt:ro \
                pennlinc/qsiprep:latest \
                "${docker_args[@]}"
            ;;
        singularity)
            SINGULARITY_IMG="${QSIPREP_SINGULARITY_IMG:-${HOME}/images/qsiprep-latest.sif}"
            if [[ ! -f "${SINGULARITY_IMG}" ]]; then
                echo "ERROR: Singularity image not found at ${SINGULARITY_IMG}"
                exit 1
            fi
            singularity run --cleanenv \
                -B "${BIDS_DIR}":"${BIDS_DIR}":ro \
                -B "${OUTPUT_DIR}":"${OUTPUT_DIR}" \
                -B "${WORK_DIR}":"${WORK_DIR}" \
                -B "${FS_LICENSE}":/opt/freesurfer/license.txt:ro \
                "${SINGULARITY_IMG}" \
                "${args[@]}"
            ;;
        none)
            CONDA_BASE=$(conda info --base 2>/dev/null || echo "/opt/anaconda3")
            source "${CONDA_BASE}/etc/profile.d/conda.sh"
            if conda env list | grep -q "cas-qsiprep"; then
                conda activate cas-qsiprep
                echo "Activated conda environment: cas-qsiprep"
            else
                echo "WARNING: cas-qsiprep environment not found."
                echo "  Create it with: conda env create -f environment/environment_qsiprep.yml"
            fi

            for tool_dir in \
                "${HOME}/mrtrix3/bin" \
                "${HOME}/abin" \
                "${HOME}/dsi_studio/dsi_studio.app/Contents/MacOS" \
                "${FSLDIR:-${HOME}/fsl}/share/fsl/bin" \
                "${FSLDIR:-${HOME}/fsl}/bin" \
                "${HOME}/workbench-build/CommandLine/wb_command.app/Contents/MacOS" \
                "${HOME}/workbench-build/Desktop/wb_view.app/Contents/MacOS"; do
                if [[ -d "${tool_dir}" ]]; then
                    export PATH="${tool_dir}:${PATH}"
                fi
            done
            echo "External tools added to PATH (MRtrix3, AFNI, DSI Studio, FSL, Workbench)"

            # DSI Studio "Hou" (2025+) saves .src.gz.sz instead of .src.gz
            WRAPPER="${PROJECT_DIR}/scripts/dsi_studio_wrapper.sh"
            if [[ -x "${WRAPPER}" ]]; then
                DSI_WRAPPER_BIN=$(mktemp -d)
                cp "${WRAPPER}" "${DSI_WRAPPER_BIN}/dsi_studio"
                chmod +x "${DSI_WRAPPER_BIN}/dsi_studio"
                export PATH="${DSI_WRAPPER_BIN}:${PATH}"
                echo "DSI Studio wrapper installed (handles .src.gz.sz rename)"
            fi

            qsiprep "${args[@]}"
            ;;
        *)
            echo "ERROR: Unknown container type '${CONTAINER}'."
            exit 1 ;;
    esac
}

# ---- Step 1: Preprocessing --------------------------------------------------
echo "[$(date '+%H:%M:%S')] Running QSIPrep preprocessing ..."
run_qsiprep "${QSIPREP_ARGS[@]}"

# ---- Step 2: Reconstruction (optional) --------------------------------------
if [[ "${RUN_RECON}" == true ]]; then
    echo ""
    echo "[$(date '+%H:%M:%S')] Running MRtrix3 reconstruction ..."
    bash "${PROJECT_DIR}/scripts/run_mrtrix_recon.sh" \
        --subject "${SUBJECT}" \
        --session "${SESSION}" \
        --nthreads "${NTHREADS}"
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo "============================================================"
echo " QSIPrep finished in $(( ELAPSED / 3600 ))h $(( (ELAPSED % 3600) / 60 ))m"
echo " Output: ${OUTPUT_DIR}"
echo "============================================================"
echo ""
echo "Key outputs for brain mechanics:"
echo "  Preprocessed DWI (T1w space, ${OUTPUT_RES} mm):"
echo "    sub-${SUBJECT}/ses-${SESSION}/dwi/*_space-T1w_desc-preproc_dwi.nii.gz"
echo "  b-values / b-vectors (rotated):"
echo "    sub-${SUBJECT}/ses-${SESSION}/dwi/*_space-T1w_desc-preproc_dwi.{bval,bvec}"
echo "  Brain mask in T1w space:"
echo "    sub-${SUBJECT}/ses-${SESSION}/dwi/*_space-T1w_desc-brain_mask.nii.gz"
if [[ "${RUN_RECON}" == true ]]; then
    echo ""
    echo "  Reconstruction outputs (MRtrix3):"
    echo "    DTI: FA, MD, AD, RD maps"
    echo "    CSD: fiber orientation distributions (fODFs)"
    echo "    Tractography: whole-brain streamlines"
fi
