#!/usr/bin/env bash
# =============================================================================
# run_fmriprep.sh -- fMRIPrep preprocessing for glioma digital twin pipeline
# Glioma Brain Digital Twin
# =============================================================================
#
# Runs fMRIPrep on the resting-state BOLD data for a given subject and session,
# producing outputs in both T1w space (for brain mechanics) and MNI space
# (for reference/reporting).
#
# Uses SyN-based fieldmap-less distortion correction (--use-syn-sdc) because
# the BOLD acquisition has only a single phase-encoding direction (AP).
#
# If a pre-computed FreeSurfer directory exists (from run_freesurfer.sh),
# fMRIPrep will reuse it instead of re-running recon-all.
#
# Usage:
#   bash scripts/run_fmriprep.sh --subject PAT16 --session preop \
#       [--container docker|singularity|none] [--nthreads N] [--mem-mb M]
#
# Prerequisites:
#   - fMRIPrep 25.2.4 in the cas-fmriprep conda environment:
#       conda env create -f environment/environment_fmriprep.yml
#   - FreeSurfer license file
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
CONTAINER="none"
NTHREADS=8
MEM_MB=16000

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)   SUBJECT="$2";   shift 2 ;;
        --session)   SESSION="$2";   shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --nthreads)  NTHREADS="$2";  shift 2 ;;
        --mem-mb)    MEM_MB="$2";    shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/run_fmriprep.sh --subject SUB --session SES"
            echo "           [--container docker|singularity|none]"
            echo "           [--nthreads N] [--mem-mb M]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${PROJECT_DIR}/data/BIDS_preop_postop"
OUTPUT_DIR="${PROJECT_DIR}/derivatives/fmriprep"
WORK_DIR="${PROJECT_DIR}/work/fmriprep"
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

# ---- Session-specific BIDS view ---------------------------------------------
# fMRIPrep 25.x discovers all sessions from the BIDS layout and conflicts
# with session-specific filter files.  Work around this by creating a
# temporary BIDS directory (symlinks) that only exposes the target session.
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

BIDS_VIEW="${WORK_DIR}/bids_view_${SUBJECT}_${SESSION}"
rm -rf "${BIDS_VIEW}"
mkdir -p "${BIDS_VIEW}/sub-${SUBJECT}"

for f in "${BIDS_DIR}"/dataset_description.json \
         "${BIDS_DIR}"/participants.tsv \
         "${BIDS_DIR}"/participants.json \
         "${BIDS_DIR}"/README \
         "${BIDS_DIR}"/CHANGES \
         "${BIDS_DIR}"/.bidsignore; do
    [[ -e "$f" ]] && ln -s "$f" "${BIDS_VIEW}/"
done

ln -s "${BIDS_DIR}/sub-${SUBJECT}/ses-${SESSION}" \
      "${BIDS_VIEW}/sub-${SUBJECT}/ses-${SESSION}"

# ---- Build fMRIPrep command --------------------------------------------------
FMRIPREP_ARGS=(
    "${BIDS_VIEW}"
    "${OUTPUT_DIR}"
    participant
    --participant-label "${SUBJECT}"
    --skip-bids-validation
    --output-spaces T1w MNI152NLin2009cAsym
    --use-syn-sdc
    --nthreads "${NTHREADS}"
    --mem-mb "${MEM_MB}"
    --fs-license-file "${FS_LICENSE}"
    --work-dir "${WORK_DIR}"
    --notrack
    --no-msm
)

# Reuse pre-computed FreeSurfer if available.
# fMRIPrep with sessions looks for sub-<label> in the FS subjects dir.
# Our convention is sub-<SUB>_ses-<SES>, so create a symlink if needed.
FS_SUBJ_ID="sub-${SUBJECT}_ses-${SESSION}"
if [[ -d "${FS_DIR}/${FS_SUBJ_ID}/surf" ]]; then
    echo "Found pre-computed FreeSurfer output -- reusing (skipping recon-all)."
    FMRIPREP_ARGS+=(--fs-subjects-dir "${FS_DIR}" --fs-no-reconall)
fi

echo "============================================================"
echo " fMRIPrep -- resting-state BOLD preprocessing"
echo "============================================================"
echo " Subject     : sub-${SUBJECT}"
echo " Session     : ses-${SESSION}"
echo " BIDS dir    : ${BIDS_DIR} (session view: ${BIDS_VIEW})"
echo " Output dir  : ${OUTPUT_DIR}"
echo " Work dir    : ${WORK_DIR}"
echo " Container   : ${CONTAINER}"
echo " Threads     : ${NTHREADS}"
echo " Memory      : ${MEM_MB} MB"
echo " Output spaces: T1w, MNI152NLin2009cAsym"
echo " SDC method  : SyN fieldmap-less"
echo "============================================================"

