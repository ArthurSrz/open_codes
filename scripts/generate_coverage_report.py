#!/usr/bin/env python3
"""
Generate a coverage report comparing HuggingFace dataset vs ground truth.

Produces:
  - docs/coverage_report.png  (main dashboard with 4 charts)
  - docs/coverage_report.md   (GitHub-publishable markdown report)
  - docs/coverage_summary.json (machine-readable summary)

Usage:
    python scripts/generate_coverage_report.py
"""

import json
import os
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# ─── Ground Truth (from CLAUDE.md, March 2026) ───────────────────────────────

GROUND_TRUTH = {
    "code_articles": {
        "label": "Articles de loi",
        "emoji": "📖",
        "ground_truth": 42_943,
        "hf_rows": 200,
        "xano_db": 6_381,
        "source": "14 codes, PISTE API",
        "ground_truth_source": "PISTE manifest + vie-publique.fr",
        "codes": {
            "Code civil": {"ground_truth": 2_896, "textId": "LEGITEXT000006070721"},
            "Code de commerce": {"ground_truth": 7_178, "textId": "LEGITEXT000005634379"},
            "Code de la consommation": {"ground_truth": 2_172, "textId": "LEGITEXT000006069565"},
            "Code de la propriété intellectuelle": {"ground_truth": 1_600, "textId": "LEGITEXT000006069414"},
            "Code de la route": {"ground_truth": 800, "textId": "LEGITEXT000006074228"},
            "Code de l'urbanisme": {"ground_truth": 2_455, "textId": "LEGITEXT000006074075"},
            "Code de procédure civile": {"ground_truth": 2_075, "textId": "LEGITEXT000006070716"},
            "Code de procédure pénale": {"ground_truth": 2_400, "textId": "LEGITEXT000006071154"},
            "Code des communes": {"ground_truth": 221, "textId": "LEGITEXT000006070162"},
            "Code des proc. civiles d'exécution": {"ground_truth": 500, "textId": "LEGITEXT000025024948"},
            "Code du travail": {"ground_truth": 11_487, "textId": "LEGITEXT000006072050"},
            "Code électoral": {"ground_truth": 1_253, "textId": "LEGITEXT000006070239"},
            "Code gén. collectivités territoriales": {"ground_truth": 6_630, "textId": "LEGITEXT000006070633"},
            "Code pénal": {"ground_truth": 1_277, "textId": "LEGITEXT000006070719"},
        },
    },
    "jurisprudence": {
        "label": "Jurisprudence",
        "emoji": "⚖️",
        "ground_truth": 82_000,
        "hf_rows": 489,
        "xano_db": None,  # unknown exact count
        "source": "Judilibre API",
        "ground_truth_source": "~5-year window of ~1.76M total",
    },
    "circulaires": {
        "label": "Circulaires",
        "emoji": "📋",
        "ground_truth": 10_644,
        "hf_rows": 100,
        "xano_db": None,
        "source": "PISTE CIRC",
        "ground_truth_source": "DILA archives, all-time",
    },
    "reponses_legis": {
        "label": "Réponses ministérielles",
        "emoji": "💬",
        "ground_truth": 40_000,
        "hf_rows": 459,
        "xano_db": None,
        "source": "PISTE QR",
        "ground_truth_source": "~5-year window of ~200K total",
    },
}

REPORT_DATE = datetime.now().strftime("%Y-%m-%d")


def compute_stats():
    """Compute coverage percentages and gaps."""
    stats = {}
    for key, src in GROUND_TRUTH.items():
        gt = src["ground_truth"]
        hf = src["hf_rows"]
        coverage_pct = (hf / gt * 100) if gt > 0 else 0
        gap = gt - hf
        stats[key] = {
            "label": src["label"],
            "ground_truth": gt,
            "hf_rows": hf,
            "xano_db": src.get("xano_db"),
            "coverage_pct": round(coverage_pct, 2),
            "gap": gap,
            "source": src["source"],
        }
    total_gt = sum(s["ground_truth"] for s in GROUND_TRUTH.values())
    total_hf = sum(s["hf_rows"] for s in GROUND_TRUTH.values())
    stats["_total"] = {
        "label": "TOTAL",
        "ground_truth": total_gt,
        "hf_rows": total_hf,
        "coverage_pct": round(total_hf / total_gt * 100, 2),
        "gap": total_gt - total_hf,
    }
    return stats


