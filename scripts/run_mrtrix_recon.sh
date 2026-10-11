#!/usr/bin/env bash
# =============================================================================
# run_mrtrix_recon.sh -- MRtrix3 reconstruction on QSIPrep-preprocessed DWI
# Glioma Brain Digital Twin
# =============================================================================
#
# Performs multi-shell multi-tissue CSD, DTI fitting, and whole-brain
# tractography using MRtrix3 -- equivalent to QSIRecon's
# mrtrix_multishell_msmt pipeline but run natively on ARM64.
#
# Requires:
#   - MRtrix3 (~/mrtrix3/bin or on PATH)
#   - QSIPrep preprocessed outputs in derivatives/qsiprep
#
# Usage:
#   bash scripts/run_mrtrix_recon.sh --subject PAT16 --session preop \
#       [--nthreads N] [--streamlines N]
# =============================================================================

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
SUBJECT=""
SESSION=""
NTHREADS=8
N_STREAMLINES=10000000

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subject)      SUBJECT="$2";       shift 2 ;;
        --session)      SESSION="$2";       shift 2 ;;
        --nthreads)     NTHREADS="$2";      shift 2 ;;
        --streamlines)  N_STREAMLINES="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/run_mrtrix_recon.sh --subject SUB --session SES"
            echo "           [--nthreads N] [--streamlines N]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ---- Paths ------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QSIPREP_DIR="${PROJECT_DIR}/derivatives/qsiprep"
RECON_DIR="${PROJECT_DIR}/derivatives/mrtrix_recon/sub-${SUBJECT}/ses-${SESSION}"
DWI_DIR="${QSIPREP_DIR}/sub-${SUBJECT}/ses-${SESSION}/dwi"

# Add MRtrix3 to PATH
export PATH="${HOME}/mrtrix3/bin:${PATH}"

# ---- Verify inputs ----------------------------------------------------------
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"
DWI_NII="${DWI_DIR}/${SUB_SES}_space-T1w_desc-preproc_dwi.nii.gz"
BVAL="${DWI_DIR}/${SUB_SES}_space-T1w_desc-preproc_dwi.bval"
BVEC="${DWI_DIR}/${SUB_SES}_space-T1w_desc-preproc_dwi.bvec"
MASK="${DWI_DIR}/${SUB_SES}_space-T1w_desc-brain_mask.nii.gz"

# Fall back to ACPC-space naming if T1w-space files not found
if [[ ! -f "${DWI_NII}" ]]; then
    DWI_NII="${DWI_DIR}/${SUB_SES}_space-ACPC_desc-preproc_dwi.nii.gz"
    BVAL="${DWI_DIR}/${SUB_SES}_space-ACPC_desc-preproc_dwi.bval"
    BVEC="${DWI_DIR}/${SUB_SES}_space-ACPC_desc-preproc_dwi.bvec"
    MASK="${DWI_DIR}/${SUB_SES}_space-ACPC_desc-brain_mask.nii.gz"
fi

for f in "$DWI_NII" "$BVAL" "$BVEC" "$MASK"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Required input not found: $f"
        exit 1
    fi
done

echo "============================================================"
echo " MRtrix3 Reconstruction -- multi-shell multi-tissue CSD"
echo "============================================================"
echo " Subject      : sub-${SUBJECT}"
echo " Session      : ses-${SESSION}"
echo " DWI input    : ${DWI_NII}"
echo " Mask         : ${MASK}"
echo " Output dir   : ${RECON_DIR}"
echo " Threads      : ${NTHREADS}"
echo " Streamlines  : ${N_STREAMLINES}"
echo "============================================================"

mkdir -p "${RECON_DIR}"
START_TIME=$(date +%s)

# ---- Step 1: Convert to MIF format -----------------------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 1/6: Converting to MIF format ..."
DWI_MIF="${RECON_DIR}/dwi.mif"

# QSIPrep may write bvals with one value per line instead of the FSL
# single-row format that MRtrix3 expects, and the b-values may not
# form clean shells. Round to nearest 500 s/mm^2.
BVAL_FIXED="${RECON_DIR}/bval_fixed.txt"
echo "  Preparing gradient table for MRtrix3 ..."
awk '{
    for (i=1; i<=NF; i++) {
        b = $i + 0;
        if (b < 50) s = 0;
        else s = int((b + 250) / 500) * 500;
        printf "%d ", s;
    }
}' "${BVAL}" | sed 's/ $/\n/' > "${BVAL_FIXED}"
echo "  Rounded b-values to shells: $(tr ' ' '\n' < "${BVAL_FIXED}" | sort -un | tr '\n' ' ')"
BVAL_USE="${BVAL_FIXED}"

if [[ ! -f "${DWI_MIF}" ]]; then
    mrconvert "${DWI_NII}" "${DWI_MIF}" \
        -fslgrad "${BVEC}" "${BVAL_USE}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

MASK_MIF="${RECON_DIR}/mask.mif"
if [[ ! -f "${MASK_MIF}" ]]; then
    mrconvert "${MASK}" "${MASK_MIF}" -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

