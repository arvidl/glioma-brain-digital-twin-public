# Platform-Specific Notes for Finse 2026

Detailed setup, known issues, and optimization tips for macOS (Apple Silicon), Linux+CUDA, and Google Colab.

## Apple Silicon (M1, M2, M3)

### Known Working Versions

As of March 2026:

- **Python**: 3.11+, native ARM64 (not Rosetta x86 translation)
- **nibabel**: 5.2+, conda-forge native
- **nilearn**: 0.10+, conda-forge
- **networkx**: 3.1+, pip (pure Python)
- **numpy**: 1.24+, conda-forge ARM64
- **scipy**: 1.10+, conda-forge ARM64
- **matplotlib**: 3.7+, conda-forge
- **plotly**: 5.17+, pip
- **tqdm**: 4.65+, pip
- **pybids**: 0.16+, pip
- **dipy**: 1.7+, conda-forge
- **FEniCS/FEniCSx**: Build from source or conda-forge (experimental)
  - **dolfinx**: 0.7+, conda-forge with `--build=native`
  - **petsc4py**: 3.19+, conda-forge
  - **basix**: Latest, conda-forge
- **TVB-library**: 2.8+, pip (pure Python for core; optional mpi4py for parallelization)

### Installation Steps (conda-forge preferred)

```bash
# Create environment
conda create -n finse26 python=3.11 -c conda-forge

# Activate
conda activate finse26

# Core neuroimaging
conda install -c conda-forge nibabel nilearn pybids dipy networkx scipy numpy matplotlib plotly tqdm -y

# FEM solver (optional)
conda install -c conda-forge fenics-dolfinx petsc4py -y

# TVB (if modeling whole-brain dynamics)
pip install tvb-library

# Development
conda install -c conda-forge pytest black ruff -y
```

### MPS Tips (Metal Performance Shaders)

Apple Silicon has no native CUDA, but **Metal** (MPS) is available in some libraries:

- **PyTorch**: Has MPS support; not applicable here (no DL models).
- **JAX**: MPS support experimental.
- **NumPy/SciPy**: CPU only, but highly optimized via Accelerate.framework.

**Practical impact**: Matrix operations (linear algebra) on large arrays (e.g., tractography, connectivity matrices) are **already faster than Intel CPUs due to memory bandwidth** (~120 GB/s vs. 50 GB/s). No additional setup needed.

### Memory Bandwidth Advantage

Apple Silicon excels at FEM assembly (data-parallel, memory-bound):

- **Typical speedup**: 2–3× vs. Intel 10-core on mesh assembly for N_dofs ~ 10^6.
- **Peak bandwidth**: 120 GB/s (M3) vs. 50 GB/s (Intel 13th gen).
- **Implication**: FEniCSx simulations on medium meshes (< 1M elements) run well on MacBook Pro.

### Known Issues and Workarounds

| Issue | Cause | Workaround |
|-------|-------|-----------|
| `ImportError: libopenblas.so` | x86 binary loaded | Use only conda-forge, not pip-installed packages |
| Slow MPI startup | Apple's implementation | Use single-core (set `-np 1`) for FEM; parallelism via OpenMP |
| FEniCSx build fails | Missing M-series optimizations | `conda install -c conda-forge fenics-dolfinx::*=*_0` to force fresh build |
| Plotly 3D rendering slow | OpenGL on MPS | Use headless mode, save HTML locally |

## Linux + CUDA

### CUDA/cuDNN Version Matrix (Recommended)

| OS | CUDA | cuDNN | Driver | Notes |
|----|------|-------|--------|-------|
| Ubuntu 22.04 LTS | 12.1+ | 8.9 | 525+ | GH200 compatible |
| Ubuntu 20.04 LTS | 11.8 | 8.6 | 450+ | Older, still supported |
| Rocky 8 | 12.1+ | 8.9 | 525+ | HPC clusters |

### Installation on Linux

```bash
# Check GPU
nvidia-smi

# Install CUDA toolkit (example: CUDA 12.1)
# Download from https://developer.nvidia.com/cuda-downloads
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-repo-ubuntu2204_12.1.0-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2204_12.1.0-1_amd64.deb
sudo apt-get update && sudo apt-get install -y cuda-toolkit-12-1

# Set environment
export PATH=/usr/local/cuda-12.1/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.1/lib64:$LD_LIBRARY_PATH

# Verify
nvcc --version
```

### Conda Environment (Linux+CUDA)

```bash
conda create -n finse26 python=3.11 -c conda-forge

conda install -c conda-forge \
  nibabel nilearn pybids dipy networkx \
  numpy scipy matplotlib plotly tqdm \
  cudatoolkit=12.1 \
  fenics-dolfinx petsc=*=*cu121* \
  pytorch::pytorch pytorch::pytorch-cuda=12.1 -y

pip install tvb-library
```

