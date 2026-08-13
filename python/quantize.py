"""
quantize.py
-----------
Converts the trained floating-point model into Q8.8 fixed-point
representation, and verifies the resulting accuracy loss is acceptable
BEFORE letting export_model.py consume it. If the quantized model's
accuracy drops too far relative to the floating-point model, this
script raises an error rather than silently proceeding -- per spec,
excessive quantization error means revisit the Q-format or retrain.

Usage:
    python3 quantize.py
Reads:  python/artifacts/model_float.npz, dataset/processed/features.npz
Writes: python/artifacts/model_quant.npz, quantization_error_report.txt
"""

import numpy as np

import config
import utils
import train  # reuse forward()/accuracy() logic on the float side


def quantize_forward(params_q, X_float):
    """Run the SAME forward pass the RTL/firmware will run, entirely in
    Q8.8 integer arithmetic, given already-normalized float input features.

    This is the reference model that software_nn.c and the RTL accelerator
    must both match bit-for-bit. IMPORTANT: this must mirror mac.v's actual
    arithmetic exactly -- mac.v renormalizes EACH product individually
    (arithmetic right shift by FRAC_BITS) BEFORE accumulating, rather than
    summing raw Q16.16 products and shifting once at the end. These are
    NOT equivalent (per-term truncation loses up to 1 LSB per term versus
    a single shift after the sum) -- matching mac.v's order here is what
    keeps this reference bit-exact against the RTL (see rtl/math/mac.v and
    PHASE3_NOTES.md).
    """
    X_q = utils.float_to_q88(X_float)                    # (N, 4) int32, Q8.8

    W1_q, b1_q = params_q["W1_q"], params_q["b1_q"]        # (4,8), (8,)
    W2_q, b2_q = params_q["W2_q"], params_q["b2_q"]        # (8,2), (2,)

    n = X_q.shape[0]
    hidden_q = np.zeros((n, config.NUM_HIDDEN), dtype=np.int64)

    # Hidden layer: mac.v renormalizes each product (arithmetic >>> FRAC_BITS)
    # BEFORE accumulating -- match that exactly, term by term.
    for j in range(config.NUM_HIDDEN):
        acc = np.zeros(n, dtype=np.int64)
        for i in range(config.NUM_INPUTS):
            product = X_q[:, i].astype(np.int64) * int(W1_q[i, j])
            renormalized = product >> config.Q_FRAC_BITS  # arithmetic shift (floor), matches Verilog >>>
            acc += renormalized
        acc += int(b1_q[j])
        hidden_q[:, j] = acc

    hidden_relu_q = np.maximum(0, hidden_q)
    hidden_relu_q = utils.clip_to_q_range(hidden_relu_q)

    output_q = np.zeros((n, config.NUM_OUTPUTS), dtype=np.int64)
    for k in range(config.NUM_OUTPUTS):
        acc = np.zeros(n, dtype=np.int64)
        for j in range(config.NUM_HIDDEN):
            product = hidden_relu_q[:, j].astype(np.int64) * int(W2_q[j, k])
            renormalized = product >> config.Q_FRAC_BITS
            acc += renormalized
        acc += int(b2_q[k])
        output_q[:, k] = acc

    output_q = utils.clip_to_q_range(output_q)
    preds = np.argmax(output_q, axis=1)
    return output_q, hidden_relu_q, preds


def quantize_model():
    float_model = utils.load_npz(config.FLOAT_MODEL_PATH)
    data = utils.load_npz(config.PROCESSED_FEATURES_PATH)

    W1, b1 = float_model["W1"], float_model["b1"]
    W2, b2 = float_model["W2"], float_model["b2"]

    # --- Quantize every parameter to Q8.8 ---
    params_q = {
        "W1_q": utils.float_to_q88(W1),
        "b1_q": utils.float_to_q88(b1),
        "W2_q": utils.float_to_q88(W2),
        "b2_q": utils.float_to_q88(b2),
    }

    # --- Check quantization error on the test split ---
    X_test, y_test = data["test_features"], data["test_labels"]

    # Floating-point reference predictions
    float_params = {"W1": W1, "b1": b1, "W2": W2, "b2": b2}
    float_logits, _ = train.forward(float_params, X_test)
    float_preds = np.argmax(float_logits, axis=1)
    float_acc = float((float_preds == y_test).mean())

    # Quantized predictions (Q8.8 integer arithmetic, as RTL/firmware will do it)
    _, _, quant_preds = quantize_forward(params_q, X_test)
    quant_acc = float((quant_preds == y_test).mean())

    accuracy_drop = float_acc - quant_acc
    weight_mse = float(np.mean((utils.q88_to_float(params_q["W1_q"]) - W1) ** 2))

    report_lines = [
        "Quantization Error Report",
        "==========================",
        f"Floating-point test accuracy : {float_acc:.4f}",
        f"Quantized  (Q8.8) test accuracy : {quant_acc:.4f}",
        f"Accuracy drop                   : {accuracy_drop:.4f}",
        f"Max acceptable drop (config.py) : {config.MAX_ACCEPTABLE_ACCURACY_DROP:.4f}",
        f"W1 weight quantization MSE      : {weight_mse:.6e}",
        f"Prediction agreement (float vs quant): "
        f"{float((float_preds == quant_preds).mean()):.4f}",
    ]
    report = "\n".join(report_lines)
    utils.log("\n" + report)

    utils.ensure_dir(config.QUANT_ERROR_REPORT_PATH)
    with open(config.QUANT_ERROR_REPORT_PATH, "w") as f:
        f.write(report + "\n")

    if accuracy_drop > config.MAX_ACCEPTABLE_ACCURACY_DROP:
        raise RuntimeError(
            f"Quantization accuracy drop ({accuracy_drop:.4f}) exceeds "
            f"MAX_ACCEPTABLE_ACCURACY_DROP ({config.MAX_ACCEPTABLE_ACCURACY_DROP}). "
            f"Revisit the Q-format or retrain before proceeding to export_model.py."
        )

    utils.save_npz(
        config.QUANT_MODEL_PATH,
        W1_q=params_q["W1_q"], b1_q=params_q["b1_q"],
        W2_q=params_q["W2_q"], b2_q=params_q["b2_q"],
        norm_mean=float_model["norm_mean"], norm_std=float_model["norm_std"],
        float_test_accuracy=float_acc, quant_test_accuracy=quant_acc,
    )

    return params_q


if __name__ == "__main__":
    quantize_model()
