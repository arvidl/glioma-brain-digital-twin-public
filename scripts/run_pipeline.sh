#!/usr/bin/env bash
# =============================================================================
# run_pipeline.sh -- Master orchestration for glioma digital twin pipeline
# Glioma Brain Digital Twin
# =============================================================================
#
# Runs the full preprocessing pipeline for one or more subjects/sessions:
#
#   Step 1:  FreeSurfer recon-all      (geometry extraction)
#   Step 2:  fMRIPrep                  (BOLD preprocessing)
#   Step 3:  QSIPrep                   (DWI preprocessing)
#   Step 4:  MRtrix3 reconstruction    (CSD, DTI, tractography)
#   Step 5:  Co-register to T1w space  (unified coordinate frame)
#   Step 5b: Longitudinal registration (ANTs SyN, per subject)
#   Step 6:  Pre-op vs post-op comparison (per subject)
#
# Steps 2 and 3 can run in parallel (both reuse FreeSurfer from Step 1).
#
# Usage:
#   bash scripts/run_pipeline.sh [OPTIONS]
#
# Options:
#   --subjects PAT16                  Subjects to process (default: PAT16)
#   --sessions preop,postop           Sessions to process (default: all)
#   --container docker|singularity|none  Container engine (default: none)
#   --threads N                       CPU threads per job (default: 8)
#   --mem-mb M                        Memory limit in MB (default: 16000)
#   --parallel                        Run fMRIPrep + QSIPrep in parallel
#   --clinical                        Use recon-all-clinical for ALL sessions
#   --clinical-postop                 Use recon-all-clinical for post-op only,
#                                       standard recon-all for pre-op (recommended)
#   --clinical-compare                Run BOTH standard and clinical on pre-op
#                                       sessions (clinical output gets _clinical
#                                       suffix for comparison); post-op always clinical
#   --skip-freesurfer                 Skip Step 1
#   --skip-fmriprep                   Skip Step 2
#   --skip-qsiprep                    Skip Step 3
#   --skip-mrtrix                     Skip Step 4
#   --skip-register                   Skip Step 5
#   --skip-longitudinal               Skip Step 5b
#   --skip-compare                    Skip Step 6
#   --resseg                          Use RESSEG for cavity masking (Step 5b)
#   --qsiprep-recon                   Run MRtrix3 recon from QSIPrep
#   -h, --help                        Show this help
#
# Prerequisites:
#   - FreeSurfer 8.1.0 (ARM64)
#   - fMRIPrep 25.2.4 (conda cas-fmriprep)
#   - QSIPrep >= 1.1 (conda cas-qsiprep)
#   - FSL 6.0.7.19, AFNI 26.0.09, MRtrix3 3.0.8 (all native ARM64)
#   - FreeSurfer license.txt in project root (or set FS_LICENSE)
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECTS="PAT16"
SESSIONS="preop,postop"
CONTAINER="none"
THREADS=8
MEM_MB=16000
PARALLEL=false
SKIP_FS=false
SKIP_FMRIPREP=false
SKIP_QSIPREP=false
SKIP_MRTRIX=false
SKIP_REGISTER=false
SKIP_LONGITUDINAL=false
SKIP_COMPARE=false
QSIPREP_RECON=""
RESSEG_FLAG=""
FS_MODE="standard"   # standard | clinical | clinical-postop | clinical-compare

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subjects)        SUBJECTS="$2";        shift 2 ;;
        --sessions)        SESSIONS="$2";        shift 2 ;;
        --container)       CONTAINER="$2";       shift 2 ;;
        --threads)         THREADS="$2";         shift 2 ;;
        --mem-mb)          MEM_MB="$2";          shift 2 ;;
        --parallel)        PARALLEL=true;           shift ;;
        --clinical)        FS_MODE="clinical";         shift ;;
        --clinical-postop) FS_MODE="clinical-postop";  shift ;;
        --clinical-compare) FS_MODE="clinical-compare"; shift ;;
        --skip-freesurfer) SKIP_FS=true;             shift ;;
        --skip-fmriprep)   SKIP_FMRIPREP=true;   shift ;;
        --skip-qsiprep)    SKIP_QSIPREP=true;    shift ;;
        --skip-mrtrix)     SKIP_MRTRIX=true;     shift ;;
        --skip-register)   SKIP_REGISTER=true;       shift ;;
        --skip-longitudinal) SKIP_LONGITUDINAL=true; shift ;;
        --skip-compare)    SKIP_COMPARE=true;         shift ;;
        --resseg)          RESSEG_FLAG="--resseg";    shift ;;
        --qsiprep-recon)   QSIPREP_RECON="--recon";  shift ;;
        -h|--help)
            sed -n '2,/^# ====/p' "$0" | head -n -1 | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IFS=',' read -ra SUB_ARRAY <<< "${SUBJECTS}"