### Multi-GPU Setup

**Distribute simulations across N GPUs** via MPI:

```bash
# 4 GPUs
mpirun -np 4 python run_simulation.py

# Automatic CUDA device assignment (PETSc)
# Device i gets rank i mod num_gpus
```

**PETSc GPU options**:
```python
opts = PETSc.Options()
opts['mat_type'] = 'aijcusparse'  # GPU matrix
opts['vec_type'] = 'cuda'         # GPU vectors
opts['ksp_type'] = 'gmres'
opts['pc_type'] = 'hypre'         # BoomerAMG on GPU
```

### HPC/SLURM Tips

```bash
#!/bin/bash
#SBATCH --job-name=finse_sim
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --time=12:00:00
#SBATCH --partition=gpu

module load cuda/12.1 openmpi gcc

mpirun -np 8 python /path/to/simulation.py \
  --subjects PAT16 \
  --output /scratch/$SLURM_JOBID
```

### Known Issues

| Issue | Cause | Workaround |
|-------|-------|-----------|
| `CUDA out of memory` on 24 GB GPU | Large mesh assembly | Reduce mesh resolution or use tiling strategy |
| MPI hangs on GPU-to-GPU transfer | NCCL version mismatch | Update NCCL library or disable GPU-aware MPI (`MPICH_GPU_SUPPORT=0`) |
| Poor scaling with >8 GPUs | Communication overhead | Profile with `nvprof`; consider weak scaling study |

## Google Colab

### Storage Strategies

**Problem**: Colab instances reset after 12 h (free) or 30 days (Pro). BIDS data (~ 50 GB) must be fetched on each run.

**Solution 1: Google Drive mounting**
```python
from google.colab import drive
drive.mount('/content/gdrive')
# Load from: /content/gdrive/My Drive/finse_data/
```
- Pro: Persistent across sessions
- Con: Slower I/O (30 MB/s vs. local SSD 500+ MB/s)

**Solution 2: Fast.ai data download**
```python
from fastai.data.external import download_url
download_url('https://openneuro.org/ds:ds001226', '/tmp/bids')
```
- Pro: Fast (on-instance storage)
- Con: Ephemeral (lost after disconnect)

**Solution 3: Hybrid (recommended)**
```python
import os
local_path = '/tmp/finse_data'
drive_path = '/content/gdrive/My Drive/finse_data'

if not os.path.exists(local_path):
    import shutil
    shutil.copytree(drive_path, local_path)  # one-time copy
# Use local_path for all I/O
```

### Resuming Sessions

**Checkpoint intermediate results**:
```python
import pickle
import json

# Save connectome, parcellation
connectivity_checkpoint = {
    'sc_matrix': sc.numpy(),
    'roi_names': roi_names,
    'mni_coords': mni_coords
}

with open('/content/gdrive/My Drive/finse_data/checkpoints/connectivity.pkl', 'wb') as f:
    pickle.dump(connectivity_checkpoint, f)

# Next session
with open('/content/gdrive/My Drive/finse_data/checkpoints/connectivity.pkl', 'rb') as f:
    connectivity_checkpoint = pickle.load(f)
```

### Pro vs. Free GPU

| Aspect | Free | Pro (USD 10/mo) |
|--------|------|---|
| GPU | T4 (16 GB) or K80 (12 GB) | V100 (32 GB) or H100 (80 GB) |
| Runtime | 12 h max | 30 days + background execution |
| RAM | 12 GB | 52 GB |
| Disk | 100 GB | 166 GB |
| Speed | 5–10× slower than workstation | 50–100× faster than CPU |

**Recommendation for Finse**: Use **Pro** for FEniCS simulations (H100 access); free tier for data exploration.

### Colab Notebook Template

```python
# Install dependencies
!pip install -q nibabel nilearn pybids networkx -q

# Mount Drive
from google.colab import drive, files
drive.mount('/content/gdrive')

# Import
import numpy as np
import nibabel as nib
from pathlib import Path

# Load data from checkpointed location
bids_root = Path('/content/gdrive/My Drive/finse_data/BIDS_preop_postop')
subj_data = nib.load(bids_root / 'sub-PAT16' / 'ses-preop' / 'anat' / 'sub-PAT16_ses-preop_T1w.nii.gz')

# Run analysis
print(f"T1w shape: {subj_data.shape}")

# Save results
output_dir = Path('/content/gdrive/My Drive/finse_results')
output_dir.mkdir(exist_ok=True)
# ... save computations

# Download to local if needed
files.download('/content/gdrive/My Drive/finse_results/summary.csv')
```

