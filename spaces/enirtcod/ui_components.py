"""
ui_components.py — HTML card builders for each legal source type + tab panel.
"""


def build_article_card(result: dict, related_decisions: list[dict] | None = None) -> str:
    code   = result.get("code_name", "Code")
    num    = result.get("num", result.get("id_legifrance", ""))
    snippet = (result.get("chunk_text") or "")[:200]
    date   = (result.get("article_dateDebut") or "")[:10]
    lf_id  = result.get("id_legifrance", "")
    url    = f"https://www.legifrance.gouv.fr/codes/article_lc/{lf_id}" if lf_id else "#"
    etat   = result.get("article_etat", "")

    etat_badge = f'<span style="font-size:11px;color:#6b7280;margin-left:6px">{etat}</span>' if etat else ""

    cross_ref_html = ""
    if related_decisions:
        mini_cards = ""
        for dec in related_decisions:
            dec_url  = dec.get("url_judilibre", "#")
            dec_date = dec.get("date_decision", "")
            dec_jur  = dec.get("jurisdiction", "")
            dec_snip = dec.get("chunk_text", "")[:120]
            mini_cards += f"""
            <div style="border-left:3px solid #6366f1;padding:6px 10px;margin-top:6px;font-size:12px;color:#374151">
              <strong>{dec_jur}</strong> · {dec_date}
              <div style="color:#6b7280;margin-top:2px">{dec_snip}…</div>
              <a href="{dec_url}" target="_blank" style="color:#6366f1;font-size:11px">→ Cour de cassation</a>
            </div>"""
        n = len(related_decisions)
        cross_ref_html = f"""
        <details style="margin-top:8px">
          <summary style="cursor:pointer;color:#6366f1;font-size:13px;font-weight:600">
            Voir les décisions ({n})
          </summary>
          {mini_cards}
        </details>"""

    return f"""
    <div data-article-id="{lf_id}" style="border:1px solid #e5e7eb;border-radius:8px;padding:12px 16px;margin-bottom:10px;background:#fff">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
        <span style="background:#dbeafe;color:#1d4ed8;font-size:11px;font-weight:700;padding:2px 8px;border-radius:12px">{code}</span>
        <strong style="font-size:14px">Art. {num}</strong>{etat_badge}
      </div>
      <p style="font-size:13px;color:#374151;margin:0 0 8px">{snippet}…</p>
      <div style="font-size:12px;color:#9ca3af">
        📅 {date} &nbsp;|&nbsp;
        <a href="{url}" target="_blank" style="color:#2563eb">🔗 Légifrance</a>
      </div>
      {cross_ref_html}
    </div>"""


def build_decision_card(result: dict) -> str:
    juris   = result.get("jurisdiction", "")
    chamber = result.get("chamber", "")
    date    = result.get("date_decision", "")
    fiche   = result.get("fiche_arret") or ""
    snippet = fiche[:200] if fiche else (result.get("chunk_text") or "")[:200]
    url     = result.get("url_judilibre", "#")
    src_id  = result.get("source_id", "")

    badge_label = f"{juris}" + (f" | {chamber}" if chamber else "")

    return f"""
    <div style="border:1px solid #e5e7eb;border-radius:8px;padding:12px 16px;margin-bottom:10px;background:#fff">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
        <span style="background:#fce7f3;color:#be185d;font-size:11px;font-weight:700;padding:2px 8px;border-radius:12px">{badge_label}</span>
        <strong style="font-size:13px">{date}</strong>
        {f'<span style="font-size:11px;color:#6b7280">n° {src_id}</span>' if src_id else ""}
      </div>
      <p style="font-size:13px;color:#374151;margin:0 0 8px">{snippet}…</p>
      <div style="font-size:12px;color:#9ca3af">
        📅 {date} &nbsp;|&nbsp;
        <a href="{url}" target="_blank" style="color:#2563eb">🔗 Cour de cassation</a>
      </div>
    </div>"""