# ---- Step 2: Estimate tissue response functions ----------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 2/6: Estimating tissue response functions (dhollander) ..."
WM_RESPONSE="${RECON_DIR}/wm_response.txt"
GM_RESPONSE="${RECON_DIR}/gm_response.txt"
CSF_RESPONSE="${RECON_DIR}/csf_response.txt"
if [[ ! -f "${WM_RESPONSE}" ]]; then
    dwi2response dhollander "${DWI_MIF}" \
        "${WM_RESPONSE}" "${GM_RESPONSE}" "${CSF_RESPONSE}" \
        -mask "${MASK_MIF}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

# ---- Step 3: Multi-shell multi-tissue CSD ----------------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 3/6: Multi-shell multi-tissue CSD (msmt_csd) ..."
WM_FOD="${RECON_DIR}/wm_fod.mif"
GM_FOD="${RECON_DIR}/gm_fod.mif"
CSF_FOD="${RECON_DIR}/csf_fod.mif"
if [[ ! -f "${WM_FOD}" ]]; then
    dwi2fod msmt_csd "${DWI_MIF}" \
        "${WM_RESPONSE}" "${WM_FOD}" \
        "${GM_RESPONSE}" "${GM_FOD}" \
        "${CSF_RESPONSE}" "${CSF_FOD}" \
        -mask "${MASK_MIF}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

# Normalize FODs for tractography
echo ""
echo "  Normalizing FODs ..."
WM_FOD_NORM="${RECON_DIR}/wm_fod_norm.mif"
GM_FOD_NORM="${RECON_DIR}/gm_fod_norm.mif"
CSF_FOD_NORM="${RECON_DIR}/csf_fod_norm.mif"
if [[ ! -f "${WM_FOD_NORM}" ]]; then
    mtnormalise "${WM_FOD}" "${WM_FOD_NORM}" \
        "${GM_FOD}" "${GM_FOD_NORM}" \
        "${CSF_FOD}" "${CSF_FOD_NORM}" \
        -mask "${MASK_MIF}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

# ---- Step 4: DTI fitting ---------------------------------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 4/6: Fitting diffusion tensors (DTI) ..."
TENSOR="${RECON_DIR}/dti.mif"
if [[ ! -f "${TENSOR}" ]]; then
    dwi2tensor "${DWI_MIF}" "${TENSOR}" \
        -mask "${MASK_MIF}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

echo "  Extracting FA, MD, AD, RD ..."
FA="${RECON_DIR}/fa.mif"
MD="${RECON_DIR}/md.mif"
AD="${RECON_DIR}/ad.mif"
RD="${RECON_DIR}/rd.mif"
if [[ ! -f "${FA}" ]]; then
    tensor2metric "${TENSOR}" \
        -fa "${FA}" -adc "${MD}" -ad "${AD}" -rd "${RD}" \
        -mask "${MASK_MIF}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

echo "  Exporting NIfTI versions ..."
for map in fa md ad rd; do
    MIF="${RECON_DIR}/${map}.mif"
    NII="${RECON_DIR}/${map}.nii.gz"
    if [[ ! -f "${NII}" ]]; then
        mrconvert "${MIF}" "${NII}" -nthreads "${NTHREADS}" -force
    fi
done

# ---- Step 5: Whole-brain tractography --------------------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 5/6: Whole-brain tractography (${N_STREAMLINES} streamlines) ..."
TCK="${RECON_DIR}/whole_brain.tck"
if [[ ! -f "${TCK}" ]]; then
    tckgen "${WM_FOD_NORM}" "${TCK}" \
        -algorithm iFOD2 \
        -select "${N_STREAMLINES}" \
        -seed_dynamic "${WM_FOD_NORM}" \
        -mask "${MASK_MIF}" \
        -maxlength 250 \
        -minlength 10 \
        -cutoff 0.06 \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

# ---- Step 6: SIFT2 ---------------------------------------------------------
echo ""
echo "[$(date '+%H:%M:%S')] Step 6/6: SIFT2 streamline filtering ..."
SIFT2_WEIGHTS="${RECON_DIR}/sift2_weights.txt"
if [[ ! -f "${SIFT2_WEIGHTS}" ]]; then
    tcksift2 "${TCK}" "${WM_FOD_NORM}" "${SIFT2_WEIGHTS}" \
        -nthreads "${NTHREADS}" -force
else
    echo "  (cached)"
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo " MRtrix3 reconstruction finished in $(( ELAPSED / 3600 ))h $(( (ELAPSED % 3600) / 60 ))m $(( ELAPSED % 60 ))s"
echo " Output: ${RECON_DIR}"
echo "============================================================"
echo ""
echo "Key outputs for brain mechanics:"
echo "  DTI scalar maps:"
echo "    fa.nii.gz  -- fractional anisotropy"
echo "    md.nii.gz  -- mean diffusivity"
echo "    ad.nii.gz  -- axial diffusivity"
echo "    rd.nii.gz  -- radial diffusivity"
echo ""
echo "  Fiber orientation distributions:"
echo "    wm_fod_norm.mif  -- WM fiber orientations (for anisotropic stiffness)"
echo "    gm_fod_norm.mif  -- GM component"
echo "    csf_fod_norm.mif -- CSF component"
echo ""
echo "  Tractography:"
echo "    whole_brain.tck    -- ${N_STREAMLINES} streamlines (iFOD2)"
echo "    sift2_weights.txt  -- SIFT2 weights for quantitative analysis"
