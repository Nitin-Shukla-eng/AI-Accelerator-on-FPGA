"""
train.py
--------
Trains the 4 -> 8 -> 2 ReLU feed-forward classifier on the processed
feature dataset. Implemented directly in numpy (no torch/tensorflow
dependency) -- the network is tiny, and hand-rolling forward/backward
here keeps the exact arithmetic fully transparent, which matters since
quantize.py and the RTL both need to reproduce this forward pass exactly.

Usage:
    python3 train.py
Reads:  dataset/processed/features.npz
Writes: python/artifacts/model_float.npz, training_curves.png
"""

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import config
import utils


def init_params():
    """He-style init, small enough to keep early activations well inside
    the eventual Q8.8 range."""
    rng = np.random.default_rng(config.RANDOM_SEED)
    W1 = rng.normal(0, np.sqrt(2.0 / config.NUM_INPUTS),
                     size=(config.NUM_INPUTS, config.NUM_HIDDEN))
    b1 = np.zeros(config.NUM_HIDDEN)
    W2 = rng.normal(0, np.sqrt(2.0 / config.NUM_HIDDEN),
                     size=(config.NUM_HIDDEN, config.NUM_OUTPUTS))
    b2 = np.zeros(config.NUM_OUTPUTS)
    return {"W1": W1, "b1": b1, "W2": W2, "b2": b2}


def relu(x):
    return np.maximum(0, x)


def forward(params, X):
    """Forward pass. X: (N, 4). Returns (logits, cache) where logits: (N, 2)."""
    z1 = X @ params["W1"] + params["b1"]      # (N, 8)
    a1 = relu(z1)                              # hidden activations (ReLU)
    logits = a1 @ params["W2"] + params["b2"]  # (N, 2) -- no activation, per spec
    cache = {"X": X, "z1": z1, "a1": a1, "logits": logits}
    return logits, cache


def softmax_cross_entropy_loss(logits, labels):
    """Standard softmax + cross-entropy, plus its gradient w.r.t. logits."""
    shifted = logits - logits.max(axis=1, keepdims=True)
    exp = np.exp(shifted)
    probs = exp / exp.sum(axis=1, keepdims=True)

    n = logits.shape[0]
    correct_logprobs = -np.log(np.clip(probs[np.arange(n), labels], 1e-12, None))
    loss = correct_logprobs.mean()

    dlogits = probs.copy()
    dlogits[np.arange(n), labels] -= 1
    dlogits /= n
    return loss, dlogits


def backward(params, cache, dlogits):
    X, z1, a1 = cache["X"], cache["z1"], cache["a1"]

    dW2 = a1.T @ dlogits + config.L2_REG * params["W2"]
    db2 = dlogits.sum(axis=0)

    da1 = dlogits @ params["W2"].T
    dz1 = da1 * (z1 > 0)  # ReLU gradient

    dW1 = X.T @ dz1 + config.L2_REG * params["W1"]
    db1 = dz1.sum(axis=0)

    return {"W1": dW1, "b1": db1, "W2": dW2, "b2": db2}


def accuracy(params, X, labels):
    logits, _ = forward(params, X)
    preds = np.argmax(logits, axis=1)
    return float((preds == labels).mean())


def train_model():
    utils.set_seed()
    data = utils.load_npz(config.PROCESSED_FEATURES_PATH)

    X_train, y_train = data["train_features"], data["train_labels"]
    X_val, y_val = data["val_features"], data["val_labels"]
    X_test, y_test = data["test_features"], data["test_labels"]

    params = init_params()
    n_train = X_train.shape[0]

    history = {"epoch": [], "train_loss": [], "train_acc": [], "val_acc": []}

    for epoch in range(1, config.NUM_EPOCHS + 1):
        # Shuffle each epoch, mini-batch gradient descent.
        perm = np.random.permutation(n_train)
        X_shuf, y_shuf = X_train[perm], y_train[perm]

        epoch_losses = []
        for start in range(0, n_train, config.BATCH_SIZE):
            end = start + config.BATCH_SIZE
            Xb, yb = X_shuf[start:end], y_shuf[start:end]

            logits, cache = forward(params, Xb)
            loss, dlogits = softmax_cross_entropy_loss(logits, yb)
            grads = backward(params, cache, dlogits)

            for key in params:
                params[key] -= config.LEARNING_RATE * grads[key]

            epoch_losses.append(loss)

        if epoch % 10 == 0 or epoch == 1 or epoch == config.NUM_EPOCHS:
            train_acc = accuracy(params, X_train, y_train)
            val_acc = accuracy(params, X_val, y_val)
            history["epoch"].append(epoch)
            history["train_loss"].append(float(np.mean(epoch_losses)))
            history["train_acc"].append(train_acc)
            history["val_acc"].append(val_acc)
            utils.log(f"epoch {epoch:4d}  loss={np.mean(epoch_losses):.4f}  "
                      f"train_acc={train_acc:.3f}  val_acc={val_acc:.3f}")

    test_acc = accuracy(params, X_test, y_test)
    utils.log(f"final floating-point test accuracy: {test_acc:.4f}")

    # Save the trained floating-point model + normalization stats (needed
    # later so hardware/firmware inputs are normalized identically).
    utils.save_npz(
        config.FLOAT_MODEL_PATH,
        W1=params["W1"], b1=params["b1"],
        W2=params["W2"], b2=params["b2"],
        norm_mean=data["norm_mean"], norm_std=data["norm_std"],
        test_accuracy=test_acc,
    )

    # Plot + save training curves.
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    axes[0].plot(history["epoch"], history["train_loss"])
    axes[0].set_title("Training loss")
    axes[0].set_xlabel("epoch")
    axes[1].plot(history["epoch"], history["train_acc"], label="train")
    axes[1].plot(history["epoch"], history["val_acc"], label="val")
    axes[1].set_title("Accuracy")
    axes[1].set_xlabel("epoch")
    axes[1].legend()
    fig.tight_layout()
    utils.ensure_dir(config.TRAINING_CURVES_PATH)
    fig.savefig(config.TRAINING_CURVES_PATH, dpi=120)
    utils.log(f"saved {config.TRAINING_CURVES_PATH}")

    return params, test_acc


if __name__ == "__main__":
    train_model()
