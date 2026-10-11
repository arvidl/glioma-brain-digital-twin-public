"""
Test environment setup and package imports.
"""


def test_import_nibabel():
    """Test nibabel can be imported."""
    import nibabel as nib

    assert hasattr(nib, "load")


def test_import_nilearn():
    """Test nilearn can be imported."""
    import nilearn

    assert hasattr(nilearn, "datasets")


def test_import_networkx():
    """Test networkx can be imported."""
    import networkx as nx

    G = nx.Graph()
    assert len(G) == 0


def test_import_scipy():
    """Test scipy can be imported."""
    from scipy import io

    assert hasattr(io, "loadmat")


def test_import_numpy():
    """Test numpy can be imported."""
    import numpy as np

    arr = np.array([1, 2, 3])
    assert len(arr) == 3


def test_import_pybids():
    """Test pybids can be imported."""
    from bids import BIDSLayout

    assert callable(BIDSLayout)


def test_import_matplotlib():
    """Test matplotlib can be imported."""
    import matplotlib.pyplot as plt

    assert hasattr(plt, "figure")


def test_import_plotly():
    """Test plotly can be imported."""
    import plotly.graph_objects as go

    assert hasattr(go, "Figure")


def test_import_tqdm():
    """Test tqdm can be imported."""
    from tqdm import tqdm

    assert callable(tqdm)


def test_nifti_load_save(synthetic_nifti_path):
    """Test nibabel can load and save NIfTI files."""
    import nibabel as nib

    # Load
    img = nib.load(synthetic_nifti_path)
    data = img.get_fdata()

    assert data.shape == (10, 10, 10)
    assert img.affine.shape == (4, 4)


def test_scipy_loadmat(tmp_path):
    """Test scipy.io.loadmat works."""
    import numpy as np
    from scipy.io import loadmat, savemat

    test_data = {"array": np.array([[1, 2], [3, 4]])}
    fpath = tmp_path / "test.mat"

    savemat(str(fpath), test_data)
    loaded = loadmat(str(fpath))

    assert "array" in loaded
    assert loaded["array"].shape == (2, 2)


def test_networkx_operations():
    """Test networkx graph operations."""
    import networkx as nx

    G = nx.Graph()
    G.add_edges_from([(1, 2), (2, 3), (3, 1)])

    assert len(G) == 3
    assert len(G.edges()) == 3
    assert nx.is_connected(G)
