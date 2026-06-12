"""
Compare CoverM abundance (RPKM) across three reads_mode runs:
  raw  /  host_removed  /  trimmed_host_removed

Usage:
    python compare_modes.py

Outputs:
    compare_modes_phage.png
    compare_modes_plasmid.png
    compare_modes_correlation.tsv
"""

import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy.stats import pearsonr, spearmanr

# ── paths ─────────────────────────────────────────────────────────────────────
RESULTS = Path("results")
MODES = {
    "raw":                   RESULTS / "test_raw",
    "host_removed":          RESULTS / "test_host_removed",
    "trimmed_host_removed":  RESULTS / "test_trimmed_host_removed",
}
MGE_TYPES = ["phage", "plasmid"]
METRIC = "RPKM"


def load_abundance(mode_dir: Path, mge_type: str) -> pd.DataFrame:
    """Read abundance TSV and return long-format dataframe (contig, sample, rpkm)."""
    path = mode_dir / "abundance" / f"{mge_type}_abundance.tsv"
    if not path.exists():
        sys.exit(f"Missing: {path}")

    df = pd.read_csv(path, sep="\t")
    rpkm_cols = [c for c in df.columns if METRIC in c]

    # normalise sample names: strip " RPKM" / "_sorted RPKM" suffix
    rename = {c: re.sub(r"_sorted RPKM$| RPKM$", "", c) for c in rpkm_cols}
    df = df[["Contig"] + rpkm_cols].rename(columns=rename)

    long = df.melt(id_vars="Contig", var_name="sample", value_name="rpkm")
    return long


def build_comparison(mge_type: str) -> pd.DataFrame:
    """Merge all modes into one dataframe."""
    frames = {}
    for mode, path in MODES.items():
        df = load_abundance(path, mge_type)
        df = df.rename(columns={"rpkm": mode})
        frames[mode] = df.set_index(["Contig", "sample"])

    merged = pd.concat(frames.values(), axis=1).reset_index()
    # keep rows where at least one mode has non-zero abundance
    mode_cols = list(MODES.keys())
    merged = merged[(merged[mode_cols] > 0).any(axis=1)].copy()
    return merged


def scatter_pair(ax, df, x_mode, y_mode, title):
    """Log-scale scatter + identity line + correlation stats."""
    x = df[x_mode].values
    y = df[y_mode].values

    # replace 0 with NaN for log scale
    mask = (x > 0) & (y > 0)
    x_plot, y_plot = x[mask], y[mask]

    ax.scatter(x_plot, y_plot, alpha=0.4, s=10, linewidths=0)
    ax.set_xscale("log")
    ax.set_yscale("log")

    lims = [
        min(x_plot.min(), y_plot.min()) * 0.5,
        max(x_plot.max(), y_plot.max()) * 2,
    ]
    ax.plot(lims, lims, "r--", linewidth=0.8, label="y = x")
    ax.set_xlim(lims)
    ax.set_ylim(lims)

    r_p, _ = pearsonr(np.log10(x_plot), np.log10(y_plot))
    r_s, _ = spearmanr(x_plot, y_plot)

    ax.set_title(title, fontsize=9)
    ax.set_xlabel(x_mode, fontsize=8)
    ax.set_ylabel(y_mode, fontsize=8)
    ax.text(
        0.05, 0.95,
        f"n={mask.sum()}\nPearson r={r_p:.3f}\nSpearman ρ={r_s:.3f}",
        transform=ax.transAxes,
        va="top", fontsize=7,
        bbox=dict(boxstyle="round,pad=0.3", fc="white", alpha=0.7),
    )

    return {"x": x_mode, "y": y_mode, "n": int(mask.sum()),
            "pearson_r": round(r_p, 4), "spearman_rho": round(r_s, 4)}