IFS=',' read -ra SES_ARRAY <<< "${SESSIONS}"

echo "############################################################"
echo "#  Glioma Brain Digital Twin -- Full Processing Pipeline    #"
echo "############################################################"
echo ""
echo "  Project    : ${PROJECT_DIR}"
echo "  Subjects   : ${SUBJECTS}"
echo "  Sessions   : ${SESSIONS}"
echo "  Container  : ${CONTAINER}"
echo "  Threads    : ${THREADS}"
echo "  Memory     : ${MEM_MB} MB"
  echo "  Parallel   : ${PARALLEL}"
  echo "  FreeSurfer : ${FS_MODE}"
  if [[ "${FS_MODE}" == "clinical-compare" ]]; then
  echo "               post-op -> recon-all-clinical"
  echo "               pre-op  -> standard recon-all + recon-all-clinical (comparison)"
  elif [[ "${FS_MODE}" == "clinical-postop" ]]; then
  echo "               post-op -> recon-all-clinical (robust to resection cavity)"
  echo "               pre-op  -> standard recon-all (better cortical thickness)"
  elif [[ "${FS_MODE}" == "clinical" ]]; then
  echo "               all sessions -> recon-all-clinical"
  else
  echo "               all sessions -> standard recon-all"
  fi
echo ""

