"""
Test BIDS dataset structure and data availability.
"""

import json
import os
from pathlib import Path

import pytest


def _default_bids_root() -> Path:
    p = Path(__file__).resolve().parent
    for _ in range(10):
        if (p / "pyproject.toml").exists():
            return p / "data" / "BIDS_preop_postop"
        p = p.parent
    return Path(__file__).resolve().parent.parent / "data" / "BIDS_preop_postop"


_BIDS_ROOT = Path(os.environ.get("FINSE_BIDS_ROOT", str(_default_bids_root())))

# Metadata is tracked in git; imaging comes from `python data/download_data.py`.
requires_imaging = pytest.mark.skipif(
    not (
        _BIDS_ROOT / "sub-PAT16" / "ses-preop" / "anat" / "sub-PAT16_ses-preop_T1w.nii.gz"
    ).exists(),
    reason="BIDS imaging not downloaded (run: python data/download_data.py)",
)


@pytest.mark.skipif(not _BIDS_ROOT.exists(), reason=f"BIDS dataset not found at {_BIDS_ROOT}")
class TestBIDSDataset:
    """Tests for BIDS dataset integrity."""

    def test_bids_root_exists(self, bids_root):
        """Test BIDS root directory exists."""
        assert bids_root.exists()
        assert bids_root.is_dir()

    def test_dataset_description_exists(self, bids_root):
        """Test dataset_description.json exists."""
        desc_file = bids_root / "dataset_description.json"
        assert desc_file.exists()

    def test_dataset_description_valid_json(self, bids_root):
        """Test dataset_description.json is valid JSON."""
        desc_file = bids_root / "dataset_description.json"
        with open(desc_file, "r") as f:
            data = json.load(f)

        # Check required fields
        assert "Name" in data
        assert "BIDSVersion" in data

    def test_participants_tsv_exists(self, bids_root):
        """Test participants.tsv exists."""
        part_file = bids_root / "participants.tsv"
        assert part_file.exists()

    def test_participants_contains_subjects(self, bids_root, subject_ids):
        """Test participants.tsv contains expected subjects."""
        part_file = bids_root / "participants.tsv"
        with open(part_file, "r") as f:
            content = f.read()

        for subj_id in subject_ids:
            assert f"sub-{subj_id}" in content

    @requires_imaging
    def test_t1w_preop_exists(self, bids_root, subject_ids):
        """Test T1w files exist for preop session."""
        for subj_id in subject_ids:
            t1w_file = (
                bids_root
                / f"sub-{subj_id}"
                / "ses-preop"
                / "anat"
                / f"sub-{subj_id}_ses-preop_T1w.nii.gz"
            )
            assert t1w_file.exists(), f"Missing: {t1w_file}"

    @requires_imaging
    def test_t1w_postop_exists(self, bids_root, subject_ids):
        """Test T1w files exist for postop session."""
        for subj_id in subject_ids:
            t1w_file = (
                bids_root
                / f"sub-{subj_id}"
                / "ses-postop"
                / "anat"
                / f"sub-{subj_id}_ses-postop_T1w.nii.gz"
            )
            assert t1w_file.exists(), f"Missing: {t1w_file}"

    @requires_imaging
    def test_tumor_masks_exist(self, bids_root, subject_ids):
        """Test tumor mask files exist in derivatives."""
        for subj_id in subject_ids:
            for space in ["T1", "MNI"]:
                mask_file = (
                    bids_root
                    / "derivatives"
                    / "tumor_masks"
                    / f"sub-{subj_id}"
                    / "anat"
                    / f"sub-{subj_id}_space_{space}_label-tumor.nii.gz"
                )
                assert mask_file.exists(), f"Missing: {mask_file}"

    @requires_imaging
    def test_bids_layout_loads(self, bids_layout, subject_ids):
        """Test BIDSLayout can load the dataset."""
        if bids_layout is None:
            pytest.skip("BIDSLayout not available")

        subjects = bids_layout.get_subjects()
        assert set(subject_ids) <= set(subjects)

    @requires_imaging
    def test_nifti_files_readable(self, bids_root, subject_ids):
        """Test that T1w NIfTI files are readable with nibabel."""
        import nibabel as nib

        for subj_id in subject_ids:
            t1w_file = (
                bids_root
                / f"sub-{subj_id}"
                / "ses-preop"
                / "anat"
                / f"sub-{subj_id}_ses-preop_T1w.nii.gz"
            )

            img = nib.load(t1w_file)
            data = img.get_fdata()

            assert data.shape[0] > 0  # non-empty
            assert img.affine.shape == (4, 4)
