"""
connectivity_utils.py
─────────────────────
Load TVB connectivity matrices, compute graph metrics, and visualise networks.

The BTC datasets ship precomputed TVB files:
  SC.zip / SCthrAn.mat  – structural connectivity (fibre density)
  FC.mat                – functional connectivity (Pearson correlation of BOLD)
  ROIts.dat             – BOLD time series per ROI (Desikan-Killiany, 90 ROIs)
  HRF.csv               – resting-state HRF parameters per ROI

Usage
-----
>>> from scripts.utils.connectivity_utils import load_sc, load_fc, compute_graph_metrics
>>> SC = load_sc("data/BIDS_preop_postop", subject="PAT16", session="preop")
>>> FC = load_fc("data/BIDS_preop_postop", subject="PAT16", session="preop")
>>> metrics = compute_graph_metrics(SC)
"""

from __future__ import annotations
from pathlib import Path
from typing import Optional
import zipfile

import numpy as np

try:
    import scipy.io as sio
except ImportError:
    raise ImportError("scipy is required")


# ─── Loaders ─────────────────────────────────────────────────────────────────

def load_sc(
    bids_root: str | Path,
    subject: str,
    session: str,
    threshold: bool = True,
) -> np.ndarray:
    """Load structural connectivity matrix.

    Parameters
    ----------
    threshold : bool
        If True use SCthrAn.mat (thresholded & normalised); else unzip SC.zip.

    Returns
    -------
    SC : (N, N) float array  (N = number of ROIs, typically 90)
    """
    base = Path(bids_root) / "derivatives" / "TVB" / f"sub-{subject}" / f"ses-{session}"
    if threshold:
        mat = sio.loadmat(str(base / "SCthrAn.mat"))
        # Key varies; try common names
        for key in ("SC_thr", "SCthrAn", "SC", "weights"):
            if key in mat:
                return mat[key].astype(float)
        # fallback: return first large matrix
        for k, v in mat.items():
            if isinstance(v, np.ndarray) and v.ndim == 2 and v.shape[0] == v.shape[1]:
                return v.astype(float)
        raise KeyError("Cannot locate SC matrix in SCthrAn.mat")
    else:
        sc_zip = base / "SC.zip"
        with zipfile.ZipFile(str(sc_zip)) as zf:
            names = zf.namelist()
            # Look for a .mat or .txt/csv with the SC
            mat_files = [n for n in names if n.endswith(".mat")]
            if mat_files:
                with zf.open(mat_files[0]) as f:
                    import io
                    mat = sio.loadmat(io.BytesIO(f.read()))
                    for key in ("SC", "weights", "tract_lengths"):
                        if key in mat:
                            return mat[key].astype(float)
    raise FileNotFoundError(f"SC not found in {base}")


def load_fc(
    bids_root: str | Path, subject: str, session: str
) -> np.ndarray:
    """Load functional connectivity matrix.

    Returns
    -------
    FC : (N, N) float array
    """
    base = Path(bids_root) / "derivatives" / "TVB" / f"sub-{subject}" / f"ses-{session}"
    mat  = sio.loadmat(str(base / "FC.mat"))
    for key in ("FC", "fc", "R", "corr"):
        if key in mat:
            return mat[key].astype(float)
    for k, v in mat.items():
        if isinstance(v, np.ndarray) and v.ndim == 2 and v.shape[0] == v.shape[1]:
            return v.astype(float)
    raise KeyError("Cannot locate FC matrix in FC.mat")


def load_roi_timeseries(
    bids_root: str | Path, subject: str, session: str
) -> np.ndarray:
    """Load ROI BOLD time series from ROIts.dat.

    Returns
    -------
    ts : (T, N) float array  (T = time points, N = ROIs)
    """
    p = (Path(bids_root) / "derivatives" / "TVB"
         / f"sub-{subject}" / f"ses-{session}" / "ROIts.dat")
    return np.loadtxt(str(p))


def load_hrf_params(
    bids_root: str | Path, subject: str, session: str
) -> np.ndarray:
    """Load rsHRF parameters per ROI from HRF.csv.

    Returns
    -------
    hrf : (N, P) array – N ROIs × P HRF parameters
    """
    import pandas as pd
    p = (Path(bids_root) / "derivatives" / "TVB"
         / f"sub-{subject}" / f"ses-{session}" / "HRF.csv")
    return pd.read_csv(str(p), header=None).values