PIPELINE_START=$(date +%s)
TOTAL_COMBOS=$(( ${#SUB_ARRAY[@]} * ${#SES_ARRAY[@]} ))
COMBO_IDX=0

# ==== Process each subject x session =========================================
for SUB in "${SUB_ARRAY[@]}"; do
    for SES in "${SES_ARRAY[@]}"; do
        COMBO_IDX=$(( COMBO_IDX + 1 ))
        echo ""
        echo "############################################################"
        echo "#  Processing ${COMBO_IDX}/${TOTAL_COMBOS}: sub-${SUB} ses-${SES}"
        echo "############################################################"

        # -- Step 1: FreeSurfer -----------------------------------------------
        if [[ "${SKIP_FS}" == false ]]; then
            echo ""
            echo "============================================================"
            echo " STEP 1: FreeSurfer -- sub-${SUB} ses-${SES}"
            echo "============================================================"

            # Determine which FreeSurfer mode(s) to run for this session
            RUN_STANDARD=false
            RUN_CLINICAL=false
            CLINICAL_NO_SUFFIX=false

            case "${FS_MODE}" in
                clinical)
                    RUN_CLINICAL=true
                    CLINICAL_NO_SUFFIX=true
                    ;;
                clinical-postop)
                    if [[ "${SES}" == "postop" ]]; then
                        RUN_CLINICAL=true
                        CLINICAL_NO_SUFFIX=true
                    else
                        RUN_STANDARD=true
                    fi
                    ;;
                clinical-compare)
                    if [[ "${SES}" == "postop" ]]; then
                        RUN_CLINICAL=true
                        CLINICAL_NO_SUFFIX=true
                    else
                        RUN_STANDARD=true
                        RUN_CLINICAL=true
                        CLINICAL_NO_SUFFIX=false
                    fi
                    ;;
                *)
                    RUN_STANDARD=true
                    ;;
            esac

            if [[ "${RUN_STANDARD}" == true ]]; then
                echo "  Using standard recon-all"
                bash "${SCRIPT_DIR}/run_freesurfer.sh" \
                    --subject "${SUB}" \
                    --session "${SES}" \
                    --threads "${THREADS}"
            fi

            if [[ "${RUN_CLINICAL}" == true ]]; then
                echo "  Using recon-all-clinical (SynthSeg + SynthDist)"
                if [[ "${CLINICAL_NO_SUFFIX}" == true ]]; then
                    bash "${SCRIPT_DIR}/run_freesurfer_clinical.sh" \
                        --subject "${SUB}" \
                        --session "${SES}" \
                        --threads "${THREADS}" \
                        --no-suffix
                else
                    echo "  (with _clinical suffix for comparison)"
                    bash "${SCRIPT_DIR}/run_freesurfer_clinical.sh" \
                        --subject "${SUB}" \
                        --session "${SES}" \
                        --threads "${THREADS}"
                fi
            fi
        else
            echo "[SKIP] Step 1: FreeSurfer"
        fi

        # -- Steps 2 & 3: fMRIPrep + QSIPrep ---------------------------------
        if [[ "${PARALLEL}" == true ]]; then
            echo ""
            echo "============================================================"
            echo " STEPS 2+3: fMRIPrep and QSIPrep (parallel)"
            echo "============================================================"

            PIDS=()

            if [[ "${SKIP_FMRIPREP}" == false ]]; then
                bash "${SCRIPT_DIR}/run_fmriprep.sh" \
                    --subject "${SUB}" \
                    --session "${SES}" \
                    --container "${CONTAINER}" \
                    --nthreads "${THREADS}" \
                    --mem-mb "${MEM_MB}" &
                PIDS+=($!)
                echo "  fMRIPrep launched (PID ${PIDS[-1]})"
            fi

            if [[ "${SKIP_QSIPREP}" == false ]]; then
                bash "${SCRIPT_DIR}/run_qsiprep.sh" \
                    --subject "${SUB}" \
                    --session "${SES}" \
                    --container "${CONTAINER}" \
                    --nthreads "${THREADS}" \
                    --mem-mb "${MEM_MB}" \
                    ${QSIPREP_RECON} &
                PIDS+=($!)
                echo "  QSIPrep launched (PID ${PIDS[-1]})"
            fi

            FAILED=false
            for pid in "${PIDS[@]}"; do
                if ! wait "${pid}"; then
                    echo "ERROR: Process ${pid} failed."
                    FAILED=true
                fi
            done
            if [[ "${FAILED}" == true ]]; then
                echo "One or more parallel jobs failed for sub-${SUB} ses-${SES}."
                echo "Continuing with next subject/session..."
                continue
            fi

        else
            # Sequential execution
            if [[ "${SKIP_FMRIPREP}" == false ]]; then
                echo ""
                echo "============================================================"
                echo " STEP 2: fMRIPrep -- sub-${SUB} ses-${SES}"
                echo "============================================================"
                bash "${SCRIPT_DIR}/run_fmriprep.sh" \
                    --subject "${SUB}" \
                    --session "${SES}" \
                    --container "${CONTAINER}" \
                    --nthreads "${THREADS}" \
                    --mem-mb "${MEM_MB}"
            else
                echo "[SKIP] Step 2: fMRIPrep"
            fi

            if [[ "${SKIP_QSIPREP}" == false ]]; then
                echo ""
                echo "============================================================"
                echo " STEP 3: QSIPrep -- sub-${SUB} ses-${SES}"
                echo "============================================================"
                bash "${SCRIPT_DIR}/run_qsiprep.sh" \
                    --subject "${SUB}" \
                    --session "${SES}" \
                    --container "${CONTAINER}" \
                    --nthreads "${THREADS}" \
                    --mem-mb "${MEM_MB}" \
                    ${QSIPREP_RECON}
            else
                echo "[SKIP] Step 3: QSIPrep"
            fi
        fi

        # -- Step 4: MRtrix3 reconstruction -----------------------------------
        if [[ "${SKIP_MRTRIX}" == false ]]; then
            echo ""
            echo "============================================================"
            echo " STEP 4: MRtrix3 reconstruction -- sub-${SUB} ses-${SES}"
            echo "============================================================"
            bash "${SCRIPT_DIR}/run_mrtrix_recon.sh" \
                --subject "${SUB}" \
                --session "${SES}" \
                --nthreads "${THREADS}"
        else
            echo "[SKIP] Step 4: MRtrix3 reconstruction"
        fi

        # -- Step 5: Co-register to T1w space ---------------------------------
        if [[ "${SKIP_REGISTER}" == false ]]; then
            echo ""
            echo "============================================================"
            echo " STEP 5: Co-register to T1w space -- sub-${SUB} ses-${SES}"
            echo "============================================================"
            bash "${SCRIPT_DIR}/register_to_t1w.sh" \
                --subject "${SUB}" \
                --session "${SES}" \
                --nthreads "${THREADS}"
        else
            echo "[SKIP] Step 5: Co-register to T1w"
        fi

    done  # sessions

    # -- Step 5b: Longitudinal registration (per subject) ---------------------
    if [[ "${SKIP_LONGITUDINAL}" == false ]]; then
        echo ""
        echo "============================================================"
        echo " STEP 5b: Longitudinal registration (SyN) -- sub-${SUB}"
        echo "============================================================"
        bash "${SCRIPT_DIR}/register_longitudinal.sh" \
            --subject "${SUB}" \
            --session-pre "preop" \
            --session-post "postop" \
            --nthreads "${THREADS}" \
            ${RESSEG_FLAG}
    else
        echo "[SKIP] Step 5b: Longitudinal registration"
    fi

    # -- Step 6: Pre-op vs Post-op comparison (per subject) -------------------
    if [[ "${SKIP_COMPARE}" == false ]]; then
        echo ""
        echo "============================================================"
        echo " STEP 6: Pre-op vs Post-op comparison -- sub-${SUB}"
        echo "============================================================"
        python "${SCRIPT_DIR}/compare_preop_postop.py" \
            --subject "${SUB}" \
            --project-dir "${PROJECT_DIR}"
    else
        echo "[SKIP] Step 6: Pre-op vs Post-op comparison"
    fi

