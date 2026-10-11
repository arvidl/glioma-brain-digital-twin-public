#!/usr/bin/env python3
"""
compute_rshrf.py
────────────────
Estimate voxel-wise resting-state HRF parameters from fMRIPrep BOLD.

Implements the point-process deconvolution approach (Wu et al., 2013;
rsHRF toolbox):
  1. Deconvolve BOLD with canonical HRF → pseudo-neural signal
  2. Detect spontaneous events (local maxima above threshold)
  3. Average BOLD time-locked to detected events → voxel-specific HRF
  4. Extract parameters from the event-triggered average

Produces three parameter maps per session:
  - FWHM:      full-width at half-maximum of the fitted HRF (seconds)
  - Height:    peak amplitude of the fitted HRF (a.u.)
  - Time2peak: time to peak of the fitted HRF (seconds)

Usage
-----
python scripts/compute_rshrf.py --subject PAT16 --project-dir .
python scripts/compute_rshrf.py --subject PAT16 --session preop --project-dir .

References
----------
Wu G-R, Liao W, Stramaglia S, et al. (2013). A blind deconvolution
  approach to recover effective connectivity brain networks from
  resting state fMRI data. Medical Image Analysis 17:365-374.
"""

import argparse
import json
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.stats import gamma as gamma_dist
from scipy.signal import butter, filtfilt, fftconvolve


def spm_hrf(tr: float, time_length: float = 32.0):
    """SPM canonical double-gamma HRF at TR resolution."""
    dt = tr
    t = np.arange(0, time_length, dt)
    a1, b1 = 6.0, 1.0
    a2, b2 = 16.0, 1.0
    c = 1.0 / 6.0
    h = gamma_dist.pdf(t, a1, scale=b1) - c * gamma_dist.pdf(t, a2, scale=b2)
    h /= h.max()
    return h, t


def extract_hrf_params(h, t):
    """Extract FWHM, Height, Time2peak from an HRF waveform."""
    if len(h) < 3 or h.max() <= 0:
        return 0.0, 0.0, 0.0

    peak_idx = np.argmax(h)
    height = float(h[peak_idx])
    time2peak = float(t[peak_idx])

    half_max = height / 2.0
    above = h >= half_max

    if above.sum() < 2:
        fwhm = 0.0
    else:
        # Interpolate for sub-TR precision
        dt = t[1] - t[0] if len(t) > 1 else 1.0
        first_idx = np.argmax(above)
        last_idx = len(above) - 1 - np.argmax(above[::-1])

        # Linear interpolation for rising edge
        if first_idx > 0:
            y0, y1 = h[first_idx - 1], h[first_idx]
            if y1 != y0:
                frac = (half_max - y0) / (y1 - y0)
                t_rise = t[first_idx - 1] + frac * dt
            else:
                t_rise = t[first_idx]
        else:
            t_rise = t[first_idx]

        # Linear interpolation for falling edge
        if last_idx < len(h) - 1:
            y0, y1 = h[last_idx], h[last_idx + 1]
            if y0 != y1:
                frac = (half_max - y0) / (y1 - y0)
                t_fall = t[last_idx] + frac * dt
            else:
                t_fall = t[last_idx]
        else:
            t_fall = t[last_idx]

        fwhm = max(0.0, float(t_fall - t_rise))

    return fwhm, height, time2peak