def plot_mge(mge_type: str, df: pd.DataFrame):
    pairs = [
        ("raw", "host_removed"),
        ("raw", "trimmed_host_removed"),
        ("host_removed", "trimmed_host_removed"),
    ]
    samples = df["sample"].unique()
    n_samples = len(samples)

    fig, axes = plt.subplots(
        n_samples, len(pairs),
        figsize=(4 * len(pairs), 4 * n_samples),
        squeeze=False,
    )
    fig.suptitle(f"{mge_type.capitalize()} — RPKM comparison", fontsize=11, y=1.01)

    records = []
    for col, (x_mode, y_mode) in enumerate(pairs):
        for row, sample in enumerate(sorted(samples)):
            sub = df[df["sample"] == sample]
            title = f"{sample}\n{x_mode} vs {y_mode}"
            stats = scatter_pair(axes[row][col], sub, x_mode, y_mode, title)
            stats["sample"] = sample
            stats["mge_type"] = mge_type
            records.append(stats)

    fig.tight_layout()
    out = f"compare_modes_{mge_type}.png"
    fig.savefig(out, dpi=150, bbox_inches="tight")
    print(f"Saved {out}")
    return records


DETECTION_THRESHOLD = 1.0   # RPKM > this → "detected"
GROUND_TRUTH = "trimmed_host_removed"


def detection_metrics(df: pd.DataFrame, mge_type: str) -> pd.DataFrame:
    """
    Binary classification metrics using trimmed_host_removed as ground truth.

    For each (sample, mode) pair:
      detected   = RPKM > DETECTION_THRESHOLD
      ground truth = trimmed_host_removed detected

      TP = detected in both mode and ground truth
      FP = detected in mode, not in ground truth
      FN = not detected in mode, but in ground truth
      TN = not detected in either

      Precision   = TP / (TP + FP)
      Recall      = TP / (TP + FN)
      Specificity = TN / (TN + FP)
    """
    compare_modes = [m for m in MODES if m != GROUND_TRUTH]
    records = []

    for sample in sorted(df["sample"].unique()):
        sub = df[df["sample"] == sample].copy()
        gt = sub[GROUND_TRUTH] > DETECTION_THRESHOLD

        for mode in compare_modes:
            pred = sub[mode] > DETECTION_THRESHOLD

            tp = (pred & gt).sum()
            fp = (pred & ~gt).sum()
            fn = (~pred & gt).sum()
            tn = (~pred & ~gt).sum()

            precision   = tp / (tp + fp) if (tp + fp) > 0 else float("nan")
            recall      = tp / (tp + fn) if (tp + fn) > 0 else float("nan")
            specificity = tn / (tn + fp) if (tn + fp) > 0 else float("nan")

            records.append({
                "mge_type":    mge_type,
                "sample":      sample,
                "mode":        mode,
                "threshold":   DETECTION_THRESHOLD,
                "TP": int(tp), "FP": int(fp), "FN": int(fn), "TN": int(tn),
                "precision":   round(precision,   4),
                "recall":      round(recall,      4),
                "specificity": round(specificity, 4),
            })

    return pd.DataFrame(records)


def main():
    all_corr  = []
    all_class = []

    for mge_type in MGE_TYPES:
        print(f"\nLoading {mge_type}...")
        df = build_comparison(mge_type)
        print(f"  {len(df)} contig × sample rows (non-zero in at least one mode)")

        corr_stats = plot_mge(mge_type, df)
        all_corr.extend(corr_stats)

        class_stats = detection_metrics(df, mge_type)
        all_class.append(class_stats)

    corr_df = pd.DataFrame(all_corr)[
        ["mge_type", "sample", "x", "y", "n", "pearson_r", "spearman_rho"]
    ]
    corr_df.to_csv("compare_modes_correlation.tsv", sep="\t", index=False)
    print("\nCorrelation summary:")
    print(corr_df.to_string(index=False))

    class_df = pd.concat(all_class, ignore_index=True)
    class_df.to_csv("compare_modes_classification.tsv", sep="\t", index=False)
    print(f"\nClassification metrics (ground truth = {GROUND_TRUTH}, threshold RPKM > {DETECTION_THRESHOLD}):")
    print(class_df[["mge_type", "sample", "mode", "TP", "FP", "FN", "TN",
                     "precision", "recall", "specificity"]].to_string(index=False))


if __name__ == "__main__":
    main()