def generate_charts(stats):
    """Generate a 4-panel coverage dashboard as PNG."""
    fig = plt.figure(figsize=(18, 14), facecolor="#0d1117")
    fig.suptitle(
        f"OpenCode — Dataset Coverage Report ({REPORT_DATE})",
        fontsize=20,
        fontweight="bold",
        color="white",
        y=0.97,
    )
    fig.text(
        0.5, 0.935,
        "HuggingFace dataset (ArthurSrz/open_codes) vs Ground Truth",
        ha="center", fontsize=13, color="#8b949e",
    )

    colors_gt = "#58a6ff"
    colors_hf = "#f97583"
    colors_gap = "#8b949e"
    bg_color = "#161b22"
    text_color = "#c9d1d9"
    grid_color = "#21262d"

    # ── Chart 1: Side-by-side bar chart ──────────────────────────────────────
    ax1 = fig.add_subplot(2, 2, 1, facecolor=bg_color)
    sources = [s for k, s in stats.items() if k != "_total"]
    labels = [s["label"] for s in sources]
    gt_vals = [s["ground_truth"] for s in sources]
    hf_vals = [s["hf_rows"] for s in sources]

    x = np.arange(len(labels))
    width = 0.35
    bars_gt = ax1.bar(x - width / 2, gt_vals, width, label="Ground Truth", color=colors_gt, alpha=0.85)
    bars_hf = ax1.bar(x + width / 2, hf_vals, width, label="HF Dataset", color=colors_hf, alpha=0.85)

    ax1.set_ylabel("Number of records", color=text_color, fontsize=11)
    ax1.set_title("Records: Ground Truth vs HF Dataset", color="white", fontsize=13, fontweight="bold", pad=12)
    ax1.set_xticks(x)
    ax1.set_xticklabels(labels, fontsize=9, color=text_color, rotation=15, ha="right")
    ax1.legend(facecolor=bg_color, edgecolor=grid_color, labelcolor=text_color)
    ax1.set_yscale("log")
    ax1.yaxis.set_major_formatter(ticker.FuncFormatter(lambda val, _: f"{val:,.0f}"))
    ax1.tick_params(colors=text_color)
    ax1.grid(axis="y", color=grid_color, alpha=0.5)
    for spine in ax1.spines.values():
        spine.set_color(grid_color)

    # Add value labels on bars
    for bar in bars_gt:
        h = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width() / 2, h * 1.15, f"{h:,}", ha="center", va="bottom", fontsize=8, color=colors_gt)
    for bar in bars_hf:
        h = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width() / 2, h * 1.15, f"{h:,}", ha="center", va="bottom", fontsize=8, color=colors_hf)

    # ── Chart 2: Coverage % gauge bars ───────────────────────────────────────
    ax2 = fig.add_subplot(2, 2, 2, facecolor=bg_color)
    coverages = [s["coverage_pct"] for s in sources]
    y_pos = np.arange(len(labels))

    # Background bars (100%)
    ax2.barh(y_pos, [100] * len(labels), color=grid_color, alpha=0.3, height=0.6)
    # Coverage bars
    bars_cov = ax2.barh(y_pos, coverages, color=colors_hf, alpha=0.85, height=0.6)

    ax2.set_xlim(0, max(5, max(coverages) * 2))
    ax2.set_yticks(y_pos)
    ax2.set_yticklabels(labels, fontsize=10, color=text_color)
    ax2.set_xlabel("Coverage (%)", color=text_color, fontsize=11)
    ax2.set_title("Coverage Percentage", color="white", fontsize=13, fontweight="bold", pad=12)
    ax2.tick_params(colors=text_color)
    ax2.grid(axis="x", color=grid_color, alpha=0.5)
    for spine in ax2.spines.values():
        spine.set_color(grid_color)

    for i, (bar, pct) in enumerate(zip(bars_cov, coverages)):
        ax2.text(bar.get_width() + 0.1, bar.get_y() + bar.get_height() / 2,
                 f"{pct:.2f}%", va="center", fontsize=11, fontweight="bold", color=colors_hf)

    # ── Chart 3: Gap waterfall ───────────────────────────────────────────────
    ax3 = fig.add_subplot(2, 2, 3, facecolor=bg_color)
    gaps = [s["gap"] for s in sources]
    bar_colors = ["#f0883e" if g > 10000 else "#d29922" if g > 5000 else "#3fb950" for g in gaps]

    bars_gap = ax3.bar(labels, gaps, color=bar_colors, alpha=0.85, width=0.6)
    ax3.set_ylabel("Missing records", color=text_color, fontsize=11)
    ax3.set_title("Gap: Records Missing from HF Dataset", color="white", fontsize=13, fontweight="bold", pad=12)
    ax3.tick_params(colors=text_color)
    ax3.set_xticks(range(len(labels)))
    ax3.set_xticklabels(labels, fontsize=9, color=text_color, rotation=15, ha="right")
    ax3.yaxis.set_major_formatter(ticker.FuncFormatter(lambda val, _: f"{val:,.0f}"))
    ax3.grid(axis="y", color=grid_color, alpha=0.5)
    for spine in ax3.spines.values():
        spine.set_color(grid_color)

    for bar in bars_gap:
        h = bar.get_height()
        ax3.text(bar.get_x() + bar.get_width() / 2, h + 500, f"{h:,}", ha="center", va="bottom", fontsize=9, color=text_color)

    # ── Chart 4: Code articles breakdown (top 14 codes) ─────────────────────
    ax4 = fig.add_subplot(2, 2, 4, facecolor=bg_color)
    codes_data = GROUND_TRUTH["code_articles"]["codes"]
    code_names = list(codes_data.keys())
    code_gts = [v["ground_truth"] for v in codes_data.values()]

    # Sort by size descending
    sorted_idx = np.argsort(code_gts)[::-1]
    code_names_sorted = [code_names[i] for i in sorted_idx]
    code_gts_sorted = [code_gts[i] for i in sorted_idx]

    y_pos_codes = np.arange(len(code_names_sorted))
    code_colors = plt.cm.Blues(np.linspace(0.4, 0.9, len(code_names_sorted)))

    ax4.barh(y_pos_codes, code_gts_sorted, color=code_colors, alpha=0.85, height=0.7)
    ax4.set_yticks(y_pos_codes)
    ax4.set_yticklabels(code_names_sorted, fontsize=7.5, color=text_color)
    ax4.set_xlabel("Articles en vigueur", color=text_color, fontsize=11)
    ax4.set_title("Code Articles Ground Truth (14 codes)", color="white", fontsize=13, fontweight="bold", pad=12)
    ax4.tick_params(colors=text_color)
    ax4.xaxis.set_major_formatter(ticker.FuncFormatter(lambda val, _: f"{val:,.0f}"))
    ax4.grid(axis="x", color=grid_color, alpha=0.5)
    ax4.invert_yaxis()
    for spine in ax4.spines.values():
        spine.set_color(grid_color)

    for i, v in enumerate(code_gts_sorted):
        ax4.text(v + 100, i, f"{v:,}", va="center", fontsize=8, color=text_color)

    # ── Annotations ──────────────────────────────────────────────────────────
    total = stats["_total"]
    fig.text(
        0.5, 0.02,
        f"Total: {total['hf_rows']:,} / {total['ground_truth']:,} records "
        f"({total['coverage_pct']:.2f}% coverage) — "
        f"Gap: {total['gap']:,} records missing",
        ha="center", fontsize=12, color="#f97583", fontweight="bold",
    )

    plt.tight_layout(rect=[0, 0.04, 1, 0.92])

    out_path = os.path.join(os.path.dirname(__file__), "..", "docs", "coverage_report.png")
    out_path = os.path.normpath(out_path)
    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"Chart saved to {out_path}")
    return out_path


