"""
search.py — FAISS retrieval + post-retrieval filtering across 4 legal sources.
"""

import numpy as np


def search_source(ds, query_embedding: list[float], k: int, source_type: str) -> list[dict]:
    """
    Run FAISS nearest-neighbour search on a single dataset.
    Returns top-k result dicts enriched with source_type and score.
    Fetches k*5 candidates to allow for post-filter headroom.
    """
    if ds is None:
        return []

    try:
        scores, results = ds.get_nearest_examples(
            "embedding", np.array(query_embedding, dtype=np.float32), k=k * 5
        )
    except Exception as e:
        print(f"[search] FAISS error on {source_type}: {e}")
        return []

    rows = []
    for i, score in enumerate(scores):
        row = {col: results[col][i] for col in results}
        row["source_type"] = source_type
        row["score"] = float(score)
        rows.append(row)

    return rows[:k]


def apply_filters(results: list[dict], filters: dict) -> list[dict]:
    """
    Apply post-retrieval filters. All filters are optional (None = skip).
    - date_from / date_to: int years, applied to all source types
    - jurisdiction: string, applied to jurisprudence only
    - code_name: string, applied to articles only
    - ministere: string, applied to circulaires and reponses
    """
    out = []
    for r in results:
        source = r.get("source_type", "")

        # Date filter (year-based, applied to all)
        if filters.get("date_from") or filters.get("date_to"):
            date_str = (
                r.get("article_dateDebut")
                or r.get("date_decision")
                or r.get("date_parution")
                or r.get("date_reponse")
                or ""
            )
            try:
                year = int(str(date_str)[:4])
                if filters.get("date_from") and year < filters["date_from"]:
                    continue
                if filters.get("date_to") and year > filters["date_to"]:
                    continue
            except (ValueError, TypeError):
                pass  # keep if date unparseable

        # Jurisdiction filter (jurisprudence only)
        if filters.get("jurisdiction") and source == "jurisprudence":
            if r.get("jurisdiction") != filters["jurisdiction"]:
                continue

        # Code filter (articles only)
        if filters.get("code_name") and source == "articles":
            if r.get("code_name") != filters["code_name"]:
                continue

        # Ministry filter (circulaires + reponses)
        if filters.get("ministere") and source in ("circulaires", "reponses"):
            if r.get("ministere") != filters["ministere"]:
                continue

        out.append(r)
    return out


def search_all(
    query_embedding: list[float],
    datasets_dict: dict,
    source_filter: str = "Tous",
    filters: dict | None = None,
) -> dict:
    """
    Run search across all loaded datasets.
    source_filter: "Tous" | "Articles" | "Jurisprudence" | "Circulaires" | "Q&R"
    Returns dict: {articles: [...], jurisprudence: [...], circulaires: [...], reponses: [...]}
    """
    if filters is None:
        filters = {}

    source_map = {
        "Articles":      ["articles"],
        "Jurisprudence": ["jurisprudence"],
        "Circulaires":   ["circulaires"],
        "Q&R":           ["reponses"],
    }

    active_sources = (
        source_map.get(source_filter, ["articles", "jurisprudence", "circulaires", "reponses"])
        if source_filter != "Tous"
        else ["articles", "jurisprudence", "circulaires", "reponses"]
    )

    k_map = {"articles": 3, "jurisprudence": 3, "circulaires": 2, "reponses": 1}

    result = {}
    for source in ["articles", "jurisprudence", "circulaires", "reponses"]:
        if source not in active_sources:
            result[source] = []
            continue

        raw = search_source(datasets_dict.get(source), query_embedding, k_map[source], source)
        result[source] = apply_filters(raw, filters) if filters else raw

    return result


def find_related_decisions(article_id_legifrance: str, juris_ds) -> list[dict]:
    """
    Find up to 3 jurisprudence chunks that mention a given article ID in their chunk_text.
    Simple O(N) string match — precomputed at startup if dataset is large.
    """
    if juris_ds is None or not article_id_legifrance:
        return []

    related = []
    for row in juris_ds:
        if article_id_legifrance in (row.get("chunk_text") or ""):
            related.append({
                "jurisdiction":   row.get("jurisdiction", ""),
                "date_decision":  row.get("date_decision", ""),
                "solution":       row.get("solution", ""),
                "url_judilibre":  row.get("url_judilibre", ""),
                "chunk_text":     (row.get("chunk_text") or "")[:300],
            })
            if len(related) >= 3:
                break

    return related