def build_circulaire_card(result: dict) -> str:
    ministere = result.get("ministere", "")
    numero    = result.get("numero", result.get("source_id", ""))
    objet     = (result.get("objet") or result.get("chunk_text") or "")[:200]
    date      = (result.get("date_parution") or "")[:10]
    url       = result.get("url_legifrance", "#")

    return f"""
    <div style="border:1px solid #e5e7eb;border-radius:8px;padding:12px 16px;margin-bottom:10px;background:#fff">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
        <span style="background:#d1fae5;color:#065f46;font-size:11px;font-weight:700;padding:2px 8px;border-radius:12px">Ministère : {ministere}</span>
        <strong style="font-size:13px">Circ. n° {numero}</strong>
      </div>
      <p style="font-size:13px;color:#374151;margin:0 0 8px">{objet}…</p>
      <div style="font-size:12px;color:#9ca3af">
        📅 {date} &nbsp;|&nbsp;
        <a href="{url}" target="_blank" style="color:#2563eb">🔗 Légifrance</a>
      </div>
    </div>"""


def build_reponse_card(result: dict) -> str:
    ministere = result.get("ministere", "")
    num_q     = result.get("numero_question", result.get("source_id", ""))
    question  = (result.get("question_text") or result.get("chunk_text") or "")[:200]
    date      = (result.get("date_reponse") or "")[:10]
    url       = result.get("url_legifrance", "#")

    return f"""
    <div style="border:1px solid #e5e7eb;border-radius:8px;padding:12px 16px;margin-bottom:10px;background:#fff">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
        <span style="background:#fef3c7;color:#92400e;font-size:11px;font-weight:700;padding:2px 8px;border-radius:12px">{ministere}</span>
        <strong style="font-size:13px">Q. n° {num_q}</strong>
      </div>
      <p style="font-size:13px;color:#374151;margin:0 0 8px">{question}…</p>
      <div style="font-size:12px;color:#9ca3af">
        📅 {date} &nbsp;|&nbsp;
        <a href="{url}" target="_blank" style="color:#2563eb">🔗 Légifrance</a>
      </div>
    </div>"""


def build_tabs_html(results_dict: dict, loading_status: dict) -> str:
    """
    Build a 4-tab HTML panel. Each tab shows its source count in the label.
    If a source failed to load, shows 'Source temporairement indisponible'.
    """
    tabs_config = [
        ("articles",      "Articles",      build_article_card),
        ("jurisprudence", "Jurisprudence", build_decision_card),
        ("circulaires",   "Circulaires",   build_circulaire_card),
        ("reponses",      "Q&R",           build_reponse_card),
    ]

    tab_buttons = ""
    tab_panels  = ""

    for i, (key, label, builder) in enumerate(tabs_config):
        results = results_dict.get(key, [])
        count   = len(results)
        active  = "active" if i == 0 else ""

        tab_buttons += f"""
        <button onclick="showTab('{key}')" id="tab-btn-{key}"
          style="padding:8px 16px;border:none;background:{'#eff6ff' if i==0 else 'transparent'};
                 color:{'#1d4ed8' if i==0 else '#6b7280'};font-weight:{'700' if i==0 else '400'};
                 border-bottom:{'2px solid #1d4ed8' if i==0 else '2px solid transparent'};
                 cursor:pointer;font-size:14px;border-radius:4px 4px 0 0">
          {label} ({count})
        </button>"""

        if not loading_status.get(key, False):
            content = '<p style="color:#9ca3af;font-style:italic;padding:20px">Source temporairement indisponible</p>'
        elif not results:
            content = '<p style="color:#9ca3af;font-style:italic;padding:20px">Aucun résultat pour cette source.</p>'
        else:
            content = "".join(builder(r) for r in results)

        display = "block" if i == 0 else "none"
        tab_panels += f"""
        <div id="tab-{key}" style="display:{display};padding:16px 0">
          {content}
        </div>"""

    js = """
    <script>
    function showTab(key) {
      ['articles','jurisprudence','circulaires','reponses'].forEach(k => {
        document.getElementById('tab-' + k).style.display = (k === key) ? 'block' : 'none';
        var btn = document.getElementById('tab-btn-' + k);
        btn.style.background    = (k === key) ? '#eff6ff' : 'transparent';
        btn.style.color         = (k === key) ? '#1d4ed8' : '#6b7280';
        btn.style.fontWeight    = (k === key) ? '700' : '400';
        btn.style.borderBottom  = (k === key) ? '2px solid #1d4ed8' : '2px solid transparent';
      });
    }
    </script>"""

    return f"""
    <div style="font-family:system-ui,sans-serif">
      <div style="border-bottom:1px solid #e5e7eb;display:flex;gap:4px">
        {tab_buttons}
      </div>
      {tab_panels}
      {js}
    </div>"""
