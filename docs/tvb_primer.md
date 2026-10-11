# The Virtual Brain (TVB) Primer

A concise introduction to whole-brain dynamics simulation on empirical connectome data.

## What TVB Does

The Virtual Brain is a neuroinformatics framework for simulating mesoscopic brain dynamics at the region level. It bridges the gap between:

- **Microscale**: single neurons, local circuits (biophysically detailed)
- **Macroscale**: large-scale functional networks, BOLD fMRI, EEG

**Core idea**: Model N brain regions as coupled nonlinear oscillators, where coupling strength is determined by anatomical connectivity (SC matrix) and region-to-region distance. Output a simulated BOLD time series comparable to empirical resting-state fMRI.

## The Mean-Field Model

TVB uses reduced mean-field approximations of local neural populations. The most common choice is the **Hopf bifurcation model** or **Stuart-Landau oscillator**:

### Complex Representation

For each region i:

$$\frac{dz_i}{dt} = (a_i + i\omega_i) z_i - |z_i|^2 z_i + I_i(t)$$

where:
- $z_i = x_i + iy_i$ ∈ ℂ (complex state)
- $a_i$: bifurcation parameter (negative → damping, near zero → oscillatory)
- $\omega_i$: intrinsic frequency (Hz)
- $I_i(t) = g_c \sum_j C_{ij} (x_j - x_i)$: global coupling from connectome
- $C_{ij}$: connectivity matrix (weighted adjacency)
- $g_c$: global coupling strength (free parameter)

**Physical interpretation**: $|z_i|$ ≈ neural firing rate; phase and amplitude modulate along a limit cycle.

### Alternative: Wilson-Cowan Conductance-Based

$$\frac{dE_i}{dt} = \frac{1}{\tau_E} \left( -E_i + S_e(w_{ee} E_i - w_{ei} I_i + I_{ext,E}) \right)$$

$$\frac{dI_i}{dt} = \frac{1}{\tau_I} \left( -I_i + S_i(w_{ie} E_i - w_{ii} I_i + I_{ext,I}) \right)$$

where E_i, I_i are excitatory and inhibitory populations, S is a sigmoid nonlinearity, w are weights.

## The Connectome Input

### Structural Connectivity (SC) Matrix

**Size**: N_regions × N_regions, typically 68–1000 regions (Desikan-Killiany, Power, etc.).

**Values**: connection strength (streamline count, averaged FA, probabilistic weight).

**Requirements**: Symmetric, non-negative, normalized (rows/columns sum to 1 or to global mean).

Derived from DTI + probabilistic tractography or from HCP connectome databases.

### Tract Lengths (Distance Matrix)

**Size**: N_regions × N_regions.

**Values**: mean white-matter distance (mm) between region centroids.

**Purpose**: Conductance delays in coupling term:
$$I_i(t) = g_c \sum_j C_{ij} x_j(t - \Delta t_{ij})$$
where $\Delta t_{ij} = \text{distance}_{ij} / v$ (v ≈ 2–5 m/s).

Delays are critical for phase delays and oscillatory stability.

### Region Centroids

**Purpose**: Anatomical reference for visualization and spatial statistics.

Typically MNI coordinates from template atlas.

## Simulating BOLD

TVB includes the **Balloon-Windkessel hemodynamic model** to convert neural state to BOLD signal.

### State Variables

- $s_i$: synaptic activity (proxy for neural output)
- $f_i$: cerebral blood flow (CBF)
- $v_i$: blood volume
- $q_i$: deoxyhemoglobin (Hb) content

### Differential Equations

$$\frac{ds_i}{dt} = x_i - \frac{s_i}{\tau_s} - (f_i - 1)$$

$$\frac{df_i}{dt} = \frac{s_i}{f_i^\alpha} - \frac{f_i - v_i^{1/\beta}}{\tau_f}$$

$$\frac{dv_i}{dt} = \frac{f_i - v_i^{1/\beta}}{\tau_v}$$

$$\frac{dq_i}{dt} = \frac{f_i(1 - (1-E_0)^{1/f_i}) - q_i v_i^{1/\beta}}{v_i}$$

where:
- $E_0 ≈ 0.4$: resting oxygen extraction
- $\tau_s, \tau_f, \tau_v$: time constants (1–2 s)
- $\alpha ≈ 0.3, \beta ≈ 0.4$: stiffness parameters

**BOLD signal**: $y_i(t) = k_1 (1 - q_i) + k_2 (1 - q_i/v_i) + k_3 (1 - v_i)$

Empirically calibrated to match typical BOLD contrast (~1–5% signal change).

## Fitting to Empirical Functional Connectivity

**Goal**: Adjust TVB parameters (g_c, ω_i, a_i) to match observed resting-state fMRI correlations.

### Functional Connectivity (FC) Matrix

**Empirical FC**: Pearson correlation of BOLD time series (or coherence/partial correlation).

**Simulated FC**: FC computed from TVB BOLD output.

### Optimization Loop

1. Generate long TVB simulation (5–10 min, 2 s TR).
2. Extract synthetic BOLD time series.
3. Compute simulated FC matrix.
4. Compare to empirical FC via mean squared error (MSE) or Kullback-Leibler divergence.
5. Adjust g_c, region-specific parameters via gradient descent or Bayesian optimization.

**Validation metric**: Functional Connectivity Dynamics (FCD) similarity, or dynamical richness (metastability).

## Code Example: TVB-Library Basic Usage

```python
import numpy as np
from tvb.simulator import Simulator
from tvb.models import HopfStochastic
from tvb.connectivity import Connectivity

# Load connectome (68 regions)
conn = Connectivity.from_file('connectivity.nii.gz')  
# or from HCP: conn = Connectivity.from_hcp(subject='100206')

# Set up model
model = HopfStochastic()
model.a = np.ones((68,)) * 0.1  # bifurcation param
model.omega = np.ones((68,)) * 40  # intrinsic frequencies (Hz)
model.c = 2.0  # global coupling (tunable)

# Simulator
sim = Simulator(
    model=model,
    connectivity=conn,
    coupling=None,  # use default global coupling
    monitors=[],  # add BalloonWindkessel here
    integrator='heunDeterministic',
    integrator_kwargs={'dt': 0.1}  # ms
)

# Generate 10 min @ 2 s TR
(time, BOLD) = sim.run(simulation_length=600000.0)  # ms

# Reshape and compute FC
n_rois = 68
n_timepoints = len(time)
bold_ts = BOLD.reshape((n_timepoints, n_rois))
fc_simulated = np.corrcoef(bold_ts.T)  # 68 × 68 correlation matrix
```

## Key Takeaways

- TVB bridges microscale biophysics to macroscale fMRI via reduced mean-field models.
- Connectome (SC) + tract lengths + region positions fully specify the model geometry.
- Balloon-Windkessel converts neural state to realistic BOLD dynamics.
- Parameter fitting (g_c, ω, a) tunes the simulation to match empirical FC.
- Output is a synthetic BOLD time series suitable for statistical analysis.

