#!/usr/bin/env bash
# =============================================================================
# freesurfer_recon.sh  –  Run FreeSurfer recon-all on a BIDS subject/session
# =============================================================================
# Usage:
#   bash scripts/freesurfer_recon.sh \
#       --bids-dir data/BIDS_preop_postop \
#       --subject  PAT16 \
#       --session  preop \
#       --fs-dir   freesurfer_outputs \
#       [--n-jobs 8] [--dry-run]
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
BIDS_DIR="data/BIDS_preop_postop"
SUBJECT=""
SESSION=""
FS_DIR="freesurfer_outputs"
N_JOBS=4
DRY_RUN=false

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bids-dir) BIDS_DIR="$2"; shift 2 ;;
    --subject)  SUBJECT="$2";  shift 2 ;;
    --session)  SESSION="$2";  shift 2 ;;
    --fs-dir)   FS_DIR="$2";   shift 2 ;;
    --n-jobs)   N_JOBS="$2";   shift 2 ;;
    --dry-run)  DRY_RUN=true;  shift   ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ -z "$SUBJECT" ]] && { echo "ERROR: --subject is required"; exit 1; }
[[ -z "$SESSION" ]] && { echo "ERROR: --session is required"; exit 1; }

# ── Verify FreeSurfer ─────────────────────────────────────────────────────────
if ! command -v recon-all &>/dev/null; then
  echo "ERROR: FreeSurfer not found in PATH."
  echo "  Set FREESURFER_HOME and run: source \$FREESURFER_HOME/SetUpFreeSurfer.sh"
  exit 1
fi
echo "[INFO] FreeSurfer: $(recon-all --version 2>&1 | head -1)"

# ── Find T1w ──────────────────────────────────────────────────────────────────
T1W="$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/anat/sub-${SUBJECT}_ses-${SESSION}_T1w.nii.gz"
if [[ ! -f "$T1W" ]]; then
  echo "ERROR: T1w not found: $T1W"
  exit 1
fi
echo "[INFO] T1w: $T1W"

# ── Run recon-all ─────────────────────────────────────────────────────────────
FS_SUBJ="${FS_DIR}/sub-${SUBJECT}_ses-${SESSION}"
CMD="recon-all -s $FS_SUBJ -i $T1W -all -parallel -openmp $N_JOBS"

echo "[INFO] Output directory: $FS_SUBJ"
echo "[INFO] Command: $CMD"

if $DRY_RUN; then
  echo "[DRY-RUN] Not executing."
else
  mkdir -p "$FS_DIR"
  export SUBJECTS_DIR="$FS_DIR"
  eval "$CMD"
  echo "[DONE] FreeSurfer reconstruction finished: $FS_SUBJ"
fi
