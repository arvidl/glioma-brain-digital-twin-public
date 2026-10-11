"""
plotting.py
───────────
Consistent, publication-ready figure styles for the Finse 2026 workshop.

Usage
-----
>>> from scripts.utils.plotting import set_style, plot_matrix, plot_brain_network
>>> set_style()
>>> fig = plot_matrix(SC, title="Structural Connectivity – sub-PAT16 pre-op")
"""

from __future__ import annotations
from typing import Optional, Sequence

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors


# ─── Style ────────────────────────────────────────────────────────────────────

PALETTE = {
    "preop":   "#2471A3",   # steel blue
    "postop":  "#E74C3C",   # crimson
    "glioma":  "#E67E22",   # orange
    "control": "#27AE60",   # green
    "tumor":   "#C0392B",   # dark red
    "bg":      "#F8F9FA",   # off-white
}


def set_style(font_size: int = 11, dpi: int = 150) -> None:
    """Apply a clean, consistent matplotlib style."""
    plt.rcParams.update({
        "figure.dpi":          dpi,
        "figure.facecolor":    "white",
        "axes.facecolor":      "white",
        "axes.spines.top":     False,
        "axes.spines.right":   False,
        "axes.grid":           False,
        "font.size":           font_size,
        "axes.labelsize":      font_size,
        "axes.titlesize":      font_size + 1,
        "xtick.labelsize":     font_size - 1,
        "ytick.labelsize":     font_size - 1,
        "legend.fontsize":     font_size - 1,
        "lines.linewidth":     1.8,
        "lines.markersize":    5,
        "savefig.bbox":        "tight",
        "savefig.dpi":         dpi,
    })


# ─── Matrix plots ─────────────────────────────────────────────────────────────

