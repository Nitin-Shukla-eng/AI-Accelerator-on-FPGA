"""
utils.py
--------
Reusable helper functions shared across the Python pipeline: seeding,
logging, file I/O helpers, and normalization. Nothing pipeline-specific
belongs here -- if a function only makes sense for training, it belongs
in train.py, not here.
"""

import os
import sys
import json
import numpy as np

import config


def set_seed(seed=None):
    """Seed numpy's RNG for reproducibility. Uses config.RANDOM_SEED by default."""
    if seed is None:
        seed = config.RANDOM_SEED
    np.random.seed(seed)
    return seed


def log(msg):
    """Simple timestamp-free logger -- kept trivial on purpose; swap for
    the `logging` module if the project grows."""
    print(f"[pipeline] {msg}", flush=True)


def ensure_dir(path):
    """Create the directory for `path` (or `path` itself if it's a dir) if missing."""
    d = path if os.path.isdir(path) or not os.path.splitext(path)[1] else os.path.dirname(path)
    if d and not os.path.exists(d):
        os.makedirs(d, exist_ok=True)


def save_npz(path, **arrays):
    ensure_dir(path)
    np.savez(path, **arrays)
    log(f"saved {path}")


def load_npz(path):
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"{path} not found -- run the earlier pipeline stage first."
        )
    return np.load(path, allow_pickle=True)


def compute_normalization_stats(features):
    """Return (mean, std) per-column, computed on `features` (train split only)."""
    mean = features.mean(axis=0)
    std = features.std(axis=0)
    std[std == 0] = 1.0  # guard against a constant feature column
    return mean, std


def apply_normalization(features, mean, std):
    return (features - mean) / std


def save_json(path, obj):
    ensure_dir(path)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def load_json(path):
    with open(path, "r") as f:
        return json.load(f)


def clip_to_q_range(int_array):
    """Clip an integer array into the valid Q8.8 16-bit signed range,
    per config.Q_MIN_INT / config.Q_MAX_INT. Used by quantize.py and
    export_model.py -- both must clip identically, or the RTL and the
    Python-side "expected" values could disagree at saturation."""
    return np.clip(int_array, config.Q_MIN_INT, config.Q_MAX_INT)


def float_to_q88(value):
    """Convert a float (or float array) to a Q8.8 signed 16-bit integer
    (or integer array), rounding to nearest and clipping on overflow."""
    scaled = np.round(np.asarray(value, dtype=np.float64) * config.Q_SCALE)
    return clip_to_q_range(scaled).astype(np.int32)


def q88_to_float(q_value):
    """Inverse of float_to_q88: integer Q8.8 -> float."""
    return np.asarray(q_value, dtype=np.float64) / config.Q_SCALE
