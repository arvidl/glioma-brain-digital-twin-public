# Installation Guide — Glioma Brain Digital Twin

Comprehensive platform-specific setup instructions for the Finse 2026 workshop.

---

## Table of Contents

1. [Prerequisites](#prerequisites-common-to-all-platforms)
2. [Apple Silicon (M4 Max, ARM64)](#apple-silicon-m4-max-arm64)
3. [Linux + CUDA (Ubuntu 24.04, NVIDIA RTX)](#linux--cuda-ubuntu-2404-nvidia-rtx)
4. [Google Colab](#google-colab)
5. [Verify Installation](#verify-installation)
6. [Download Data](#download-data)
7. [Running Notebooks](#running-notebooks)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites (Common to All Platforms)

Before proceeding with platform-specific installation, ensure you have:

### 1. Git

Git is required to clone the repository.

**macOS:**
```bash
# Using Homebrew (install Homebrew if needed: https://brew.sh)
brew install git
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install git
```

**Windows:**
Download and install from [git-scm.com](https://git-scm.com/download/win).

### 2. Miniforge or Mambaforge

**Strongly recommended over Anaconda** due to smaller footprint and faster package resolution.

- **Miniforge**: [github.com/conda-forge/miniforge](https://github.com/conda-forge/miniforge)
- **Mambaforge**: [github.com/conda-forge/mambaforge](https://github.com/conda-forge/mambaforge) (includes mamba for faster installs)

Download the appropriate installer for your platform and architecture (see platform-specific sections below).

### 3. Disk Space

Ensure you have **at least 10 GB of free disk space** for:
- Conda environment: ~5 GB
- BIDS imaging data (pre/post-op for both patients): ~500 MB
- Processing outputs and caches: ~2-4 GB

Check available space:
```bash
df -h  # macOS/Linux
```

### 4. Clone the Repository

```bash
git clone https://github.com/arvidl/glioma-brain-digital-twin-public.git
cd glioma-brain-digital-twin

# Download imaging data (~400 MB)
python data/download_data.py
```

---

## Apple Silicon (M4 Max, ARM64)

### Step 1: Install Miniforge for ARM

Download the **ARM64 (Apple Silicon)** installer from [Miniforge releases](https://github.com/conda-forge/miniforge/releases):

```bash
# Download (example for M-series Macs)
curl -L https://github.com/conda-forge/miniforge/releases/download/23.3.1-1/Miniforge3-23.3.1-1-MacOSX-arm64.sh \
  -o ~/miniforge-installer.sh

# Install
bash ~/miniforge-installer.sh -b -p ~/miniforge3

# Initialize conda
~/miniforge3/bin/conda init zsh  # or bash if you use bash
```

Restart your terminal and verify:
```bash
conda --version
# Output: conda 23.3.1 (or similar)
```

### Step 2: Create Environment

```bash
cd glioma-brain-digital-twin
conda env create -f environment/environment_osx_arm64.yml
conda activate finse26
```

The ARM-specific environment file ensures compatibility with macOS native libraries.

### Step 3: Install PyTorch with MPS (Metal Performance Shaders)

PyTorch's Metal Performance Shaders enables GPU acceleration on Apple Silicon:

```bash
# Uninstall CPU version if present
pip uninstall torch torchvision torchaudio -y

# Install with MPS
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

Actually, MPS is included by default in recent PyTorch. Verify:

```bash
python -c "import torch; print(torch.backends.mps.is_available())"
# Output: True
```

If output is `False`, update PyTorch:
```bash
pip install --upgrade torch torchvision torchaudio
```

### Step 4: Install MRtrix3

```bash
brew install mrtrix3
```

Verify:
```bash
mrinfo --version
```

### Step 5: Verify FreeSurfer

FreeSurfer is pre-installed on workshop machines. Verify it's accessible:

```bash
which freesurfer
echo $FREESURFER_HOME

# If not set, add to ~/.zshrc or ~/.bash_profile:
export FREESURFER_HOME=/Applications/freesurfer
export PATH="$FREESURFER_HOME/bin:$PATH"
source $FREESURFER_HOME/SetUpFreeSurfer.sh
```

### Step 6: Install ANTs (Required for Pipeline)

ANTs command-line tools are needed for co-registration (`register_to_t1w.sh`)
and longitudinal registration (`register_longitudinal.sh`):

```bash
conda activate finse26
conda install -c conda-forge ants
```

Verify with:

```bash
antsRegistrationSyN.sh -h   # should print usage
```

### Step 7: Install FEniCSx (Optional)

FEniCSx has ARM64 builds in conda-forge (needed only for NB07 brain mechanics):

```bash
conda activate finse26
conda install -c conda-forge fenics-dolfinx petsc4py
```

If the above fails, try pip:

```bash
pip install fenics-dolfinx basix ufl
```

### Step 8: Verify Installation

```bash
cd glioma-brain-digital-twin
bash environment/setup_env.sh
python scripts/check_env.py
```

Both should complete without errors.

---

## Linux + CUDA (Ubuntu 24.04, NVIDIA RTX)

This guide assumes **Ubuntu 24.04 LTS** with **NVIDIA RTX A5000** (or similar CUDA-capable GPU).

### Step 1: Install NVIDIA Drivers

Check if drivers are already installed:

```bash
nvidia-smi
```

If command not found, install drivers:

```bash
# Update package manager
sudo apt update

# Install NVIDIA driver (version 535 or later recommended)
sudo apt install nvidia-driver-535
sudo apt install nvidia-utils

# Reboot to load drivers
sudo reboot
```

Verify after reboot:

```bash
nvidia-smi
# Output should show GPU, driver version, CUDA version
```

### Step 2: Install NVIDIA CUDA Toolkit

Download from [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-downloads) or use apt:

```bash
# Option A: Using apt (easier)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install cuda-toolkit-12-4

# Option B: Using the .run installer (if apt fails)
# Download cuda_12.4.1_550.54.15_linux.run from NVIDIA website
# chmod +x cuda_12.4.1_550.54.15_linux.run
# sudo ./cuda_12.4.1_550.54.15_linux.run
```

Add CUDA to PATH (~/.bashrc or ~/.zshrc):

```bash
export PATH="/usr/local/cuda-12.4/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH"
```

Verify:

```bash
nvcc --version
# Output: nvcc: NVIDIA (R) Cuda compiler driver, version 12.4
```

### Step 3: Install Miniforge

Download the **Linux x86_64** installer:

```bash
curl -L https://github.com/conda-forge/miniforge/releases/download/23.3.1-1/Miniforge3-23.3.1-1-Linux-x86_64.sh \
  -o ~/miniforge-installer.sh

bash ~/miniforge-installer.sh -b -p ~/miniforge3
~/miniforge3/bin/conda init bash
```

Restart terminal and verify:

```bash
conda --version
```

### Step 4: Create Environment

```bash
cd glioma-brain-digital-twin
conda env create -f environment/environment.yml
conda activate finse26
```

### Step 5: Install PyTorch with CUDA Support

PyTorch must be compiled for your specific CUDA version (12.1 or 12.4):

```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

**For CUDA 12.4** (if above fails):

```bash
pip install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
```

Verify CUDA availability:

```bash
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
# Expected output: True NVIDIA RTX A5000
```

### Step 6: Install MRtrix3

Option A (conda-forge, recommended):

```bash
conda activate finse26
conda install -c conda-forge mrtrix3
```

Option B (build from source, if conda installation fails):

```bash
cd /tmp
git clone https://github.com/MRtrix3/mrtrix3.git
cd mrtrix3
./configure
./build
# Follow on-screen instructions to add to PATH
```

Verify:

```bash
mrinfo --version
```

### Step 7: Install FSL 6.0

Download from [FSL website](https://fsl.fmrib.ox.ac.uk/fsldownloads_registration/):

```bash
# Download fslinstaller.py
python fslinstaller.py

# Follow interactive installation (default: /usr/local/fsl)

# Add FSL to PATH (~/.bashrc):
export FSLDIR=/usr/local/fsl
export PATH="${FSLDIR}/bin:${PATH}"
source ${FSLDIR}/etc/fslconf/fsl.sh
```

Verify:

```bash
which fslmaths
```

### Step 8: Install ANTs (Required for Pipeline)

```bash
conda activate finse26
conda install -c conda-forge ants
```

### Step 9: Verify Installation

```bash
cd glioma-brain-digital-twin
bash environment/setup_env.sh
python scripts/check_env.py
```

Both should complete without errors.

---

## Google Colab

No local installation needed! Simply open notebooks directly in Colab.

### Step 1: Open Notebook in Colab

Click the Colab badge at the top of any notebook, or:

1. Go to [colab.research.google.com](https://colab.research.google.com)
2. Select "GitHub" tab
3. Enter: `USER/glioma-brain-digital-twin`
4. Select desired notebook (e.g., `NB00_Setup_and_Verification.ipynb`)

### Step 2: Enable GPU (Optional but Recommended)

1. Click `Runtime` → `Change runtime type`
2. Select `T4 GPU` under "Accelerator"
3. Click `Save`

Verify GPU:

```python
import torch
print(torch.cuda.is_available(), torch.cuda.get_device_name(0))
```

### Step 3: Automatic Dependencies

Each notebook's **first code cell** contains auto-installation code:

```python
# Auto-install dependencies (runs once)
!pip install nibabel nilearn pybids dipy networkx \
             fenics-dolfinx basix ufl xarray scipy
```

This cell runs automatically on first notebook open.

### Important Limitations

- **Session timeout**: 90 minutes of inactivity
- **Disk space**: ~15 GB limit (sufficient for workshop)
- **Data**: Download syncs from GitHub LFS automatically
- **GPU**: Limited T4 GPU time (~100 compute units/month free)

For full development, use local installation (Options A or B).

---

## Verify Installation

### Automated Check

Run the verification script:

```bash
cd glioma-brain-digital-twin
bash environment/setup_env.sh
python scripts/check_env.py
```

This checks:
- Python version (3.10+)
- All required packages installed
- CUDA availability (if on Linux+GPU)
- Data files present
- Notebook structure intact

### Manual Verification

Test each major dependency:

```python
python << 'PYEOF'
import sys
import nibabel as nib
import numpy as np
from nilearn import image
import pybids
import networkx as nx
import torch
import dipy
import fenics_dolfinx
import scipy

print("Python version:", sys.version)
print("NumPy:", np.__version__)
print("nibabel:", nib.__version__)
print("nilearn version: OK")
print("pybids version: OK")
print("networkx:", nx.__version__)
print("PyTorch:", torch.__version__, "| CUDA available:", torch.cuda.is_available())
print("DIPY version: OK")
print("FEniCSx version: OK")
print("SciPy version: OK")
print("\nAll core dependencies installed successfully!")
PYEOF
```

---

## Download Data

The repository includes BIDS metadata (JSON sidecars, gradient tables, participants
info) tracked in git, but the large imaging files (~420 MB of NIfTI volumes) must
be obtained separately.

### Option A: Automatic Download (Recommended)

The download script fetches the complete dataset from a GitHub Release:

```bash
cd glioma-brain-digital-twin
python data/download_data.py
```

This downloads ~400 MB and extracts all imaging files into `data/BIDS_preop_postop/`.

### Option B: Manual Download

Download the zip directly from the
[data release](https://github.com/arvidl/glioma-brain-digital-twin-public/releases/tag/glioma-data-v2.0.0) and
extract into `data/`:

```bash
cd glioma-brain-digital-twin
# Download BIDS_preop_postop_v1.0.0.zip from the Releases page, then:
unzip BIDS_preop_postop_v1.0.0.zip -d data/
```

### Option C: Copy from a Local Source

If you already have the BIDS data on your machine (e.g. on a USB drive or shared
folder):

```bash
python data/download_data.py --local /path/to/your/BIDS_preop_postop
```

This copies only the binary imaging files that are missing from `data/BIDS_preop_postop/`.

### Verify Data

After downloading, verify all files are present:

```bash
python data/download_data.py --dry-run
ls data/BIDS_preop_postop/sub-PAT16/ses-preop/anat/
```

You should see `sub-PAT16_ses-preop_T1w.nii.gz` along with the JSON sidecar.

### Full Datasets (Optional, Advanced)

The workshop uses a curated subset of two patients. The full datasets with 25 tumor
patients and 11 controls are available on OpenNeuro:

- **BTC pre-operative**: [OpenNeuro ds001226](https://openneuro.org/datasets/ds001226)
- **BTC post-operative**: [OpenNeuro ds002080](https://openneuro.org/datasets/ds002080)

```bash
# Download additional subjects from OpenNeuro (requires AWS CLI):
python data/download_data.py --method aws --subject PAT01
```

---

## Running Notebooks

### Jupyter Lab (Recommended)

```bash
cd glioma-brain-digital-twin
conda activate finse26
jupyter lab notebooks/
```

Opens at `http://localhost:8888`. Select any notebook to begin.

### Jupyter Notebook

```bash
conda activate finse26
jupyter notebook notebooks/
```

### Visual Studio Code

1. Install extensions: Python, Jupyter
2. Open folder: `glioma-brain-digital-twin`
3. Open any `.ipynb` file
4. Select kernel: `finse26`

### PyCharm Professional

1. Open folder: `glioma-brain-digital-twin`
2. Set interpreter: `~/miniforge3/envs/finse26`
3. Open notebook in cell editor

---

## Troubleshooting

### Issue: "Conda command not found"

**Solution**: Initialize conda and restart terminal:

```bash
~/miniforge3/bin/conda init bash
# or
~/miniforge3/bin/conda init zsh
```

Restart terminal:

```bash
exec $SHELL
conda --version
```

### Issue: "ImportError: No module named 'nibabel'"

**Solution**: Ensure correct environment is activated:

```bash
conda activate finse26
python -c "import nibabel"
```

If still failing:

```bash
pip install --upgrade nibabel
```

### Issue: "CUDA out of memory" (PyTorch on Linux)

**Solution**: Reduce batch size in notebooks, or use CPU:

```python
import torch
device = torch.device('cpu')  # Force CPU
```

### Issue: "ModuleNotFoundError: No module named 'fenics_dolfinx'"

**Solution**: Install FEniCSx explicitly:

```bash
conda activate finse26
conda install -c conda-forge fenics-dolfinx petsc4py
```

If conda fails, try:

```bash
pip install fenics-dolfinx basix ufl gmsh
```

### Issue: "Imaging data missing (NIfTI files not found)"

**Solution**: Download the imaging data:

```bash
cd glioma-brain-digital-twin
python data/download_data.py
```

Or download the zip manually from the
[data release](https://github.com/arvidl/glioma-brain-digital-twin-public/releases/tag/glioma-data-v2.0.0)
and extract into `data/`.

### Issue: "MRtrix3 not found after installation"

**Solution**: Add to PATH:

```bash
# macOS (Homebrew)
brew link mrtrix3

# Linux
export PATH="$HOME/mrtrix3/bin:$PATH"
```

### Issue: "FreeSurfer license error"

**Solution**: Ensure `FREESURFER_HOME` is set:

```bash
export FREESURFER_HOME=/Applications/freesurfer  # macOS
# or
export FREESURFER_HOME=/usr/local/freesurfer     # Linux
```

Add to ~/.zshrc or ~/.bash_profile to persist.

### Issue: "Port 8888 already in use (Jupyter)"

**Solution**: Use different port:

```bash
jupyter lab --port 8889
```

Or kill existing Jupyter process:

```bash
pkill -f jupyter
```

### Need Further Help?

1. Check notebook output for specific error messages
2. Review environment files: `environment/`
3. Run verification: `python scripts/check_env.py`
4. Open an **Issue** on GitHub with:
   - Platform (macOS/Linux/Colab)
   - Output of `python scripts/check_env.py`
   - Full error message

---

**Last Updated**: March 2, 2026  
**For questions**: See README.md or open an Issue on GitHub

