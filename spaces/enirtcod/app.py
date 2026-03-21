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
# Logo — base64 inline (Gradio 5.x doesn't serve file/ paths reliably)
# ---------------------------------------------------------------------------
_logo_b64 = ""
_logo_path = os.path.join(os.path.dirname(__file__), "logo_b64.txt")
if os.path.exists(_logo_path):
    with open(_logo_path) as f:
        _logo_b64 = f.read().strip()

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
    if not query.strip():
        return (
            gr.update(value='<p style="color:#94a3b8;font-style:italic;padding:12px 0">Veuillez entrer une question juridique.</p>'),
            gr.update(value=""),
        )

    warning_note = ""
    if len(query) > 500:
        query = query[:500]
        warning_note = "\n\n*Requete tronquee a 500 caracteres.*"

    try:
        embedding = embed_query(query, HF_TOKEN)
    except ValueError as e:
        return (
            gr.update(value=f'<p style="color:#dc2626;padding:12px 0">{e}</p>'),
            gr.update(value=""),
        )

    filters = {}
    if date_from and int(date_from) > 2000:
        filters["date_from"] = int(date_from)
    if date_to and int(date_to) < 2026:
        filters["date_to"] = int(date_to)
    if jurisdiction and jurisdiction != "Tous":
        filters["jurisdiction"] = jurisdiction
    if code_name and code_name != "Tous":
        filters["code_name"] = code_name
    if ministere and ministere != "Tous":
        filters["ministere"] = ministere

    results = search_all(embedding, DATASETS, source_filter=source_filter, filters=filters)

    enriched_articles = []
    for r in results.get("articles", []):
        lf_id = r.get("id_legifrance", "")
        related = find_related_decisions(lf_id, DATASETS.get("jurisprudence"))
        enriched_articles.append((r, related))

    synthesis_text = synthesize(query, results, HF_TOKEN) + warning_note

    article_html = "".join(
        build_article_card(r, related) for r, related in enriched_articles
    )
    tabs_html = build_tabs_html(results, LOADING_STATUS)

    if article_html and enriched_articles:
        plain_article_html = "".join(build_article_card(r) for r, _ in enriched_articles)
        tabs_html = tabs_html.replace(plain_article_html, article_html)

    synthesis_html = f"""
    <div style="background:#ffffff;border-radius:12px;padding:20px 24px;
                border:1px solid #e2e8f0;box-shadow:0 1px 3px rgba(0,0,0,0.04);margin-bottom:20px">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px">
        <div style="width:4px;height:22px;background:#0f172a;border-radius:2px"></div>
        <p style="font-size:15px;font-weight:700;color:#0f172a;margin:0;letter-spacing:-0.2px">Synthese juridique</p>
      </div>
      <div style="font-size:14px;line-height:1.75;color:#334155;white-space:pre-wrap">{synthesis_text}</div>
    </div>"""

    return gr.update(value=synthesis_html), gr.update(value=tabs_html)


# ---------------------------------------------------------------------------
# Theme & CSS — Doctrine.fr-inspired design
# ---------------------------------------------------------------------------
CUSTOM_CSS = """
/* ── Global theme overrides ── */
:root {
  --color-accent: #0f172a !important;
  --color-accent-soft: #dbeafe !important;
  --button-primary-background-fill: #0f172a !important;
  --button-primary-background-fill-hover: #1e293b !important;
  --button-primary-text-color: #ffffff !important;
  --block-border-color: #cbd5e1 !important;
  --block-background-fill: #ffffff !important;
  --body-background-fill: #f1f5f9 !important;
  --input-background-fill: #ffffff !important;
  --block-label-text-color: #334155 !important;
  --slider-color: #0f172a !important;
}

.gradio-container {
  max-width: 100% !important;
  margin: 0 auto !important;
  width: 100% !important;
  padding: 0 48px !important;
  box-sizing: border-box !important;
  background: #f1f5f9 !important;
}

/* ── Typography ── */
.gradio-container, .gradio-container * {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif !important;
}

/* ── Search input ── */
.gradio-container textarea {
  border: 2px solid #94a3b8 !important;
  border-radius: 10px !important;
  font-size: 16px !important;
  padding: 14px 18px !important;
  transition: border-color 0.2s, box-shadow 0.2s !important;
  background: #ffffff !important;
}
.gradio-container textarea:focus {
  border-color: #0f172a !important;
  box-shadow: 0 0 0 3px rgba(15, 23, 42, 0.12) !important;
  outline: none !important;
}

/* ── Primary button ── */
.gradio-container button.primary {
  background: #0f172a !important;
  border: none !important;
  border-radius: 10px !important;
  font-weight: 700 !important;
  font-size: 16px !important;
  padding: 14px 32px !important;
  letter-spacing: 0.3px !important;
  transition: background 0.2s, transform 0.1s, box-shadow 0.2s !important;
  box-shadow: 0 2px 8px rgba(15, 23, 42, 0.2) !important;
}
.gradio-container button.primary:hover {
  background: #1e293b !important;
  transform: translateY(-1px) !important;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.3) !important;
}

/* ── Dropdowns ── */
.gradio-container select,
.gradio-container .wrap input {
  border: 2px solid #94a3b8 !important;
  border-radius: 8px !important;
  font-size: 14px !important;
  font-weight: 500 !important;
}

/* ── Slider: override orange track ── */
.gradio-container input[type="range"] {
  accent-color: #0f172a !important;
}
.gradio-container .range-slider {
  accent-color: #0f172a !important;
}

/* ── Accordion ── */
.gradio-container .accordion {
  border: 2px solid #cbd5e1 !important;
  border-radius: 10px !important;
  background: #ffffff !important;
}
.gradio-container .accordion summary {
  font-weight: 600 !important;
  color: #1e293b !important;
}

/* ── Block panels ── */
.gradio-container .block {
  border-radius: 10px !important;
  border: 1px solid #cbd5e1 !important;
  box-shadow: 0 1px 2px rgba(0,0,0,0.03) !important;
}

/* ── Hide footer ── */
footer { display: none !important; }

/* ── Responsive ── */
@media (max-width: 768px) {
  .gradio-container { max-width: 100% !important; padding: 0 12px !important; }
}
"""

