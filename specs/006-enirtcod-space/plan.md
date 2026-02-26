# Implementation Plan: enirtcod.fr Open Legal Search Space

**Feature Branch**: `006-enirtcod-space`
**Created**: 2026-02-25
**Spec**: [spec.md](spec.md)

## Tech Stack

- **UI Framework**: Gradio 4.x (Python)
- **Semantic search**: FAISS (via HuggingFace `datasets` built-in `add_faiss_index`)
- **Dataset**: `ArthurSrz/open_codes` (4 configs: default, jurisprudence, circulaires, reponses_legis)
- **Embeddings**: Mistral AI `mistral-embed` (1024-dim) via HuggingFace Inference API
- **LLM synthesis**: `mistralai/Mistral-7B-Instruct-v0.3` via HuggingFace Inference API
- **Deployment**: HuggingFace Spaces (free tier, 16GB RAM)
- **Domain**: enirtcod.fr (custom domain on HF Space)

## Project Structure

```
spaces/enirtcod/
├── app.py              # Main Gradio app
├── search.py           # FAISS retrieval logic (4-way search)
├── synthesis.py        # LLM synthesis + citation formatting
├── ui_components.py    # Gradio component builders (cards, tabs, filters)
├── data_loader.py      # Dataset loading + FAISS index construction
├── requirements.txt    # gradio>=4.0, datasets, huggingface_hub, mistralai, faiss-cpu
└── README.md           # HF Space card (license: apache-2.0)
```

## Architecture

```
User query (French)
    │
    ├─[1] Embed: HF Inference → mistral-embed → 1024-dim vector
    │
    ├─[2] FAISS on open_codes/default        → top-3 article chunks
    ├─[3] FAISS on open_codes/jurisprudence  → top-3 decision chunks
    ├─[4] FAISS on open_codes/circulaires    → top-2 circulaire chunks
    ├─[5] FAISS on open_codes/reponses_legis → top-1 réponse chunk
    │      └─ each filtered by date/jurisdiction/code/ministry if active
    │
    └─[6] Mistral 7B Instruct via HF Inference API
          System prompt: cite [Code, art.] + [Cass. date, n°] style only from context
          → Prose synthesis with structured citations
```

## Startup Sequence (data_loader.py)

```python
# At Space startup (runs once, ~60-90s):
articles_ds = load_dataset("ArthurSrz/open_codes", name="default", split="train")
juris_ds    = load_dataset("ArthurSrz/open_codes", name="jurisprudence", split="train")
circ_ds     = load_dataset("ArthurSrz/open_codes", name="circulaires", split="train")
rep_ds      = load_dataset("ArthurSrz/open_codes", name="reponses_legis", split="train")

for ds in [articles_ds, juris_ds, circ_ds, rep_ds]:
    ds.add_faiss_index(column="embedding")
```

If any dataset fails to load, the other three continue (graceful degradation).

## Search Logic (search.py)

```python
def search_all(query_embedding, k_per_source=3, filters=None):
    results = {
        "articles":      search_with_filters(articles_ds, query_embedding, k=3, filters),
        "jurisprudence": search_with_filters(juris_ds,    query_embedding, k=3, filters),
        "circulaires":   search_with_filters(circ_ds,     query_embedding, k=2, filters),
        "reponses":      search_with_filters(rep_ds,      query_embedding, k=1, filters),
    }
    return results

def search_with_filters(ds, query_emb, k, filters):
    scores, indices = ds.get_nearest_examples("embedding", query_emb, k=k*10)
    results = [ds[i] for i in indices]
    # Apply post-retrieval filters (date_range, jurisdiction, code, ministry)
    if filters.get("date_from"): results = [r for r in results if r["date"] >= filters["date_from"]]
    if filters.get("jurisdiction"): results = [r for r in results if r.get("jurisdiction") == filters["jurisdiction"]]
    return results[:k]
```

## Synthesis Logic (synthesis.py)