def generate_markdown(stats):
    """Generate a GitHub-publishable markdown report."""
    total = stats["_total"]
    lines = [
        f"# Dataset Coverage Report",
        f"",
        f"> **Generated**: {REPORT_DATE}  ",
        f"> **Dataset**: [`ArthurSrz/open_codes`](https://huggingface.co/datasets/ArthurSrz/open_codes)  ",
        f"> **Overall coverage**: **{total['coverage_pct']:.2f}%** ({total['hf_rows']:,} / {total['ground_truth']:,} records)",
        f"",
        f"![Coverage Report](coverage_report.png)",
        f"",
        f"## Summary",
        f"",
        f"| Source | HF Dataset | Ground Truth | Coverage | Gap |",
        f"|--------|-----------|-------------|----------|-----|",
    ]

    for key, s in stats.items():
        if key == "_total":
            continue
        gt_src = GROUND_TRUTH[key].get("ground_truth_source", "")
        lines.append(
            f"| {GROUND_TRUTH[key]['emoji']} {s['label']} | "
            f"**{s['hf_rows']:,}** | "
            f"{s['ground_truth']:,} | "
            f"**{s['coverage_pct']:.2f}%** | "
            f"{s['gap']:,} |"
        )

    lines.append(
        f"| **TOTAL** | **{total['hf_rows']:,}** | "
        f"**{total['ground_truth']:,}** | "
        f"**{total['coverage_pct']:.2f}%** | "
        f"**{total['gap']:,}** |"
    )

    lines += [
        f"",
        f"## Code Articles Breakdown (14 codes)",
        f"",
        f"| Code | Ground Truth (articles en vigueur) | Source |",
        f"|------|-----------------------------------|--------|",
    ]
    for name, data in sorted(
        GROUND_TRUTH["code_articles"]["codes"].items(),
        key=lambda x: x[1]["ground_truth"],
        reverse=True,
    ):
        lines.append(f"| {name} | {data['ground_truth']:,} | `{data['textId']}` |")

    lines.append(f"| **Total** | **{GROUND_TRUTH['code_articles']['ground_truth']:,}** | |")

    lines += [
        f"",
        f"## Analysis",
        f"",
        f"### Data Loss Layers",
        f"",
        f"The coverage gap occurs at multiple stages:",
        f"",
        f"1. **Source APIs → Xano DB** (sync pipeline): Only a fraction of available data has been ingested.",
        f"   - Code articles: ~6,381 in Xano vs ~42,943 ground truth (14.9% sync coverage)",
        f"   - Multi-source tables (jurisprudence, circulaires, réponses): backfill in progress",
        f"",
        f"2. **Xano DB → HF Dataset** (export pipeline): The export is producing even fewer rows.",
        f"   - Code articles: 200 rows exported from 6,381 in DB (3.1% export coverage)",
        f"   - This suggests the export pipeline has pagination or filtering issues",
        f"",
        f"3. **Combined effect**: End-to-end coverage is under 1% for all sources.",
        f"",
        f"### Root Causes",
        f"",
        f"| Layer | Issue | Impact |",
        f"|-------|-------|--------|",
        f"| Sync (codes) | Only 5 of 14 codes configured in LEX_codes_piste | Missing ~75% of article volume |",
        f"| Sync (multi-source) | Backfill spec 007 in progress | 3 new sources barely started |",
        f"| Export | Chunk dedup + stale filtering may be too aggressive | Rows lost between DB and HF |",
        f"| Export | Pagination may not reach all pages | Truncated data |",
        f"",
        f"### Priority Actions",
        f"",
        f"1. **Add remaining 9 codes** to `LEX_codes_piste` → biggest volume unlock (~36K articles)",
        f"2. **Complete spec 007 backfill** → fill multi-source tables from historical archives",
        f"3. **Audit export pipeline** → ensure all Xano rows make it to HF dataset",
        f"4. **Monitor nightly** → track coverage trend over time",
        f"",
        f"## Ground Truth Sources",
        f"",
        f"| Source | Reference | Date |",
        f"|--------|-----------|------|",
        f"| Code articles | PISTE manifest + vie-publique.fr statistiques normatives | Jan-Feb 2026 |",
        f"| Judilibre | Cour de cassation open data (5-year window of ~1.76M) | Mar 2026 |",
        f"| Circulaires | DILA JORF archives (all-time) | Mar 2026 |",
        f"| Réponses ministérielles | PISTE QR fond (5-year window of ~200K) | Mar 2026 |",
    ]

    out_path = os.path.join(os.path.dirname(__file__), "..", "docs", "coverage_report.md")
    out_path = os.path.normpath(out_path)
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Report saved to {out_path}")
    return out_path


def generate_json(stats):
    """Save machine-readable summary."""
    output = {
        "generated": REPORT_DATE,
        "dataset": "ArthurSrz/open_codes",
        "overall_coverage_pct": stats["_total"]["coverage_pct"],
        "total_hf_rows": stats["_total"]["hf_rows"],
        "total_ground_truth": stats["_total"]["ground_truth"],
        "total_gap": stats["_total"]["gap"],
        "sources": {
            k: {
                "hf_rows": v["hf_rows"],
                "ground_truth": v["ground_truth"],
                "coverage_pct": v["coverage_pct"],
                "gap": v["gap"],
            }
            for k, v in stats.items()
            if k != "_total"
        },
    }
    out_path = os.path.join(os.path.dirname(__file__), "..", "docs", "coverage_summary.json")
    out_path = os.path.normpath(out_path)
    with open(out_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"JSON saved to {out_path}")
    return out_path


if __name__ == "__main__":
    stats = compute_stats()
    generate_charts(stats)
    generate_markdown(stats)
    generate_json(stats)
    print(f"\nOverall: {stats['_total']['hf_rows']:,} / {stats['_total']['ground_truth']:,} "
          f"= {stats['_total']['coverage_pct']:.2f}% coverage")
