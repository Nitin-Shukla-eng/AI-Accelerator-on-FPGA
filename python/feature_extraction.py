"""
feature_extraction.py
----------------------
Converts raw vibration sensor recordings into normalized statistical
feature vectors: RMS, Peak, Kurtosis, Crest Factor (in that fixed order,
matching FEATURE0..FEATURE3 in the HDS register map).

This module is imported (not just run) by both train.py and evaluate.py,
so that training and evaluation always apply identical preprocessing.

Usage (standalone):
    python3 feature_extraction.py
Reads:  dataset/raw/manifest.csv + dataset/raw/<filename>.csv
Writes: dataset/processed/features.npz
"""

import os
import glob
import numpy as np
import scipy.io as sio

import config
import utils


def compute_features(signal):
    """Compute the four statistical features for one raw vibration signal.

    signal: 1D numpy array of raw samples.
    Returns: numpy array [rms, peak, kurtosis, crest_factor], float64.
    """
    signal = np.asarray(signal, dtype=np.float64)

    rms = np.sqrt(np.mean(signal ** 2))
    peak = np.max(np.abs(signal))

    mean = np.mean(signal)
    std = np.std(signal)
    if std == 0:
        kurtosis = 0.0
    else:
        kurtosis = np.mean(((signal - mean) / std) ** 4) - 3.0  # excess kurtosis

    crest_factor = peak / rms if rms != 0 else 0.0

    return np.array([rms, peak, kurtosis, crest_factor], dtype=np.float64)


def _load_de_signal(mat_path):
    """Load a CWRU .mat file and return its drive-end (*_DE_time) signal
    as a 1D float64 array, regardless of the exact variable name inside
    (CWRU files name this e.g. X097_DE_time, X118_DE_time, etc.)."""
    mat = sio.loadmat(mat_path)
    de_keys = [k for k in mat.keys() if k.endswith("_DE_time")]
    if not de_keys:
        raise KeyError(f"No *_DE_time key found in {mat_path}; "
                        f"keys present: {list(mat.keys())}")
    return mat[de_keys[0]].reshape(-1).astype(np.float64)


def _label_from_filename(filename):
    """CWRU naming: Normal_*.mat -> 0 (Normal); B*/IR*/OR*.mat (ball / inner
    race / outer race fault) -> 1 (Fault)."""
    return 0 if os.path.basename(filename).startswith("Normal") else 1


def load_raw_dataset():
    """Load every .mat recording in dataset/raw/, slice each into fixed-length
    windows (config.WINDOW_SIZE / config.WINDOW_STRIDE), and compute one
    4-feature vector per window.

    Returns:
        features: (N, 4) float64 array, raw (un-normalized) feature values
        labels:   (N,) int array, 0=Normal, 1=Fault
        sources:  list of str, source filename for each row (for debugging /
                  tracing a feature vector back to its recording)
    """
    mat_paths = sorted(glob.glob(os.path.join(config.DATASET_RAW_DIR, "*.mat")))
    if not mat_paths:
        raise FileNotFoundError(
            f"No .mat files found in {config.DATASET_RAW_DIR}. "
            f"See dataset/README.md for the expected raw dataset layout."
        )

    feature_rows, label_rows, source_rows = [], [], []

    for mat_path in mat_paths:
        signal = _load_de_signal(mat_path)
        label = _label_from_filename(mat_path)

        n_windows = 1 + (len(signal) - config.WINDOW_SIZE) // config.WINDOW_STRIDE
        for w in range(max(n_windows, 0)):
            start = w * config.WINDOW_STRIDE
            window = signal[start:start + config.WINDOW_SIZE]
            if len(window) < config.WINDOW_SIZE:
                continue
            feature_rows.append(compute_features(window))
            label_rows.append(label)
            source_rows.append(os.path.basename(mat_path))

    features = np.array(feature_rows, dtype=np.float64)
    labels = np.array(label_rows, dtype=np.int64)

    if config.BALANCE_CLASSES:
        rng = np.random.default_rng(config.RANDOM_SEED)
        idx0 = np.where(labels == 0)[0]
        idx1 = np.where(labels == 1)[0]
        n_min = min(len(idx0), len(idx1))
        idx0 = rng.choice(idx0, size=n_min, replace=False)
        idx1 = rng.choice(idx1, size=n_min, replace=False)
        keep = np.sort(np.concatenate([idx0, idx1]))
        features = features[keep]
        labels = labels[keep]
        source_rows = [source_rows[i] for i in keep]

    return features, labels, source_rows


def build_processed_dataset():
    """Full pipeline: load raw -> compute features -> split -> normalize
    (stats computed on the TRAIN split only) -> save to
    dataset/processed/features.npz.
    """
    utils.set_seed()

    raw_features, labels, filenames = load_raw_dataset()
    n = len(labels)
    utils.log(f"loaded {n} raw recordings "
              f"({int((labels == 0).sum())} normal, {int((labels == 1).sum())} fault)")

    # Shuffle once, deterministically, before splitting.
    idx = np.random.permutation(n)
    raw_features = raw_features[idx]
    labels = labels[idx]
    filenames = [filenames[i] for i in idx]

    n_train = int(n * config.TRAIN_SPLIT)
    n_val = int(n * config.VAL_SPLIT)
    # test gets the remainder, so splits always sum to n exactly

    train_feat = raw_features[:n_train]
    val_feat = raw_features[n_train:n_train + n_val]
    test_feat = raw_features[n_train + n_val:]

    train_labels = labels[:n_train]
    val_labels = labels[n_train:n_train + n_val]
    test_labels = labels[n_train + n_val:]

    if config.NORMALIZE_FEATURES:
        mean, std = utils.compute_normalization_stats(train_feat)
        train_feat_n = utils.apply_normalization(train_feat, mean, std)
        val_feat_n = utils.apply_normalization(val_feat, mean, std)
        test_feat_n = utils.apply_normalization(test_feat, mean, std)
    else:
        mean, std = np.zeros(config.NUM_FEATURES), np.ones(config.NUM_FEATURES)
        train_feat_n, val_feat_n, test_feat_n = train_feat, val_feat, test_feat

    utils.log(f"split sizes -> train={len(train_labels)}, "
              f"val={len(val_labels)}, test={len(test_labels)}")

    utils.save_npz(
        config.PROCESSED_FEATURES_PATH,
        train_features=train_feat_n, train_labels=train_labels,
        val_features=val_feat_n, val_labels=val_labels,
        test_features=test_feat_n, test_labels=test_labels,
        norm_mean=mean, norm_std=std,
        feature_names=np.array(config.FEATURE_NAMES),
    )


if __name__ == "__main__":
    build_processed_dataset()
