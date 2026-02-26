"""
app.py — enirtcod.fr Gradio HF Space entry point.

Startup sequence:
  1. load_all_datasets() — loads 4 FAISS indexes into RAM (~60-90s cold start)
  2. Gradio Blocks layout with search bar, source selector, filter panel,
     synthesis panel, and tabbed result cards.
"""

import os
import gradio as gr

from data_loader import load_all_datasets, embed_query, LOADING_STATUS
from search import search_all, find_related_decisions
from synthesis import synthesize
from ui_components import build_tabs_html, build_article_card

HF_TOKEN = os.environ.get("HF_TOKEN", "")

# ---------------------------------------------------------------------------
# Cold start — runs once at module import (Space startup)
# ---------------------------------------------------------------------------
print("[app] Starting dataset loading… (may take up to 90s)")
DATASETS = load_all_datasets()
print(f"[app] Loading complete. Status: {LOADING_STATUS}")

# Populate filter dropdowns dynamically from loaded datasets
_code_names = []
if DATASETS.get("articles"):
    try:
        _code_names = sorted(set(DATASETS["articles"]["code_name"]))
    except Exception:
        _code_names = []

_ministeres = []
if DATASETS.get("circulaires"):
    try:
        _ministeres = sorted(set(m for m in DATASETS["circulaires"]["ministere"] if m))
    except Exception:
        _ministeres = []


# ---------------------------------------------------------------------------
# Search handler
# ---------------------------------------------------------------------------
def run_search(query: str, source_filter: str, date_from: int, date_to: int,
               jurisdiction: str, code_name: str, ministere: str):
    # Empty query guard
    if not query.strip():
        return (
            gr.update(value="<p style='color:#9ca3af;font-style:italic'>Veuillez entrer une question juridique.</p>"),
            gr.update(value=""),
        )

    # Query length guard
    warning_note = ""
    if len(query) > 500:
        query = query[:500]
        warning_note = "\n\n⚠️ *Requête tronquée à 500 caractères.*"

    try:
        embedding = embed_query(query, HF_TOKEN)
    except ValueError as e:
        return (
            gr.update(value=f"<p style='color:#ef4444'>{e}</p>"),
            gr.update(value=""),
        )

    filters = {}
    if date_from:
        filters["date_from"] = int(date_from)
    if date_to:
        filters["date_to"] = int(date_to)
    if jurisdiction and jurisdiction != "Tous":
        filters["jurisdiction"] = jurisdiction
    if code_name and code_name != "Tous":
        filters["code_name"] = code_name
    if ministere and ministere != "Tous":
        filters["ministere"] = ministere

    results = search_all(embedding, DATASETS, source_filter=source_filter, filters=filters)

    # Cross-references: enrich article results with related decisions
    enriched_articles = []
    for r in results.get("articles", []):
        lf_id = r.get("id_legifrance", "")
        related = find_related_decisions(lf_id, DATASETS.get("jurisprudence"))
        enriched_articles.append((r, related))

    # Build synthesis
    synthesis_text = synthesize(query, results, HF_TOKEN) + warning_note

    # Build article cards with cross-references
    article_html = "".join(
        build_article_card(r, related) for r, related in enriched_articles
    )
    # Temporarily replace articles list for tab builder (pass raw results for tab counts)
    tabs_html = build_tabs_html(results, LOADING_STATUS)

    # Inject enriched article cards into the Articles tab
    if article_html and enriched_articles:
        plain_article_html = "".join(build_article_card(r) for r, _ in enriched_articles)
        tabs_html = tabs_html.replace(plain_article_html, article_html)

    synthesis_html = f"""
    <div style="font-family:system-ui,sans-serif;background:#f8fafc;border-radius:8px;
                padding:16px 20px;border-left:4px solid #2563eb;margin-bottom:16px">
      <p style="font-size:13px;font-weight:700;color:#2563eb;margin:0 0 10px">Synthèse juridique</p>
      <div style="font-size:14px;line-height:1.7;color:#1e293b;white-space:pre-wrap">{synthesis_text}</div>
    </div>"""

    return gr.update(value=synthesis_html), gr.update(value=tabs_html)


# ---------------------------------------------------------------------------
# Gradio layout
# ---------------------------------------------------------------------------
LOADING_MSG = "Chargement des sources juridiques… (peut prendre jusqu'à 90 secondes)" \
    if not all(LOADING_STATUS.values()) else ""

with gr.Blocks(
    title="enirtcod.fr — Recherche juridique française",
    css="""
    .gradio-container { max-width: 1100px !important; }
    footer { display: none !important; }
    """,
) as demo:

    gr.HTML("""
    <div style="text-align:center;padding:24px 0 12px;font-family:system-ui,sans-serif">
      <h1 style="font-size:28px;font-weight:800;color:#1e293b;margin:0">⚖️ enirtcod.fr</h1>
      <p style="color:#64748b;font-size:14px;margin:6px 0 0">
        Alternative open-source à Doctrine.fr · Recherche dans 4 sources juridiques françaises
      </p>
    </div>""")

    if LOADING_MSG:
        gr.HTML(f"""
        <div style="background:#fef3c7;border:1px solid #f59e0b;border-radius:8px;
                    padding:10px 16px;font-size:13px;color:#92400e;text-align:center">
          ⏳ {LOADING_MSG}
        </div>""")

    with gr.Row():
        query_box = gr.Textbox(
            placeholder="Ex : Quelles sont les conditions de la responsabilité civile délictuelle ?",
            label="Question juridique",
            lines=2,
            scale=5,
        )
        source_selector = gr.Dropdown(
            choices=["Tous", "Articles", "Jurisprudence", "Circulaires", "Q&R"],
            value="Tous",
            label="Source",
            scale=1,
        )

    search_btn = gr.Button("🔍 Rechercher", variant="primary")

    with gr.Accordion("Filtres avancés", open=False):
        with gr.Row():
            date_from = gr.Slider(minimum=2000, maximum=2026, step=1, value=2000, label="Année depuis")
            date_to   = gr.Slider(minimum=2000, maximum=2026, step=1, value=2026, label="Année jusqu'à")
        with gr.Row():
            juris_filter = gr.Dropdown(
                choices=["Tous", "Cour de cassation", "Cour d'appel"],
                value="Tous",
                label="Juridiction",
            )
            code_filter = gr.Dropdown(
                choices=["Tous"] + _code_names,
                value="Tous",
                label="Code juridique",
            )
            min_filter = gr.Dropdown(
                choices=["Tous"] + _ministeres,
                value="Tous",
                label="Ministère",
            )

    synthesis_out = gr.HTML(label="Synthèse")
    results_out   = gr.HTML(label="Résultats")

    search_btn.click(
        fn=run_search,
        inputs=[query_box, source_selector, date_from, date_to,
                juris_filter, code_filter, min_filter],
        outputs=[synthesis_out, results_out],
    )

    query_box.submit(
        fn=run_search,
        inputs=[query_box, source_selector, date_from, date_to,
                juris_filter, code_filter, min_filter],
        outputs=[synthesis_out, results_out],
    )

if __name__ == "__main__":
    demo.launch()
