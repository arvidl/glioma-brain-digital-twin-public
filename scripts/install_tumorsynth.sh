#!/usr/bin/env bash
# =============================================================================
# install_tumorsynth.sh -- Install TumorSynth (nnUNet v1.7) for tumor segmentation
# Glioma Brain Digital Twin
# =============================================================================
#
# Creates a conda environment with nnUNet v1.7 and downloads the TumorSynth
# model weights for whole-tumor + healthy tissue segmentation.
#
# Prerequisites:
#   - conda (Anaconda or Miniconda)
#   - FreeSurfer 8.1.0 (for mri_synthstrip, mri_robust_register)
#   - ~2 GB disk space for model weights
#
# Usage:
#   bash scripts/install_tumorsynth.sh [--inner-tumor] [--nnunet-dir DIR]
#
# Options:
#   --inner-tumor    Also download inner tumor (ET/NET/necrosis) weights
#   --nnunet-dir DIR Root directory for nnUNet installation (default: ~/nnUNet)
#
# References:
#   Wu J et al. (2026) TumorSynth: Integrated Brain Tumor and Tissue
#   Segmentation in Brain MRI Scans of any Resolution and Contrast.
#   Radiology: Imaging Cancer.
#
#   https://surfer.nmr.mgh.harvard.edu/fswiki/TumorSynth
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NNUNET_DIR="${HOME}/nnUNet"
INSTALL_INNER=false
ENV_NAME="nnUNet_v1.7"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --inner-tumor) INSTALL_INNER=true; shift ;;
        --nnunet-dir)  NNUNET_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: bash scripts/install_tumorsynth.sh [--inner-tumor] [--nnunet-dir DIR]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "============================================================"
echo " TumorSynth Installation"
echo "============================================================"
echo " nnUNet directory : ${NNUNET_DIR}"
echo " Conda env name   : ${ENV_NAME}"
echo " Inner tumor      : ${INSTALL_INNER}"
echo "============================================================"
echo ""

# ---- Step 1: Locate conda.sh -----------------------------------------------
CONDA_SH=""
if [[ -f "${CONDA_PREFIX}/etc/profile.d/conda.sh" ]]; then
    CONDA_SH="${CONDA_PREFIX}/etc/profile.d/conda.sh"
elif [[ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]]; then
    CONDA_SH="/opt/anaconda3/etc/profile.d/conda.sh"
elif [[ -f "${HOME}/anaconda3/etc/profile.d/conda.sh" ]]; then
    CONDA_SH="${HOME}/anaconda3/etc/profile.d/conda.sh"
elif [[ -f "${HOME}/miniconda3/etc/profile.d/conda.sh" ]]; then
    CONDA_SH="${HOME}/miniconda3/etc/profile.d/conda.sh"
else
    # Try to find it from .zshrc or .bashrc
    CONDA_SH=$(grep -h 'conda.sh' ~/.zshrc ~/.bashrc 2>/dev/null | head -1 | sed "s/.*source //;s/'//g;s/\"//g;s/ .*//" || true)
fi

if [[ -z "${CONDA_SH}" || ! -f "${CONDA_SH}" ]]; then
    echo "ERROR: Could not locate conda.sh. Please set CONDA_SH manually."
    echo "  Example: export CONDA_SH=/opt/anaconda3/etc/profile.d/conda.sh"
    exit 1
fi
echo "[1/5] Found conda.sh: ${CONDA_SH}"

# ---- Step 2: Download model weights ----------------------------------------
echo ""
echo "[2/5] Downloading model weights ..."
echo ""
echo "  MANUAL STEP REQUIRED:"
echo "  The TumorSynth weights must be downloaded manually from UCL SharePoint."
echo ""
echo "  1. Whole tumor (required):"
echo "     https://liveuclac-my.sharepoint.com/:u:/g/personal/rmapfpr_ucl_ac_uk/EWsIGJOFbD9MiPyQnGhjGHwBquaWhxJfEAzbfs6v5BvFzA?e=JQHlSQ"
echo "     -> Save to: ${PROJECT_DIR}/tools/TumourSynth_v1.0.zip"
echo ""

if [[ "${INSTALL_INNER}" == true ]]; then
    echo "  2. Inner tumor (optional):"
    echo "     https://liveuclac-my.sharepoint.com/:u:/g/personal/rmapfpr_ucl_ac_uk/IQCJJdWxSqPsQpKaxW3yFWikARbdkwcgnY8nkd-5HUezl3Q?e=E7i74D"
    echo "     -> Save to: ${PROJECT_DIR}/tools/Task003_InnerTumor.zip"
    echo ""