# ---------------------------------------------------------------------------
# Gradio layout
# ---------------------------------------------------------------------------
theme = gr.themes.Soft(
    primary_hue=gr.themes.colors.blue,
    secondary_hue=gr.themes.colors.slate,
    neutral_hue=gr.themes.colors.slate,
    font=gr.themes.GoogleFont("Inter"),
)

with gr.Blocks(title="enirtcod.fr — Recherche juridique francaise", css=CUSTOM_CSS, theme=theme) as demo:

    # ── Header ──
    _logo_html = (
        f'<img src="data:image/png;base64,{_logo_b64}" alt="enirtcod logo"'
        ' style="width:56px;height:56px;object-fit:contain;flex-shrink:0">'
        if _logo_b64 else ""
    )
    gr.HTML(f"""
    <div style="display:flex;align-items:center;gap:16px;padding:24px 0 8px">
      {_logo_html}
      <div>
        <h1 style="font-size:36px;font-weight:800;color:#0f172a;margin:0;letter-spacing:-0.8px">
          enirtcod<span style="color:#1d4ed8">.fr</span>
        </h1>
        <p style="color:#475569;font-size:15px;margin:4px 0 0;font-weight:500">
          Recherchez dans les codes, la jurisprudence et les circulaires
        </p>
      </div>
    </div>""")

    # ── Search bar ──
    gr.HTML('<div style="height:8px"></div>')

    query_box = gr.Textbox(
        placeholder="Posez votre question : responsabilite civile, article 1240, licenciement abusif…",
        label="",
        lines=1,
        show_label=False,
    )

    search_btn = gr.Button("Rechercher", variant="primary", size="lg")

    # ── Example queries ──
    gr.HTML("""
    <div style="display:flex;gap:8px;flex-wrap:wrap;padding:4px 0 8px">
      <span style="background:#f1f5f9;border:1px solid #cbd5e1;border-radius:16px;padding:4px 14px;font-size:13px;color:#475569;cursor:default">droit de retractation achat en ligne</span>
      <span style="background:#f1f5f9;border:1px solid #cbd5e1;border-radius:16px;padding:4px 14px;font-size:13px;color:#475569;cursor:default">obligation de securite employeur</span>
      <span style="background:#f1f5f9;border:1px solid #cbd5e1;border-radius:16px;padding:4px 14px;font-size:13px;color:#475569;cursor:default">article L1232-1 code du travail</span>
      <span style="background:#f1f5f9;border:1px solid #cbd5e1;border-radius:16px;padding:4px 14px;font-size:13px;color:#475569;cursor:default">vice cache immobilier</span>
    </div>""")

    # ── Filters ──
    with gr.Accordion("Affiner la recherche", open=False):
        source_selector = gr.Dropdown(
            choices=["Tous", "Articles", "Jurisprudence", "Circulaires", "Q&R"],
            value="Tous",
            label="Source",
        )
        with gr.Row():
            date_from = gr.Slider(minimum=2000, maximum=2026, step=1, value=2000, label="Depuis")
            date_to   = gr.Slider(minimum=2000, maximum=2026, step=1, value=2026, label="Jusqu'a")
        with gr.Row():
            juris_filter = gr.Dropdown(
                choices=["Tous", "Cour de cassation", "Cour d'appel"],
                value="Tous",
                label="Tribunal",
            )
            code_filter = gr.Dropdown(
                choices=["Tous"] + _code_names,
                value="Tous",
                label="Code juridique",
            )
            min_filter = gr.Dropdown(
                choices=["Tous"] + _ministeres,
                value="Tous",
                label="Ministere",
            )

    # ── Results ──
    gr.HTML('<div style="height:8px"></div>')
    synthesis_out = gr.HTML(label="Synthese")
    results_out   = gr.HTML(label="Resultats")

    # ── Event handlers ──
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
