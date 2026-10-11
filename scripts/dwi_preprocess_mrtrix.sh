#!/usr/bin/env bash
# =============================================================================
# dwi_preprocess_mrtrix.sh  –  Full MRtrix3 DWI preprocessing pipeline
# =============================================================================
# Steps:
#   1. Convert to .mif
#   2. Denoise (dwidenoise)
#   3. Gibbs ringing removal (mrdegibbs)
#   4. Motion & distortion correction – requires AP+PA pair (dwifslpreproc)
#   5. Bias field correction (dwibiascorrect)
#   6. Brain mask (dwi2mask)
#   7. Response function estimation (dwi2response)
#   8. Fibre ODF (dwi2fod msmt_csd)
#   9. Tractography (tckgen  – 10 M streamlines)
#  10. SIFT2 weights (tcksift2)
#
# Usage:
#   bash scripts/dwi_preprocess_mrtrix.sh \
#       --bids-dir data/BIDS_preop_postop \
#       --subject  PAT16 \
#       --session  preop \
#       --out-dir  mrtrix_outputs \
#       [--n-tracks 10000000] [--n-threads 8] [--dry-run]
# =============================================================================
set -euo pipefail

BIDS_DIR="data/BIDS_preop_postop"
SUBJECT=""
SESSION=""
OUT_DIR="mrtrix_outputs"
N_TRACKS=10000000
THREADS=8
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bids-dir)  BIDS_DIR="$2";  shift 2 ;;
    --subject)   SUBJECT="$2";   shift 2 ;;
    --session)   SESSION="$2";   shift 2 ;;
    --out-dir)   OUT_DIR="$2";   shift 2 ;;
    --n-tracks)  N_TRACKS="$2";  shift 2 ;;
    --n-threads) THREADS="$2";   shift 2 ;;
    --dry-run)   DRY_RUN=true;   shift   ;;
    -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$SUBJECT" || -z "$SESSION" ]] && { echo "ERROR: --subject and --session required"; exit 1; }

for tool in mrconvert dwidenoise mrdegibbs dwifslpreproc dwibiascorrect dwi2mask dwi2response dwi2fod tckgen tcksift2; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found (install MRtrix3)"; exit 1; }
done

# ── Path setup ────────────────────────────────────────────────────────────────
SUB_SES="sub-${SUBJECT}_ses-${SESSION}"
BIDS_DWI="$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/dwi"
WORK="$OUT_DIR/$SUB_SES"
DRY_RUN && echo "[DRY-RUN] Would create $WORK" || mkdir -p "$WORK"

AP_NII="$BIDS_DWI/${SUB_SES}_acq-AP_dwi.nii.gz"
AP_BVAL="$BIDS_DWI/${SUB_SES}_acq-AP_dwi.bval"
AP_BVEC="$BIDS_DWI/${SUB_SES}_acq-AP_dwi.bvec"
PA_NII="$BIDS_DWI/${SUB_SES}_acq-PA_dwi.nii.gz"
PA_BVAL="$BIDS_DWI/${SUB_SES}_acq-PA_dwi.bval"
PA_BVEC="$BIDS_DWI/${SUB_SES}_acq-PA_dwi.bvec"

run() {
  echo "[CMD] $*"
  $DRY_RUN || eval "$*"
}

# ── Pipeline ─────────────────────────────────────────────────────────────────
echo "=== DWI preprocessing: $SUB_SES ==="

# 1. Convert AP to .mif (embeds bvals/bvecs)
run "mrconvert $AP_NII -fslgrad $AP_BVEC $AP_BVAL $WORK/dwi_ap.mif -force -nthreads $THREADS"

# 2. Denoise
run "dwidenoise $WORK/dwi_ap.mif $WORK/dwi_denoised.mif -nthreads $THREADS -force"

# 3. Gibbs ringing removal
run "mrdegibbs $WORK/dwi_denoised.mif $WORK/dwi_degibbs.mif -nthreads $THREADS -force"

# 4. Motion & EPI distortion correction using AP+PA pair
run "mrconvert $PA_NII -fslgrad $PA_BVEC $PA_BVAL $WORK/dwi_pa.mif -force -nthreads $THREADS"
run "dwiextract $WORK/dwi_pa.mif - -bzero | mrmath - mean $WORK/b0_PA.mif -axis 3 -force"
run "dwiextract $WORK/dwi_degibbs.mif - -bzero | mrmath - mean $WORK/b0_AP.mif -axis 3 -force"
run "mrcat $WORK/b0_AP.mif $WORK/b0_PA.mif -axis 3 $WORK/b0_AP_PA.mif -force"
run "dwifslpreproc $WORK/dwi_degibbs.mif $WORK/dwi_preproc.mif \
     -pe_dir AP -rpe_pair $WORK/b0_AP_PA.mif \
     -eddy_options ' --slm=linear --repol' \
     -nthreads $THREADS -force"

# 5. Bias field correction
run "dwibiascorrect ants $WORK/dwi_preproc.mif $WORK/dwi_biascorr.mif -nthreads $THREADS -force"

# 6. Brain mask
run "dwi2mask $WORK/dwi_biascorr.mif $WORK/mask.mif -nthreads $THREADS -force"

# 7. Response function estimation (dhollander multi-shell algorithm)
run "dwi2response dhollander $WORK/dwi_biascorr.mif \
     $WORK/response_wm.txt $WORK/response_gm.txt $WORK/response_csf.txt \
     -mask $WORK/mask.mif -nthreads $THREADS -force"

# 8. Multi-tissue CSD
run "dwi2fod msmt_csd $WORK/dwi_biascorr.mif \
     $WORK/response_wm.txt  $WORK/wm_fod.mif \
     $WORK/response_gm.txt  $WORK/gm_fod.mif \
     $WORK/response_csf.txt $WORK/csf_fod.mif \
     -mask $WORK/mask.mif -nthreads $THREADS -force"

# 9. Tractography (iFOD2)
run "tckgen $WORK/wm_fod.mif $WORK/tracks_${N_TRACKS}.tck \
     -seed_image $WORK/mask.mif -mask $WORK/mask.mif \
     -select $N_TRACKS -maxlength 250 -nthreads $THREADS -force"

# 10. SIFT2
run "tcksift2 $WORK/tracks_${N_TRACKS}.tck $WORK/wm_fod.mif \
     $WORK/sift2_weights.txt -nthreads $THREADS -force"

echo "=== Preprocessing complete: $WORK ==="
