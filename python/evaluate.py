"""
evaluate.py
-----------
Compares predictions across up to four sources -- floating-point,
quantized (Q8.8, Python reference), software (firmware, once available),
and hardware (accelerator, once available) -- against ground truth, and
reports accuracy/precision/recall/F1/confusion matrix for each.

Early in the project (Phase 2), only floating-point and quantized
predictions exist -- run it in that mode. After Phase 5 (firmware) and
Phase 8 (hardware bring-up), pass in the software/hardware prediction
logs too for the full four-way comparison that results/comparison/
needs.

Usage:
    python3 evaluate.py
        (float vs. quantized only, using the test split)

    python3 evaluate.py --software path/to/sw_predictions.txt \\
                         --hardware path/to/hw_predictions.txt
        (full four-way comparison, one integer prediction per line,
         in the same order as generated/software/test_vectors.h)
"""

import argparse
import numpy as np

import config
import utils
import train
import quantize


def confusion_matrix(y_true, y_pred, num_classes=2):
    cm = np.zeros((num_classes, num_classes), dtype=np.int64)
    for t, p in zip(y_true, y_pred):
        cm[t, p] += 1
    return cm


def precision_recall_f1(cm):
    """Per-class precision/recall/F1 from a 2x2 confusion matrix (rows=true, cols=pred)."""
    results = {}
    num_classes = cm.shape[0]
    for c in range(num_classes):
        tp = cm[c, c]
        fp = cm[:, c].sum() - tp
        fn = cm[c, :].sum() - tp
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * precision * recall / (precision + recall)
              if (precision + recall) > 0 else 0.0)
        results[c] = {"precision": precision, "recall": recall, "f1": f1}
    return results


def report_for_source(name, y_true, y_pred):
    accuracy = float((y_true == y_pred).mean())
    cm = confusion_matrix(y_true, y_pred)
    prf = precision_recall_f1(cm)

    lines = [f"--- {name} ---", f"accuracy: {accuracy:.4f}", f"confusion matrix (rows=true, cols=pred):"]
    lines.append(str(cm))
    for c, label in enumerate(["Normal", "Fault"]):
        m = prf[c]
        lines.append(f"  class {label}: precision={m['precision']:.4f} "
                      f"recall={m['recall']:.4f} f1={m['f1']:.4f}")
    return "\n".join(lines), accuracy


def load_prediction_file(path, n_expected):
    preds = np.loadtxt(path, dtype=int)
    preds = np.atleast_1d(preds)
    if len(preds) != n_expected:
        raise ValueError(
            f"{path} has {len(preds)} predictions, expected {n_expected} "
            f"(must match generated/software/test_vectors.h)."
        )
    return preds


def evaluate_all(software_path=None, hardware_path=None):
    data = utils.load_npz(config.PROCESSED_FEATURES_PATH)
    float_model = utils.load_npz(config.FLOAT_MODEL_PATH)
    quant_model = utils.load_npz(config.QUANT_MODEL_PATH)

    X_test, y_test = data["test_features"], data["test_labels"]

    # --- Floating point ---
    float_params = {"W1": float_model["W1"], "b1": float_model["b1"],
                     "W2": float_model["W2"], "b2": float_model["b2"]}
    float_logits, _ = train.forward(float_params, X_test)
    float_preds = np.argmax(float_logits, axis=1)

    # --- Quantized (Python Q8.8 reference) ---
    params_q = {"W1_q": quant_model["W1_q"], "b1_q": quant_model["b1_q"],
                "W2_q": quant_model["W2_q"], "b2_q": quant_model["b2_q"]}
    _, _, quant_preds = quantize.quantize_forward(params_q, X_test)

    reports = []
    r, float_acc = report_for_source("Floating-point (Python)", y_test, float_preds)
    reports.append(r)
    r, quant_acc = report_for_source("Quantized Q8.8 (Python reference)", y_test, quant_preds)
    reports.append(r)

    agreement_float_quant = float((float_preds == quant_preds).mean())
    reports.append(f"\nfloat vs. quantized prediction agreement: {agreement_float_quant:.4f}")

    if software_path is not None:
        sw_preds = load_prediction_file(software_path, len(y_test))
        r, sw_acc = report_for_source("Software (PicoRV32 firmware)", y_test, sw_preds)
        reports.append(r)
        reports.append(f"quantized vs. software agreement: "
                        f"{float((quant_preds == sw_preds).mean()):.4f}")

    if hardware_path is not None:
        hw_preds = load_prediction_file(hardware_path, len(y_test))
        r, hw_acc = report_for_source("Hardware (accelerator)", y_test, hw_preds)
        reports.append(r)
        reports.append(f"quantized vs. hardware agreement: "
                        f"{float((quant_preds == hw_preds).mean()):.4f}")

    if software_path is not None and hardware_path is not None:
        reports.append(f"software vs. hardware agreement: "
                        f"{float((sw_preds == hw_preds).mean()):.4f}")

    full_report = "\n\n".join(reports)
    utils.log("\n" + full_report)

    out_path = config.RESULTS_COMPARISON_DIR + "/evaluation_report.txt"
    utils.ensure_dir(out_path)
    with open(out_path, "w") as f:
        f.write(full_report + "\n")
    utils.log(f"saved {out_path}")

    return full_report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--software", default=None,
                         help="path to a file with one integer prediction per "
                              "line from the firmware, matching test_vectors.h order")
    parser.add_argument("--hardware", default=None,
                         help="path to a file with one integer prediction per "
                              "line from the hardware accelerator, matching "
                              "test_vectors.h order")
    args = parser.parse_args()
    evaluate_all(software_path=args.software, hardware_path=args.hardware)