```python
SYSTEM_PROMPT = """Tu es un assistant juridique français. Réponds à la question en te basant
UNIQUEMENT sur les extraits fournis. Cite chaque source en style juridique français :
- Articles : [Code civil, art. 1240] ou [C. trav., art. L.1237-19]
- Décisions : [Cass. 1re civ., 13 avr. 2023, n° 21-20.145]
- Circulaires : [Circ. n° 2023-123, ministère XY]
Si tu ne trouves pas de réponse dans les extraits, réponds : "Aucun résultat pertinent trouvé."
"""

def synthesize(query, retrieved_chunks):
    context = format_chunks_as_context(retrieved_chunks)
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"Question: {query}\n\nExtraits:\n{context}"}
    ]
    return hf_inference_client.chat_completion(model="mistralai/Mistral-7B-Instruct-v0.3", messages=messages)
```

## Result Card Format

### Article card
```
[badge: Code civil] Art. 1240 — De tout fait quelconque de l'homme...
📅 En vigueur depuis 01/01/2016 | 🔗 Legifrance
[Voir les décisions (N)] (if N > 0)
```

### Decision card
```
[badge: Cour de cassation | 1re chambre civile] 13 avril 2023 · n° 21-20.145
La cour a jugé que... [fiche d'arrêt snippet]
📅 2023-04-13 | 🔗 Cour de cassation
```

### Circulaire card
```
[badge: Ministère du travail] Circ. n° 2023-045 — Objet: Application de...
📅 15 mars 2023 | 🔗 Legifrance
```

### Q&R card
```
[badge: Ministère de la justice] Q. n° 12345 — Comment interpréter...
[snippet of reponse_text] 📅 2022-11-22 | 🔗 Legifrance
```

## UI Layout (Gradio)

```
┌─────────────────────────────────────────────────────┐
│  🔍 enirtcod.fr   [search bar        ] [Rechercher] │
│     Source: [Tous ▼]                                │
├────────────┬────────────────────────────────────────┤
│  FILTRES   │  Synthèse ──────────────────────────── │
│  Date: ... │  [LLM prose answer with citations]     │
│  Juridic.. │                                        │
│  Code: ... │  Résultats ────────────────────────── │
│  Ministère │  Articles (N) | Jurisprudence (N) |    │
│            │  Circulaires (N) | Q&R (N)             │
│            │  ┌──────────────────────────────────┐ │
│            │  │ [Result Card]                    │ │
│            │  │ [Result Card]                    │ │
│            │  └──────────────────────────────────┘ │
└────────────┴────────────────────────────────────────┘
```

## Cross-Reference Logic

```python
def find_related_decisions(article_id_legifrance):
    # Simple string match: find decision chunks containing the article ID
    related = [row for row in juris_ds if article_id_legifrance in row["chunk_text"]]
    return related[:3]  # top 3 only
```

## HF Space Configuration (README.md YAML header)

```yaml
---
title: enirtcod
emoji: ⚖️
colorFrom: blue
colorTo: indigo
sdk: gradio
sdk_version: "4.44.0"
app_file: app.py
pinned: true
license: apache-2.0
---
```

## Requirements (requirements.txt)

```
gradio>=4.44.0
datasets>=2.14.0
huggingface_hub>=0.20.0
faiss-cpu>=1.7.4
mistralai>=1.0.0
numpy>=1.24.0
```

## Key Files

| File | Purpose |
|------|---------|
| `spaces/enirtcod/app.py` | Gradio app entry point, layout, event handlers |
| `spaces/enirtcod/data_loader.py` | Dataset loading + FAISS index construction |
| `spaces/enirtcod/search.py` | FAISS retrieval with post-retrieval filters |
| `spaces/enirtcod/synthesis.py` | LLM synthesis + citation formatter |
| `spaces/enirtcod/ui_components.py` | Gradio card builders per source type |
| `spaces/enirtcod/requirements.txt` | Python dependencies |
| `spaces/enirtcod/README.md` | HF Space card with YAML metadata |