# ─── Matrix utilities ─────────────────────────────────────────────────────────

def threshold_matrix(
    M: np.ndarray,
    proportional: Optional[float] = None,
    absolute: Optional[float] = None,
) -> np.ndarray:
    """Threshold a connectivity matrix.

    Parameters
    ----------
    proportional : float [0,1]
        Keep top `proportional` fraction of edges.
    absolute : float
        Zero out entries below this value.
    """
    M = M.copy()
    np.fill_diagonal(M, 0)
    if proportional is not None:
        cutoff = np.percentile(M[M > 0], 100 * (1 - proportional))
        M[M < cutoff] = 0
    elif absolute is not None:
        M[M < absolute] = 0
    return M


def symmetrise(M: np.ndarray) -> np.ndarray:
    """Return (M + M.T) / 2."""
    return (M + M.T) / 2


def normalise_sc(SC: np.ndarray) -> np.ndarray:
    """Log-transform + [0,1] normalise SC for TVB input."""
    SC = SC.copy()
    SC[SC > 0] = np.log(SC[SC > 0] + 1)
    _max = SC.max()
    if _max > 0:
        SC /= _max
    return SC


# ─── Graph metrics ─────────────────────────────────────────────────────────────

def compute_graph_metrics(M: np.ndarray, weighted: bool = True) -> dict:
    """Compute common graph-theoretic metrics using networkx.

    Parameters
    ----------
    M : square connectivity matrix (non-negative)
    weighted : bool

    Returns
    -------
    dict with keys:
        degree_strength  – sum of edge weights per node
        clustering       – clustering coefficient per node
        betweenness      – betweenness centrality per node
        global_efficiency
        local_efficiency
        modularity       – Q from greedy community detection
    """
    try:
        import networkx as nx
    except ImportError:
        raise ImportError("networkx is required")

    M = M.copy()
    np.fill_diagonal(M, 0)
    N = M.shape[0]

    if weighted:
        G = nx.from_numpy_array(M)
    else:
        G = nx.from_numpy_array((M > 0).astype(float))

    strength = np.array([G.degree(n, weight="weight") for n in range(N)])
    clustering = np.array(list(nx.clustering(G, weight="weight").values()))
    betweenness = np.array(list(nx.betweenness_centrality(G, weight="weight").values()))

    # Global efficiency
    if weighted:
        ge = nx.global_efficiency(G)
    else:
        ge = nx.global_efficiency(G)

    # Local efficiency (average of local efficiencies)
    le = np.mean(list(nx.local_efficiency(G).values())) if hasattr(nx, 'local_efficiency') else np.nan

    # Modularity via greedy community detection
    from networkx.algorithms.community import greedy_modularity_communities
    communities = list(greedy_modularity_communities(G, weight="weight"))
    modularity  = nx.community.quality.modularity(G, communities, weight="weight")

    return {
        "degree_strength":   strength,
        "clustering":        clustering,
        "betweenness":       betweenness,
        "global_efficiency": ge,
        "local_efficiency":  le,
        "modularity":        modularity,
        "communities":       communities,
        "n_communities":     len(communities),
    }


# ─── Visualisation ─────────────────────────────────────────────────────────────

def compare_matrices(
    M1: np.ndarray,
    M2: np.ndarray,
    labels: tuple[str, str] = ("Pre-op", "Post-op"),
    title: str = "",
    cmap: str = "viridis",
    figsize: tuple[int, int] = (12, 5),
) -> "plt.Figure":
    """Plot two matrices side by side with a shared colour scale."""
    import matplotlib.pyplot as plt
    vmin = min(M1.min(), M2.min())
    vmax = max(M1.max(), M2.max())

    fig, axes = plt.subplots(1, 3, figsize=figsize,
                             gridspec_kw={"width_ratios": [1, 1, 0.05]})
    for ax, M, label in zip(axes[:2], (M1, M2), labels):
        im = ax.imshow(M, cmap=cmap, vmin=vmin, vmax=vmax, aspect="auto")
        ax.set_title(label, fontsize=12, fontweight="bold")
        ax.set_xlabel("ROI index")
        ax.set_ylabel("ROI index")
    plt.colorbar(im, cax=axes[2])
    if title:
        fig.suptitle(title, fontsize=14)
    fig.tight_layout()
    return fig
