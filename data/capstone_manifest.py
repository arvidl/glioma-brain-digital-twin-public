"""
Manifest of data files required by the Capstone Notebook Series (NB_C01–C09).

Two categories:
  BIDS_FILES  – paths relative to data/BIDS_preop_postop/
                These are already shipped in the existing GitHub Release
                (glioma-data-v2.0.0).

  DERIV_FILES – paths relative to derivatives/  (project-level)
                These must be packaged into a *new* GitHub Release
                (capstone-derivatives-v1.0.0).

Usage:
    from data.capstone_manifest import BIDS_FILES, DERIV_FILES
"""

from __future__ import annotations

# ── Files inside data/BIDS_preop_postop/ ─────────────────────────────────────
# Already covered by the existing release zip.

BIDS_FILES: list[str] = [
    # NB_C01 – BIDS metadata
    "dataset_description.json",
    "participants.tsv",
    "sub-PAT16/sub-PAT16_sessions.tsv",
    "sub-PAT16/sub-PAT16_sessions.json",
    # NB_C03 – raw T1w images
    "sub-PAT16/ses-preop/anat/sub-PAT16_ses-preop_T1w.nii.gz",
    "sub-PAT16/ses-postop/anat/sub-PAT16_ses-postop_T1w.nii.gz",
    # NB_C03 – tumour masks
    "derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_T1_label-tumor_binary.nii.gz",
    "derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_T1_label-tumor.nii.gz",
    "derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_MNI_label-tumor_binary.nii.gz",
    "derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_MNI_label-tumor.nii.gz",
    # NB_C04/C07/C08 – TVB structural connectivity
    "derivatives/TVB/sub-PAT16/ses-preop/SCthrAn.mat",
    # NB_C05/C07 – TVB functional connectivity
    "derivatives/TVB/sub-PAT16/ses-preop/FC.mat",
    # NB_C05 – rsHRF maps (BIDS-level copy)
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_FWHM.nii.gz",
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Height.nii.gz",
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Time2peak.nii.gz",
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_FWHM.nii.gz",
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Height.nii.gz",
    "derivatives/rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Time2peak.nii.gz",
]

# ── Files inside derivatives/ (project-level) ───────────────────────────────
# Must be packaged into a new capstone derivatives release.

DERIV_FILES: list[str] = [
    # NB_C03 – fmriprep preprocessed T1w
    "fmriprep/sub-PAT16/ses-preop/anat/sub-PAT16_ses-preop_desc-preproc_T1w.nii.gz",
    "fmriprep/sub-PAT16/ses-postop/anat/sub-PAT16_ses-postop_desc-preproc_T1w.nii.gz",
    # NB_C03/C07/C08 – FreeSurfer parcellations registered to T1w
    "registered_t1w/sub-PAT16/ses-preop/aparc+aseg_space-T1w.nii.gz",
    "registered_t1w/sub-PAT16/ses-postop/aparc+aseg_space-T1w.nii.gz",
    # NB_C04 – DTI scalar maps in native T1w space (pre-op)
    "registered_t1w/sub-PAT16/ses-preop/fa_space-T1w.nii.gz",
    "registered_t1w/sub-PAT16/ses-preop/md_space-T1w.nii.gz",
    "registered_t1w/sub-PAT16/ses-preop/ad_space-T1w.nii.gz",
    "registered_t1w/sub-PAT16/ses-preop/rd_space-T1w.nii.gz",
    # NB_C04 – DTI scalar maps warped to post-op space (longitudinal)
    "registered_t1w/sub-PAT16/longitudinal/fa_preop_in_postop.nii.gz",
    "registered_t1w/sub-PAT16/longitudinal/md_preop_in_postop.nii.gz",
    "registered_t1w/sub-PAT16/longitudinal/ad_preop_in_postop.nii.gz",
    "registered_t1w/sub-PAT16/longitudinal/rd_preop_in_postop.nii.gz",
    # NB_C06/C07/C08 – displacement and FEM fields
    "registered_t1w/sub-PAT16/longitudinal/displacement_magnitude.nii.gz",
    "registered_t1w/sub-PAT16/longitudinal/fem_displacement_magnitude.nii.gz",
    "registered_t1w/sub-PAT16/longitudinal/fem_displacement_improved.nii.gz",
    # NB_C04/C05/C07/C08 – de novo structural connectivity
    "connectivity/sub-PAT16/ses-preop/sc_sift2.npy",
    "connectivity/sub-PAT16/ses-postop/sc_sift2.npy",
    # NB_C05/C07 – de novo functional connectivity
    "connectivity/sub-PAT16/ses-preop/fc_pearson.npy",
    "connectivity/sub-PAT16/ses-postop/fc_pearson.npy",
    # NB_C05 – rsHRF maps (project-level copy, mirrors BIDS derivatives)
    "rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_FWHM.nii.gz",
    "rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Height.nii.gz",
    "rsHRF/sub-PAT16/sub-PAT16_ses-preop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Time2peak.nii.gz",
    "rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_FWHM.nii.gz",
    "rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Height.nii.gz",
    "rsHRF/sub-PAT16/sub-PAT16_ses-postop_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold_Time2peak.nii.gz",
]