fi

TOOLS_DIR="${PROJECT_DIR}/tools"
mkdir -p "${TOOLS_DIR}"

WHOLE_TUMOR_ZIP=""
for candidate in \
    "${TOOLS_DIR}/TumourSynth_v1.0.zip" \
    "${TOOLS_DIR}/TumorSynth_v1.0.zip" \
    "${TOOLS_DIR}/tumorsynth_v1.0.zip"; do
    if [[ -f "${candidate}" ]]; then
        WHOLE_TUMOR_ZIP="${candidate}"
        break
    fi
done

if [[ -z "${WHOLE_TUMOR_ZIP}" ]]; then
    echo "  Waiting for download. Place the zip file at:"
    echo "    ${TOOLS_DIR}/TumourSynth_v1.0.zip  (or TumorSynth_v1.0.zip)"
    echo ""
    echo "  Then re-run this script."
    exit 0
fi
echo "  Found: ${WHOLE_TUMOR_ZIP}"

# Unpack whole tumor weights
WHOLE_TUMOR_DIR="${TOOLS_DIR}/Task002_Tumor"
if [[ ! -d "${WHOLE_TUMOR_DIR}" ]]; then
    echo "  Unpacking whole tumor weights ..."
    cd "${TOOLS_DIR}"
    unzip -q "${WHOLE_TUMOR_ZIP}"
    mv TumourSynth_v1.0 Task002_Tumor
    cd "${PROJECT_DIR}"
fi
echo "  Whole tumor weights: ${WHOLE_TUMOR_DIR}"

# Unpack inner tumor weights if requested
if [[ "${INSTALL_INNER}" == true ]]; then
    INNER_ZIP="${TOOLS_DIR}/Task003_InnerTumor.zip"
    INNER_DIR="${TOOLS_DIR}/Task003_InnerTumor"
    if [[ -f "${INNER_ZIP}" && ! -d "${INNER_DIR}" ]]; then
        echo "  Unpacking inner tumor weights ..."
        cd "${TOOLS_DIR}"
        unzip -q "${INNER_ZIP}"
        cd "${PROJECT_DIR}"
        echo "  Inner tumor weights: ${INNER_DIR}"
    fi
fi

# ---- Step 3: Create conda env manually --------------------------------------
# The FreeSurfer-provided create_nnUNet_v1.7_env.sh script fails on Apple
# Silicon because python-gdcm (a dicom2nifti dependency) cannot build from
# source.  We don't need DICOM support (all data is NIfTI), so we create
# the environment manually and install nnUNet without dicom2nifti.

echo ""
echo "[3/5] Creating conda environment '${ENV_NAME}' ..."
echo "  (This may take several minutes)"
echo ""

source "${CONDA_SH}"

if conda env list 2>/dev/null | grep -q "${ENV_NAME}"; then
    echo "  Environment '${ENV_NAME}' already exists -- skipping creation."
else
    # Create env with Python 3.8 + PyTorch (CPU-only for Mac)
    conda create -y -n "${ENV_NAME}" python=3.8 -c conda-forge
    conda activate "${ENV_NAME}"

    # Install PyTorch CPU (Apple Silicon compatible)
    pip install torch==2.1.2 torchvision==0.16.2

    # Clone and install nnUNet v1.7 with dicom2nifti excluded
    TMPDIR_NNUNET=$(mktemp -d)
    git clone https://github.com/MIC-DKFZ/nnUNet.git "${TMPDIR_NNUNET}/nnUNet"
    cd "${TMPDIR_NNUNET}/nnUNet"
    git checkout 7f1e273fa1021dd2ff00df2ada781ee3133096ef

    # Remove dicom2nifti from requirements (we don't need DICOM import)
    sed -i.bak 's/dicom2nifti/# dicom2nifti/' setup.py 2>/dev/null || \
        sed -i '' 's/dicom2nifti/# dicom2nifti/' setup.py

    pip install .
    cd "${PROJECT_DIR}"
    rm -rf "${TMPDIR_NNUNET}"

    # macOS uses "spawn" multiprocessing by default, which cannot pickle the
    # lambdas scattered throughout nnUNet (nd_softmax, nnUNetTrainerV2, etc.).
    # Force "fork" start method via sitecustomize.py for the entire env.
    SITE_DIR="$(python -c 'import site; print(site.getsitepackages()[0])')"
    cat >> "${SITE_DIR}/sitecustomize.py" << 'SCEOF'