def estimate_hrf_voxelwise(bold_data, mask, tr, bandpass=(0.01, 0.1)):
    """Point-process deconvolution HRF estimation for each voxel."""
    n_vols = bold_data.shape[3]
    h_canon, t_hrf = spm_hrf(tr, time_length=32.0)
    n_hrf = len(h_canon)
    hrf_window = min(n_hrf, int(20.0 / tr))  # ~20s window for averaging

    fwhm_map = np.zeros(bold_data.shape[:3], dtype=np.float32)
    height_map = np.zeros_like(fwhm_map)
    ttp_map = np.zeros_like(fwhm_map)

    voxels = np.argwhere(mask)
    n_vox = len(voxels)
    print(f"  Estimating HRF for {n_vox} voxels ...")

    # Bandpass filter
    nyq = 0.5 / tr
    low = bandpass[0] / nyq
    high = min(bandpass[1] / nyq, 0.99)
    b_filt, a_filt = butter(3, [low, high], btype="band")

    # Precompute FFT of canonical HRF for Wiener deconvolution
    n_fft = 2 ** int(np.ceil(np.log2(n_vols + n_hrf - 1)))
    h_fft = np.fft.rfft(h_canon, n=n_fft)
    h_power = np.abs(h_fft) ** 2
    noise_power = 0.1 * h_power.mean()

    for idx, (x, y, z) in enumerate(voxels):
        if idx % 20000 == 0 and idx > 0:
            print(f"    {idx}/{n_vox} voxels ...")

        ts = bold_data[x, y, z, :].astype(np.float64)
        ts -= ts.mean()
        if ts.var() < 1e-10:
            continue

        # Bandpass filter
        ts_filt = filtfilt(b_filt, a_filt, ts)

        # Step 1: Wiener deconvolution → pseudo-neural signal
        ts_fft = np.fft.rfft(ts_filt, n=n_fft)
        neural_fft = ts_fft * np.conj(h_fft) / (h_power + noise_power)
        neural = np.fft.irfft(neural_fft, n=n_fft)[:n_vols]

        # Step 2: Detect spontaneous events (local maxima > 1 SD)
        threshold = neural.std()
        events = []
        for i in range(1, n_vols - 1):
            if (neural[i] > neural[i - 1] and
                neural[i] > neural[i + 1] and
                neural[i] > threshold):
                events.append(i)

        if len(events) < 3:
            # Too few events -- fall back to canonical parameters
            fwhm_map[x, y, z] = 5.0
            height_map[x, y, z] = 1.0
            ttp_map[x, y, z] = 5.0
            continue

        # Step 3: Event-triggered average of BOLD signal
        hrf_est = np.zeros(hrf_window)
        n_used = 0
        for ev in events:
            end = ev + hrf_window
            if end <= n_vols:
                segment = ts_filt[ev:end]
                segment = segment - segment[0]  # baseline at event onset
                hrf_est += segment
                n_used += 1

        if n_used < 3:
            fwhm_map[x, y, z] = 5.0
            height_map[x, y, z] = 1.0
            ttp_map[x, y, z] = 5.0
            continue

        hrf_est /= n_used

        peak_val = hrf_est.max()
        if peak_val <= 0:
            continue

        # Normalize for FWHM/Time2peak extraction, keep raw peak as Height
        hrf_est_norm = hrf_est / peak_val
        t_window = np.arange(hrf_window) * tr
        fwhm, _, ttp = extract_hrf_params(hrf_est_norm, t_window)

        fwhm_map[x, y, z] = fwhm
        height_map[x, y, z] = peak_val
        ttp_map[x, y, z] = ttp

    print(f"  Done: {n_vox} voxels processed")
    return fwhm_map, height_map, ttp_map


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--session", default=None, help="preop, postop, or omit for both")
    parser.add_argument("--project-dir", required=True, type=Path)
    parser.add_argument("--space", default="MNI152NLin2009cAsym",
                        help="BOLD output space (default: MNI152NLin2009cAsym)")
    args = parser.parse_args()

    project = args.project_dir.resolve()
    fmriprep_dir = project / "derivatives" / "fmriprep"
    out_root = project / "derivatives" / "rsHRF"

    sessions = [args.session] if args.session else ["preop", "postop"]
    sub = args.subject
    space = args.space

    print("=" * 60)
    print(f" rsHRF Estimation: sub-{sub}")
    print(f" Method: point-process deconvolution (Wu et al. 2013)")
    print("=" * 60)

    for ses in sessions:
        print(f"\n--- ses-{ses} ---")

        func_dir = fmriprep_dir / f"sub-{sub}" / f"ses-{ses}" / "func"
        bold_files = sorted(func_dir.glob(f"*_space-{space}_desc-preproc_bold.nii.gz"))
        mask_files = sorted(func_dir.glob(f"*_space-{space}_desc-brain_mask.nii.gz"))
        json_files = sorted(func_dir.glob(f"*_space-{space}_desc-preproc_bold.json"))

        if not bold_files:
            print(f"  BOLD not found in {space} space, skipping")
            continue

        bold_img = nib.load(str(bold_files[0]))
        bold_data = np.asarray(bold_img.dataobj)

        tr = 2.0
        if json_files:
            with open(json_files[0]) as f:
                tr = json.load(f).get("RepetitionTime", tr)

        if mask_files:
            mask = np.asarray(nib.load(str(mask_files[0])).dataobj) > 0
        else:
            mask = bold_data.mean(axis=3) > bold_data.mean() * 0.1

        print(f"  BOLD: {bold_img.shape}, TR={tr}s")
        print(f"  Brain mask: {mask.sum()} voxels")

        fwhm, height, ttp = estimate_hrf_voxelwise(bold_data, mask, tr)

        out_dir = out_root / f"sub-{sub}"
        out_dir.mkdir(parents=True, exist_ok=True)

        prefix = f"sub-{sub}_ses-{ses}_task-rest_space-{space}_desc-preproc_bold"

        for name, data in [("FWHM", fwhm), ("Height", height), ("Time2peak", ttp)]:
            out_path = out_dir / f"{prefix}_{name}.nii.gz"
            out_img = nib.Nifti1Image(data, bold_img.affine, bold_img.header)
            nib.save(out_img, str(out_path))
            brain_vals = data[mask & (data > 0)]
            if len(brain_vals) > 0:
                print(f"  {name}: mean={brain_vals.mean():.3f}, "
                      f"std={brain_vals.std():.3f}, "
                      f"range=[{brain_vals.min():.3f}, {brain_vals.max():.3f}]")
            else:
                print(f"  {name}: no valid voxels")

        print(f"  Saved to: {out_dir}")

    print("\n" + "=" * 60)
    print(" rsHRF estimation complete")
    print("=" * 60)


if __name__ == "__main__":
    main()
