"""
Unit tests for scripts/utils/ modules.

These tests use synthetic data and do not require the BIDS dataset to be present.
"""
import pytest
import numpy as np
from pathlib import Path


# ---------------------------------------------------------------------------
# mri_utils
# ---------------------------------------------------------------------------

class TestMriUtils:
    """Tests for scripts.utils.mri_utils (NIfTI I/O and DTI helpers)."""

    def test_load_nifti(self, synthetic_nifti_path):
        from scripts.utils.mri_utils import load_nifti

        img, data, affine = load_nifti(synthetic_nifti_path)
        assert data.shape == (10, 10, 10)
        assert affine.shape == (4, 4)

    def test_save_and_reload(self, tmp_path):
        from scripts.utils.mri_utils import save_nifti, load_nifti

        data = np.random.randn(5, 5, 5).astype(np.float32)
        affine = np.eye(4)
        out = tmp_path / "test_save.nii.gz"

        save_nifti(data, affine, out)
        _, loaded, aff = load_nifti(out)

        np.testing.assert_allclose(loaded, data, atol=1e-6)
        np.testing.assert_array_equal(aff, affine)

    def test_get_affine(self, synthetic_nifti_path):
        from scripts.utils.mri_utils import get_affine

        aff = get_affine(synthetic_nifti_path)
        assert aff.shape == (4, 4)

    def test_get_voxel_size(self, synthetic_nifti_path):
        from scripts.utils.mri_utils import get_voxel_size

        vs = get_voxel_size(synthetic_nifti_path)
        assert len(vs) == 3
        assert all(v > 0 for v in vs)


# ---------------------------------------------------------------------------
# connectivity_utils
# ---------------------------------------------------------------------------

class TestConnectivityUtils:
    """Tests for matrix operations in connectivity_utils."""

    def test_threshold_matrix_absolute(self):
        from scripts.utils.connectivity_utils import threshold_matrix

        M = np.array([[0.0, 0.5, 0.1], [0.5, 0.0, 0.9], [0.1, 0.9, 0.0]])
        M_thr = threshold_matrix(M, absolute=0.3)

        assert M_thr[0, 2] == 0.0
        assert M_thr[2, 0] == 0.0
        assert M_thr[0, 1] == 0.5
        np.fill_diagonal(M_thr, 0)
        assert np.all(M_thr[M_thr > 0] >= 0.3)

    def test_threshold_matrix_proportional(self):
        from scripts.utils.connectivity_utils import threshold_matrix

        M = np.random.rand(10, 10)
        M = (M + M.T) / 2
        np.fill_diagonal(M, 0)

        M_thr = threshold_matrix(M, proportional=0.3)
        nonzero_before = np.sum(M > 0)
        nonzero_after = np.sum(M_thr > 0)
        assert nonzero_after <= nonzero_before

    def test_symmetrise(self):
        from scripts.utils.connectivity_utils import symmetrise

        M = np.array([[1.0, 2.0], [4.0, 3.0]])
        S = symmetrise(M)
        np.testing.assert_array_equal(S, S.T)
        assert S[0, 1] == 3.0

    def test_normalise_sc(self):
        from scripts.utils.connectivity_utils import normalise_sc

        SC = np.random.rand(10, 10) * 100
        SC = (SC + SC.T) / 2
        np.fill_diagonal(SC, 0)

        normed = normalise_sc(SC)
        assert normed.max() <= 1.0
        assert normed.min() >= 0.0

    def test_compute_graph_metrics(self):
        from scripts.utils.connectivity_utils import compute_graph_metrics

        np.random.seed(42)
        M = np.random.rand(20, 20)
        M = (M + M.T) / 2
        np.fill_diagonal(M, 0)
        M[M < 0.5] = 0

        metrics = compute_graph_metrics(M)

        assert "degree_strength" in metrics
        assert "clustering" in metrics
        assert "betweenness" in metrics
        assert "global_efficiency" in metrics
        assert "modularity" in metrics
        assert len(metrics["degree_strength"]) == 20


# ---------------------------------------------------------------------------
# plotting
# ---------------------------------------------------------------------------

class TestPlotting:
    """Tests for plotting utilities (figures are created but not displayed)."""

    def test_set_style(self):
        from scripts.utils.plotting import set_style
        import matplotlib.pyplot as plt

        set_style(font_size=12, dpi=100)
        assert plt.rcParams["font.size"] == 12

    def test_plot_matrix(self):
        from scripts.utils.plotting import plot_matrix
        import matplotlib.pyplot as plt

        M = np.random.rand(10, 10)
        fig = plot_matrix(M, title="Test Matrix")
        assert fig is not None
        plt.close(fig)

    def test_plot_matrix_comparison(self):
        from scripts.utils.plotting import plot_matrix_comparison
        import matplotlib.pyplot as plt

        M1 = np.random.rand(10, 10)
        M2 = np.random.rand(10, 10)
        fig = plot_matrix_comparison(M1, M2)
        assert fig is not None
        plt.close(fig)

    def test_plot_roi_timeseries(self):
        from scripts.utils.plotting import plot_roi_timeseries
        import matplotlib.pyplot as plt

        ts = np.random.randn(100, 10)
        fig = plot_roi_timeseries(ts, tr=2.0, roi_indices=[0, 1, 2])
        assert fig is not None
        plt.close(fig)

    def test_plot_metrics_comparison(self):
        from scripts.utils.plotting import plot_metrics_comparison
        import matplotlib.pyplot as plt

        pre = {"global_efficiency": 0.5, "modularity": 0.4, "clustering": 0.3}
        post = {"global_efficiency": 0.45, "modularity": 0.38, "clustering": 0.28}
        fig = plot_metrics_comparison(pre, post)
        assert fig is not None
        plt.close(fig)


# ---------------------------------------------------------------------------
# mechanics_utils (material parameters only; FEniCSx tests skipped if absent)
# ---------------------------------------------------------------------------

class TestMechanicsUtils:
    """Tests for mechanics helper functions."""

    def test_lame_parameters(self):
        from scripts.utils.mechanics_utils import lame_parameters

        lam, mu = lame_parameters(E=2500.0, nu=0.45)
        assert lam > 0
        assert mu > 0
        assert mu == pytest.approx(2500.0 / (2 * 1.45), rel=1e-6)

    def test_tissue_properties_keys(self):
        from scripts.utils.mechanics_utils import TISSUE_PROPERTIES

        expected = {"white_matter", "gray_matter", "glioma_II", "glioma_III", "edema", "csf"}
        assert expected.issubset(set(TISSUE_PROPERTIES.keys()))

        for tissue, props in TISSUE_PROPERTIES.items():
            assert "E" in props
            assert "nu" in props
            assert "rho" in props


# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------

class TestConfig:
    """Tests for centralized configuration."""

    def test_repo_root_exists(self):
        from scripts.config import REPO_ROOT

        assert REPO_ROOT.exists()
        assert (REPO_ROOT / "pyproject.toml").exists()

    def test_bids_root_path(self):
        from scripts.config import BIDS_ROOT

        assert str(BIDS_ROOT).endswith("BIDS_preop_postop")

    def test_subjects_and_sessions(self):
        from scripts.config import SUBJECTS, SESSIONS

        assert "PAT16" in SUBJECTS
        assert len(SUBJECTS) == 1
        assert "preop" in SESSIONS
        assert "postop" in SESSIONS