# Patch: force "fork" multiprocessing on macOS for nnUNet compatibility.
import multiprocessing, sys
if sys.platform == "darwin":
    try:
        multiprocessing.set_start_method("fork", force=True)
    except RuntimeError:
        pass
SCEOF
    echo "  Patched multiprocessing start method -> fork (macOS)"

    # Install additional dependencies
    pip install nibabel matplotlib pandas SimpleITK scipy

    conda deactivate
    echo "  Environment '${ENV_NAME}' created successfully."
fi

# ---- Step 4: Set up nnUNet directory structure and env vars -----------------
echo ""
echo "[4/5] Setting up nnUNet directory structure ..."

NNUNET_RAW="${NNUNET_DIR}/nnUNet_raw_data_base"
NNUNET_PREPROCESSED="${NNUNET_DIR}/nnUNet_preprocessed"
NNUNET_RESULTS="${NNUNET_DIR}/nnUNet_trained_models"

mkdir -p "${NNUNET_RAW}" "${NNUNET_PREPROCESSED}" "${NNUNET_RESULTS}"
mkdir -p "${NNUNET_RESULTS}/nnUNet/3d_fullres"

# Copy model weights to the nnUNet results directory
if [[ -d "${WHOLE_TUMOR_DIR}" ]]; then
    TARGET="${NNUNET_RESULTS}/nnUNet/3d_fullres/Task002_Tumor"
    if [[ ! -d "${TARGET}" ]]; then
        cp -r "${WHOLE_TUMOR_DIR}" "${TARGET}"
        echo "  Whole tumor weights -> ${TARGET}"
    else
        echo "  Whole tumor weights already in place."
    fi
fi

if [[ "${INSTALL_INNER}" == true && -d "${TOOLS_DIR}/Task003_InnerTumor" ]]; then
    TARGET="${NNUNET_RESULTS}/nnUNet/3d_fullres/Task003_InnerTumor"
    if [[ ! -d "${TARGET}" ]]; then
        cp -r "${TOOLS_DIR}/Task003_InnerTumor" "${TARGET}"
        echo "  Inner tumor weights -> ${TARGET}"
    fi
fi

# Create env vars file
ENVVARS_FILE="${TOOLS_DIR}/nnUNet_v1.7_path.sh"
cat > "${ENVVARS_FILE}" << ENVEOF
export nnUNet_raw_data_base="${NNUNET_RAW}"
export nnUNet_preprocessed="${NNUNET_PREPROCESSED}"
export RESULTS_FOLDER="${NNUNET_RESULTS}"
ENVEOF
echo "  Env vars file: ${ENVVARS_FILE}"

# Auto-source on conda activate
source "${CONDA_SH}"
conda activate "${ENV_NAME}"
mkdir -p "${CONDA_PREFIX}/etc/conda/activate.d"
cp "${ENVVARS_FILE}" "${CONDA_PREFIX}/etc/conda/activate.d/"
echo "  nnUNet env vars will auto-source on conda activate."
conda deactivate

# ---- Step 5: Clone TumorSynth main script -----------------------------------
echo ""
echo "[5/5] Cloning TumorSynth main script ..."

TUMORSYNTH_DIR="${TOOLS_DIR}/TumorSynth"
if [[ ! -d "${TUMORSYNTH_DIR}" ]]; then
    git clone --depth 1 https://github.com/fprados/TumorSynth.git "${TUMORSYNTH_DIR}"
else
    echo "  TumorSynth repo already present."
fi

echo ""
echo "============================================================"
echo " TumorSynth installation complete"
echo "============================================================"
echo ""
echo " To use:"
echo "   conda activate ${ENV_NAME}"
echo "   source ${TOOLS_DIR}/nnUNet_v1.7_path.sh  # if not auto-sourced"
echo "   bash ${TUMORSYNTH_DIR}/mri_TumorSynth --help"
echo ""
echo " To run the feasibility test on all 4 T1w images:"
echo "   bash scripts/test_tumorsynth.sh"
echo ""
echo " See docs/preprocessing_pipeline_plan.md for details."