START_TIME=$(date +%s)

case "${CONTAINER}" in
    docker)
        DOCKER_FMRIPREP_ARGS=(
            /data
            /out
            participant
            --participant-label "${SUBJECT}"
            --output-spaces T1w MNI152NLin2009cAsym
            --use-syn-sdc
            --nthreads "${NTHREADS}"
            --mem-mb "${MEM_MB}"
            --fs-license-file /opt/freesurfer/license.txt
            --work-dir /work
            --notrack
            --stop-on-first-crash
        )
        FS_DOCKER_MOUNT=""
        if [[ -d "${FS_DIR}/${FS_SUBJ_ID}/surf" ]]; then
            DOCKER_FMRIPREP_ARGS+=(--fs-subjects-dir /freesurfer --fs-no-reconall)
            FS_DOCKER_MOUNT="-v ${FS_DIR}:/freesurfer:ro"
        fi
        docker run --rm --platform linux/amd64 \
            -v "${BIDS_VIEW}":/data:ro \
            -v "${OUTPUT_DIR}":/out \
            -v "${WORK_DIR}":/work \
            -v "${FS_LICENSE}":/opt/freesurfer/license.txt:ro \
            ${FS_DOCKER_MOUNT} \
            nipreps/fmriprep:latest \
            "${DOCKER_FMRIPREP_ARGS[@]}"
        ;;
    singularity)
        SINGULARITY_IMG="${FMRIPREP_SINGULARITY_IMG:-${HOME}/images/fmriprep-latest.sif}"
        if [[ ! -f "${SINGULARITY_IMG}" ]]; then
            echo "ERROR: Singularity image not found at ${SINGULARITY_IMG}"
            exit 1
        fi
        singularity run --cleanenv \
            -B "${BIDS_VIEW}":"${BIDS_VIEW}":ro \
            -B "${OUTPUT_DIR}":"${OUTPUT_DIR}" \
            -B "${WORK_DIR}":"${WORK_DIR}" \
            -B "${FS_LICENSE}":/opt/freesurfer/license.txt:ro \
            ${FS_DIR:+-B "${FS_DIR}":"${FS_DIR}":ro} \
            "${SINGULARITY_IMG}" \
            "${FMRIPREP_ARGS[@]}"
        ;;
    none)
        CONDA_BASE=$(conda info --base 2>/dev/null || echo "/opt/anaconda3")
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        if conda env list | grep -q "cas-fmriprep"; then
            conda activate cas-fmriprep
            echo "Activated conda environment: cas-fmriprep"
        else
            echo "WARNING: cas-fmriprep environment not found."
            echo "  Create it with: conda env create -f environment/environment_fmriprep.yml"
        fi

        for tool_dir in \
            "${HOME}/abin" \
            "${FSLDIR:-${HOME}/fsl}/share/fsl/bin" \
            "${FSLDIR:-${HOME}/fsl}/bin" \
            "${HOME}/workbench-build/CommandLine/wb_command.app/Contents/MacOS" \
            "${HOME}/workbench-build/Desktop/wb_view.app/Contents/MacOS" \
            "${FREESURFER_HOME:-/Applications/freesurfer/8.1.0}/bin"; do
            if [[ -d "${tool_dir}" ]]; then
                export PATH="${tool_dir}:${PATH}"
            fi
        done
        echo "External tools added to PATH (AFNI, FSL, Workbench, FreeSurfer)"

        fmriprep "${FMRIPREP_ARGS[@]}"
        ;;
    *)
        echo "ERROR: Unknown container type '${CONTAINER}'. Use docker, singularity, or none."
        exit 1 ;;
esac

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo "============================================================"
echo " fMRIPrep finished in $(( ELAPSED / 3600 ))h $(( (ELAPSED % 3600) / 60 ))m"
echo " Output: ${OUTPUT_DIR}"
echo "============================================================"
echo ""
echo "Key outputs for brain mechanics (T1w-space):"
echo "  Preprocessed BOLD:"
echo "    sub-${SUBJECT}/ses-${SESSION}/func/*_space-T1w_desc-preproc_bold.nii.gz"
echo "  Confounds:"
echo "    sub-${SUBJECT}/ses-${SESSION}/func/*_desc-confounds_timeseries.tsv"
echo "  Brain mask:"
echo "    sub-${SUBJECT}/ses-${SESSION}/func/*_space-T1w_desc-brain_mask.nii.gz"
echo ""
echo "NOTE: For brain mechanics, use T1w-space outputs only."
echo "      MNI-space outputs are for reporting/visualization."