done  # subjects

# ==== QC checklist ============================================================
echo ""
echo "============================================================"
echo " QC Checklist"
echo "============================================================"

QC_FILE="${PROJECT_DIR}/derivatives/pipeline_qc_checklist.md"
{
cat << 'QCEOF'
# Pipeline QC Checklist

QCEOF

for SUB in "${SUB_ARRAY[@]}"; do
    for SES in "${SES_ARRAY[@]}"; do
        cat << SESEOF

## sub-${SUB} ses-${SES}

### FreeSurfer
- [ ] Inspect pial surfaces on T1w (freeview overlay)
- [ ] Check aparc+aseg labels -- especially ventricle/WM boundaries
- [ ] Verify brainstem/thalamic substructure segmentations if available

### fMRIPrep
- [ ] Review HTML report (derivatives/fmriprep/sub-${SUB}.html)
- [ ] Check BOLD-to-T1w registration (BBR cost function convergence)
- [ ] Inspect SyN SDC correction quality in orbitofrontal/temporal regions
- [ ] Review motion parameters -- flag any volumes with FD > 0.5 mm

### QSIPrep
- [ ] Review HTML report (derivatives/qsiprep/sub-${SUB}.html)
- [ ] Check b0-to-T1w overlay -- focus on cortical and ventricle boundaries
- [ ] Inspect eddy correction quality and outlier replacement log
- [ ] Verify b-vector rotation consistency

### Registration QC
- [ ] Overlay dwiref_in_T1w.nii.gz on desc-preproc_T1w.nii.gz
- [ ] Check DTI maps (FA, MD) alignment with T1w anatomy
- [ ] Verify tractography streamlines follow expected white matter tracts

SESEOF
    done
done

for SUB in "${SUB_ARRAY[@]}"; do
    cat << LONGEOF

## Longitudinal QC: sub-${SUB}

### Deformable Registration (Step 5b)
- [ ] Cavity mask covers the resection void (freeview_deformation.sh)
- [ ] Warped pre-op T1w aligns with post-op anatomy
- [ ] High displacement regions are near the cavity (expected)
- [ ] Jacobian near 1.0 in regions far from the lesion
- [ ] Expanding regions (J > 1, e.g. ventricles) make clinical sense

### Pre-op vs Post-op Comparison (Step 6)
- [ ] Pre-op vs post-op T1w alignment quality
- [ ] Resection cavity impact on post-op processing
- [ ] Consistency of parcellation labels across timepoints
- [ ] DTI metric changes in expected regions

LONGEOF
done

} > "${QC_FILE}"

echo "QC checklist written to: ${QC_FILE}"

# ==== Summary =================================================================
PIPELINE_END=$(date +%s)
TOTAL_ELAPSED=$(( PIPELINE_END - PIPELINE_START ))
echo ""
echo "############################################################"
printf "#  Pipeline complete: %02d:%02d:%02d\n" \
    $((TOTAL_ELAPSED/3600)) $(((TOTAL_ELAPSED%3600)/60)) $((TOTAL_ELAPSED%60))
echo "############################################################"
echo ""
echo "Derivatives structure:"
echo "  ${PROJECT_DIR}/derivatives/"
echo "    freesurfer/       -- Surfaces, segmentations, label maps"
echo "    fmriprep/         -- Preprocessed BOLD (T1w + MNI space)"
echo "    qsiprep/          -- Preprocessed DWI (T1w space)"
echo "    mrtrix_recon/     -- CSD, DTI maps, tractography"
echo "    registered_t1w/   -- All modalities co-registered to T1w"
echo "      .../longitudinal/ -- SyN warp, Jacobian, displacement, cavity mask"
echo ""
echo "Next steps:"
echo "  1. Complete the QC checklist: ${QC_FILE}"
echo "  2. Review pre-op vs post-op comparison outputs"
echo "  3. Generate FE mesh from T1w-space derivatives"
echo "  4. Assign material properties from DTI + fOD maps"