def plot_matrix(
    M: np.ndarray,
    title: str = "",
    cmap: str = "viridis",
    vmin: Optional[float] = None,
    vmax: Optional[float] = None,
    roi_labels: Optional[Sequence[str]] = None,
    colorbar_label: str = "",
    figsize: tuple = (7, 6),
) -> plt.Figure:
    """Plot a connectivity matrix as a heatmap."""
    fig, ax = plt.subplots(figsize=figsize)
    im = ax.imshow(M, cmap=cmap, vmin=vmin, vmax=vmax, aspect="auto")
    cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    if colorbar_label:
        cbar.set_label(colorbar_label)
    if roi_labels is not None:
        step = max(1, len(roi_labels) // 10)
        ticks = range(0, len(roi_labels), step)
        ax.set_xticks(list(ticks))
        ax.set_yticks(list(ticks))
        ax.set_xticklabels([roi_labels[i] for i in ticks], rotation=90, fontsize=7)
        ax.set_yticklabels([roi_labels[i] for i in ticks], fontsize=7)
    ax.set_xlabel("ROI")
    ax.set_ylabel("ROI")
    ax.set_title(title, fontweight="bold")
    fig.tight_layout()
    return fig


def plot_matrix_comparison(
    M_pre: np.ndarray,
    M_post: np.ndarray,
    titles: tuple[str, str] = ("Pre-operative", "Post-operative"),
    cmap: str = "viridis",
    shared_scale: bool = True,
    figsize: tuple = (13, 5),
) -> plt.Figure:
    """Plot two matrices and their difference side by side."""
    diff  = M_post - M_pre
    mats  = [M_pre, M_post, diff]
    t     = list(titles) + [f"Difference ({titles[1]} − {titles[0]})"]
    cmaps = [cmap, cmap, "RdBu_r"]

    if shared_scale:
        vmin = min(M_pre.min(), M_post.min())
        vmax = max(M_pre.max(), M_post.max())
        vmins = [vmin, vmin, -np.abs(diff).max()]
        vmaxs = [vmax, vmax,  np.abs(diff).max()]
    else:
        vmins = [None, None, -np.abs(diff).max()]
        vmaxs = [None, None,  np.abs(diff).max()]

    fig, axes = plt.subplots(1, 3, figsize=figsize)
    for ax, M, title, cm, vn, vx in zip(axes, mats, t, cmaps, vmins, vmaxs):
        im = ax.imshow(M, cmap=cm, vmin=vn, vmax=vx, aspect="auto")
        ax.set_title(title, fontsize=10, fontweight="bold")
        ax.axis("off")
        plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    return fig


# ─── Network plots ────────────────────────────────────────────────────────────

def plot_brain_network(
    M: np.ndarray,
    node_colors: Optional[np.ndarray] = None,
    node_sizes: Optional[np.ndarray] = None,
    title: str = "",
    layout: str = "circular",
    edge_threshold: float = 0.1,
    figsize: tuple = (8, 8),
) -> plt.Figure:
    """Draw a brain connectivity network using networkx.

    Parameters
    ----------
    layout : 'circular' | 'spring' | 'spectral'
    """
    try:
        import networkx as nx
    except ImportError:
        raise ImportError("networkx is required")

    M_thr = M.copy()
    M_thr[M_thr < edge_threshold * M_thr.max()] = 0
    np.fill_diagonal(M_thr, 0)

    G = nx.from_numpy_array(M_thr)
    edges, weights = zip(*nx.get_edge_attributes(G, "weight").items()) \
        if G.number_of_edges() > 0 else ([], [])

    if layout == "circular":
        pos = nx.circular_layout(G)
    elif layout == "spring":
        pos = nx.spring_layout(G, weight="weight", seed=42)
    else:
        pos = nx.spectral_layout(G, weight="weight")

    sizes  = 300 * (node_sizes  / node_sizes.max())  if node_sizes  is not None else 200
    colors = node_colors if node_colors is not None else PALETTE["preop"]

    fig, ax = plt.subplots(figsize=figsize)
    if edges:
        nx.draw_networkx_edges(G, pos, edgelist=edges,
                               width=[1 + 3 * w / max(weights) for w in weights],
                               edge_color=weights, edge_cmap=plt.cm.Blues,
                               alpha=0.6, ax=ax)
    nx.draw_networkx_nodes(G, pos, node_color=colors, node_size=sizes, ax=ax)
    ax.set_title(title, fontweight="bold")
    ax.axis("off")
    fig.tight_layout()
    return fig


# ─── Time series ──────────────────────────────────────────────────────────────

def plot_roi_timeseries(
    ts: np.ndarray,
    tr: float = 2.4,
    roi_indices: Optional[Sequence[int]] = None,
    roi_labels: Optional[Sequence[str]] = None,
    title: str = "",
    figsize: tuple = (14, 5),
) -> plt.Figure:
    """Plot BOLD time series for selected ROIs.

    Parameters
    ----------
    ts  : (T, N) array
    tr  : repetition time in seconds
    """
    T, N = ts.shape
    time = np.arange(T) * tr

    if roi_indices is None:
        roi_indices = list(range(min(6, N)))

    fig, ax = plt.subplots(figsize=figsize)
    cmap = plt.cm.tab10
    for i, roi in enumerate(roi_indices):
        label = roi_labels[roi] if roi_labels else f"ROI {roi}"
        y = ts[:, roi]
        y = (y - y.mean()) / (y.std() + 1e-10)  # z-score for display
        ax.plot(time, y + i * 3, color=cmap(i / 10), label=label, linewidth=1.2)

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("BOLD signal (z-scored, offset)")
    ax.set_title(title, fontweight="bold")
    ax.legend(loc="upper right", fontsize=8)
    fig.tight_layout()
    return fig


# ─── Metrics bar / radar ───────────────────────────────────────────────────────

def plot_metrics_comparison(
    metrics_pre: dict,
    metrics_post: dict,
    keys: Optional[Sequence[str]] = None,
    figsize: tuple = (10, 4),
) -> plt.Figure:
    """Bar chart comparing scalar metrics pre vs post."""
    if keys is None:
        keys = [k for k in metrics_pre if isinstance(metrics_pre[k], (int, float))]

    x    = np.arange(len(keys))
    pre  = [metrics_pre.get(k, 0)  for k in keys]
    post = [metrics_post.get(k, 0) for k in keys]

    fig, ax = plt.subplots(figsize=figsize)
    width = 0.35
    ax.bar(x - width/2, pre,  width, label="Pre-op",  color=PALETTE["preop"],  alpha=0.85)
    ax.bar(x + width/2, post, width, label="Post-op", color=PALETTE["postop"], alpha=0.85)
    ax.set_xticks(x)
    ax.set_xticklabels(keys, rotation=20, ha="right")
    ax.legend()
    ax.set_title("Network metric comparison: pre vs post-operative", fontweight="bold")
    fig.tight_layout()
    return fig
