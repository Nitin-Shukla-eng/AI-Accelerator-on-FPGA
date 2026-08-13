"""
config.py
---------
Single source of truth for every path, hyperparameter, and format setting
used across the TinyRISC-TinyML Python pipeline.

RULE (per project manifest): no other script in python/ may hardcode a
path, hyperparameter, or the network topology. If you need to change
something, change it here.
"""

import os

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------
# Repo root is two levels up from this file (python/config.py -> repo root)
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DATASET_RAW_DIR = os.path.join(REPO_ROOT, "dataset", "raw")
DATASET_PROCESSED_DIR = os.path.join(REPO_ROOT, "dataset", "processed")

# Raw dataset format (see dataset/README.md): CWRU bearing dataset .mat files
# placed directly in dataset/raw/ (e.g. Normal_0.mat, IR007_0.mat, B014_2.mat,
# OR0146_1.mat, ...). Each .mat file contains a `<id>_DE_time` array (drive-end
# accelerometer signal) which is what feature_extraction.py reads.
# Label rule: filename starts with "Normal" -> class 0 (Normal); every other
# filename (B*, IR*, OR* = ball/inner-race/outer-race faults) -> class 1 (Fault).

# Processed (feature-extracted) dataset output
PROCESSED_FEATURES_PATH = os.path.join(DATASET_PROCESSED_DIR, "features.npz")

# Model artifact outputs (floating point + quantized), kept in python/ as
# working artifacts -- NOT part of generated/ (generated/ is only the
# final C headers + Verilog ROMs written by export_model.py)
MODEL_DIR = os.path.join(REPO_ROOT, "python", "artifacts")
FLOAT_MODEL_PATH = os.path.join(MODEL_DIR, "model_float.npz")
QUANT_MODEL_PATH = os.path.join(MODEL_DIR, "model_quant.npz")
TRAINING_CURVES_PATH = os.path.join(MODEL_DIR, "training_curves.png")
QUANT_ERROR_REPORT_PATH = os.path.join(MODEL_DIR, "quantization_error_report.txt")

# Generated output locations (export_model.py is the ONLY script allowed
# to write here)
GENERATED_SOFTWARE_DIR = os.path.join(REPO_ROOT, "generated", "software")
GENERATED_HARDWARE_DIR = os.path.join(REPO_ROOT, "generated", "hardware")

WEIGHTS_H_PATH = os.path.join(GENERATED_SOFTWARE_DIR, "weights.h")
TEST_VECTORS_H_PATH = os.path.join(GENERATED_SOFTWARE_DIR, "test_vectors.h")
EXPECTED_OUTPUTS_H_PATH = os.path.join(GENERATED_SOFTWARE_DIR, "expected_outputs.h")

HIDDEN_WEIGHT_ROM_PATH = os.path.join(GENERATED_HARDWARE_DIR, "hidden_weight_rom.v")
HIDDEN_BIAS_ROM_PATH = os.path.join(GENERATED_HARDWARE_DIR, "hidden_bias_rom.v")
OUTPUT_WEIGHT_ROM_PATH = os.path.join(GENERATED_HARDWARE_DIR, "output_weight_rom.v")
OUTPUT_BIAS_ROM_PATH = os.path.join(GENERATED_HARDWARE_DIR, "output_bias_rom.v")

# Evaluation report output
RESULTS_COMPARISON_DIR = os.path.join(REPO_ROOT, "results", "comparison")

# ---------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------
RANDOM_SEED = 42

# ---------------------------------------------------------------------
# Feature extraction settings
# ---------------------------------------------------------------------
# The four features fed to the network, in this fixed order.
# This order MUST match FEATURE0..FEATURE3 in the HDS register map:
#   FEATURE0 = RMS, FEATURE1 = Peak, FEATURE2 = Kurtosis, FEATURE3 = Crest Factor
FEATURE_NAMES = ["rms", "peak", "kurtosis", "crest_factor"]
NUM_FEATURES = len(FEATURE_NAMES)

# Simple z-score normalization applied to each feature column independently.
# Mean/std are computed on the training split only, then re-used (frozen)
# for validation/test/hardware -- this is why feature_extraction.py must be
# shared by both train.py and evaluate.py rather than re-implemented.
NORMALIZE_FEATURES = True

# Each raw .mat recording is one long continuous signal (100k-500k samples).
# feature_extraction.py slices it into fixed-length, non-overlapping windows
# and computes one 4-feature vector per window -- this is what turns ~40 raw
# files into hundreds of independent training examples.
WINDOW_SIZE = 2048     # samples per window (~17ms at the CWRU 12kHz DE sample rate)
WINDOW_STRIDE = 2048   # non-overlapping; set < WINDOW_SIZE for overlapping windows

# CWRU Normal_* recordings are much longer than the fault recordings, so
# windowing alone yields noticeably more Normal windows than Fault windows.
# If True, the majority class is randomly (seeded) subsampled down to the
# minority class count after windowing, so training isn't biased by class
# imbalance that has nothing to do with the actual classification difficulty.
BALANCE_CLASSES = True

# ---------------------------------------------------------------------
# Network topology (FROZEN per SSD/HDS -- do not change without a
# documented revision; the RTL is not topology-generic)
# ---------------------------------------------------------------------
NUM_INPUTS = 4          # RMS, Peak, Kurtosis, Crest Factor
NUM_HIDDEN = 8          # hidden layer neurons, ReLU activation
NUM_OUTPUTS = 2         # Normal (class 0), Fault (class 1) -- no activation (raw scores)

# ---------------------------------------------------------------------
# Training hyperparameters
# ---------------------------------------------------------------------
TRAIN_SPLIT = 0.7
VAL_SPLIT = 0.15
TEST_SPLIT = 0.15        # must sum to 1.0 with TRAIN_SPLIT + VAL_SPLIT

LEARNING_RATE = 0.05
NUM_EPOCHS = 500
BATCH_SIZE = 16
L2_REG = 1e-4             # small weight decay to keep quantization well-behaved

# ---------------------------------------------------------------------
# Quantization settings (Q8.8 fixed point, 16-bit, FROZEN per spec)
# ---------------------------------------------------------------------
Q_INT_BITS = 8
Q_FRAC_BITS = 8
Q_TOTAL_BITS = Q_INT_BITS + Q_FRAC_BITS   # 16
Q_SCALE = 1 << Q_FRAC_BITS                # 256
Q_MIN_INT = -(1 << (Q_TOTAL_BITS - 1))     # -32768
Q_MAX_INT = (1 << (Q_TOTAL_BITS - 1)) - 1  #  32767

# Maximum acceptable accuracy drop (float model -> quantized model) before
# quantize.py should refuse to proceed and force a re-think of the Q-format.
MAX_ACCEPTABLE_ACCURACY_DROP = 0.02   # 2 percentage points

# ---------------------------------------------------------------------
# Test vector export settings
# ---------------------------------------------------------------------
# How many held-out test vectors to embed into test_vectors.h / expected_outputs.h
# for firmware + RTL simulation + hardware validation. Keep this small --
# these get compiled into PicoRV32 program memory and driven through
# testbenches by hand-inspectable arrays.
NUM_EXPORTED_TEST_VECTORS = 20
