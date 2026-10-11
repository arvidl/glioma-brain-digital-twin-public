#!/usr/bin/env bash
# =============================================================================
# setup_env.sh  –  Create and verify the finse26 conda environment
# =============================================================================
# Usage:
#   bash environment/setup_env.sh [--force]
#
#   --force   Remove existing environment before rebuilding
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/environment/environment.yml"
ENV_NAME="finse26"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "=============================================================="
echo " Finse 2026  –  Glioma Brain Digital Twin"
echo " Environment setup"
echo "=============================================================="
echo ""

# ── Detect OS / architecture ─────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
info "Platform: $OS / $ARCH"

case "$OS-$ARCH" in
  Darwin-arm64)   PLATFORM="apple-silicon" ;;
  Darwin-x86_64)  PLATFORM="intel-mac"     ;;
  Linux-x86_64)
    if command -v nvidia-smi &>/dev/null; then
      PLATFORM="linux-cuda"
    else
      PLATFORM="linux-cpu"
    fi
    ;;
  *) warn "Unsupported platform $OS-$ARCH; proceeding with generic setup."
     PLATFORM="generic" ;;
esac
info "Detected profile: $PLATFORM"

# ── Check conda ───────────────────────────────────────────────────────────────
if ! command -v conda &>/dev/null; then
  error "conda not found. Install Miniforge (recommended): https://github.com/conda-forge/miniforge"
fi
CONDA_BASE="$(conda info --base)"
# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

# ── Optional --force flag ─────────────────────────────────────────────────────
FORCE=false
for arg in "$@"; do [[ "$arg" == "--force" ]] && FORCE=true; done

if conda env list | grep -q "^${ENV_NAME} "; then
  if $FORCE; then
    warn "Removing existing environment '$ENV_NAME' (--force)…"
    conda env remove -n "$ENV_NAME" -y
  else
    warn "Environment '$ENV_NAME' already exists. Use --force to rebuild."
    info "Activating existing environment for verification…"
    conda activate "$ENV_NAME"
    python "$REPO_ROOT/scripts/check_env.py"
    exit 0
  fi
fi

# ── Create environment ────────────────────────────────────────────────────────
info "Creating conda environment from $ENV_FILE …"
conda env create -f "$ENV_FILE" -y
conda activate "$ENV_NAME"
success "Conda environment '$ENV_NAME' created."

# ── Platform-specific PyTorch install ─────────────────────────────────────────
case "$PLATFORM" in
  apple-silicon)
    info "Installing PyTorch with MPS (Apple Silicon acceleration)…"
    pip install --upgrade torch torchvision torchaudio --quiet
    python -c "import torch; print('MPS available:', torch.backends.mps.is_available())"
    ;;
  linux-cuda)
    CUDA_VER="$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+')"
    info "CUDA $CUDA_VER detected. Installing PyTorch with CUDA support…"
    CUDA_TAG="cu$(echo $CUDA_VER | tr -d '.')"
    # Map to nearest supported wheel (12.1 → cu121, 11.8 → cu118)
    if (( $(echo "$CUDA_VER >= 12.0" | bc -l) )); then
      CUDA_TAG="cu121"
    else
      CUDA_TAG="cu118"
    fi
    pip install torch torchvision torchaudio \
        --index-url "https://download.pytorch.org/whl/$CUDA_TAG" --quiet
    python -c "import torch; print('CUDA available:', torch.cuda.is_available())"
    ;;
  *)
    info "Installing CPU-only PyTorch…"
    pip install torch torchvision torchaudio --index-url \
        https://download.pytorch.org/whl/cpu --quiet
    ;;
esac

# ── MRtrix3 hint ─────────────────────────────────────────────────────────────
echo ""
info "MRtrix3 is NOT installed by conda (it needs system libraries)."
case "$PLATFORM" in
  apple-silicon|intel-mac)
    info "  → Install via Homebrew:  brew install mrtrix3"
    ;;
  linux-cuda|linux-cpu)
    info "  → Install via conda-forge:  conda install -n $ENV_NAME -c conda-forge mrtrix3"
    info "    or from source:  https://www.mrtrix.org/download/"
    ;;
esac

# ── FreeSurfer hint ───────────────────────────────────────────────────────────
if ! command -v recon-all &>/dev/null; then
  warn "FreeSurfer 'recon-all' not found in PATH."
  info "  → Set FREESURFER_HOME and source \$FREESURFER_HOME/SetUpFreeSurfer.sh"
  info "  → See docs/platform_notes.md for details."
fi

# ── Verify full environment ───────────────────────────────────────────────────
echo ""
info "Running environment verification…"
python "$REPO_ROOT/scripts/check_env.py"

echo ""
success "Setup complete!"
echo ""
echo "  Activate:   conda activate $ENV_NAME"
echo "  Notebooks:  cd $REPO_ROOT && jupyter lab"
echo ""
