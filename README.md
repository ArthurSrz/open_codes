<p align="center">
  <img src="docs/banner.webp" alt="Open Codes banner" width="100%">
</p>

<h1 align="center">Open Codes</h1>

<p align="center">
An open dataset of French legal texts with semantic embeddings, updated daily from 4 official sources.
</p>

<p align="center">
  <a href="https://huggingface.co/datasets/ArthurSrz/open_codes">HuggingFace Dataset</a> &bull;
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#how-it-works">Architecture</a> &bull;
  <a href="#license">License</a>
</p>

---

## What is Open Codes?

Open Codes provides **chunked, embedded French legal texts** from 4 official sources, updated daily and ready for RAG pipelines, legal research, and NLP experimentation.

Each row in the dataset is a text chunk enriched with:
- **1024-dim embeddings** from Mistral AI (`mistral-embed`)
- Full metadata from official sources (dates, hierarchy, status, identifiers...)
- Human-readable labels and section paths

### Sources updated daily

| Source | Description | Dataset config | Volume |
|--------|-------------|----------------|--------|
| **Codes** | 5 major legal codes from Legifrance | `default` | ~26K chunks |
| **Decisions de justice** | Court decisions from Judilibre | `jurisprudence` | ~82K decisions |
| **Circulaires** | Government circulars | `circulaires` | ~10K circulaires |
| **Questions & Réponses** | Parliamentary Q&A (réponses ministérielles) | `reponses_legis` | ~40K réponses |

### Legal codes included (default config)

| Code | Domain |
|------|--------|
| Code civil | Core private law |
| Code de l'urbanisme | Urban planning |
| Code electoral | Electoral law |
| Code general des collectivites territoriales | Local government |
| Code des communes | Municipal law |

## Quick Start

```python
from datasets import load_dataset

# Load code articles (default config)
codes = load_dataset("ArthurSrz/open_codes", split="train")

# Load other sources
jurisprudence = load_dataset("ArthurSrz/open_codes", "jurisprudence", split="train")
circulaires = load_dataset("ArthurSrz/open_codes", "circulaires", split="train")
reponses = load_dataset("ArthurSrz/open_codes", "reponses_legis", split="train")

# Browse a chunk
row = codes[0]
print(row["code_name"])       # e.g. "Code civil"
print(row["chunk_text"][:200])
print(len(row["embedding"]))  # 1024

# Semantic search with embeddings
import numpy as np
query_emb = get_embedding("responsabilite civile")  # your embedding function
scores = np.dot(np.array(codes["embedding"]), query_emb)
top_k = np.argsort(scores)[-5:][::-1]
for i in top_k:
    print(f"{codes[i]['code_name']} {codes[i]['num']}: {codes[i]['chunk_text'][:100]}")
```

## How It Works

```
  Legifrance PISTE API    Judilibre API    DILA JORF Archives
        |                      |                  |
        v                      v                  v
  Xano Sync Pipeline                    (nightly at 02:00-03:30 UTC)
  [PopulateQueue]  -->  [SyncWorker]    (4 source types)
        |                      |
        v                      v
  Queue items            Fetch / Hash / Chunk / Embed
        |                      |
        v                      v
  Xano DB (9 tables)     REF_article_chunks + REF_legal_chunks
        |                      |
        +----------+-----------+
                   |
                   v
         GitHub Action                  (nightly at 07:00 UTC)
         export_to_hf.py
                   |
                   v
    HuggingFace Hub: ArthurSrz/open_codes
         (4 configs: default, jurisprudence, circulaires, reponses_legis)
```

**Pipeline stages:**
1. **PopulateQueue** — nightly tasks query each source API for new/updated items, create queue entries
2. **SyncWorker** — polls queue every 4-5s, fetches content, computes hashes, chunks text, generates Mistral embeddings
3. **GitHub Action** — merges chunks + metadata for all 4 sources, builds typed HuggingFace Datasets, pushes to Hub

## Data Schema

### Key columns

| Column | Type | Description |
|--------|------|-------------|
| `chunk_text` | string | Text content of the chunk |
| `embedding` | float32[1024] | Mistral AI embedding vector |
| `code_name` | string | Human-readable code name |
| `id_legifrance` | string | Legifrance article identifier |
| `num` | string | Article number (e.g. "L. 1234-5") |
| `etat` | string | Status: VIGUEUR (in force), ABROGE (repealed) |
| `article_texte` | string | Full article plain text |
| `article_dateDebut` | string | Effective date (Unix ms) |
| `article_fullSectionsTitre` | string | Full hierarchy path |

See the [HuggingFace dataset card](https://huggingface.co/datasets/ArthurSrz/open_codes) for the complete 50+ column schema.

## License

- **Dataset**: [Licence Ouverte / Etalab 2.0](https://www.etalab.gouv.fr/licence-ouverte-open-licence/) (French open data license)
- **Source data**: [PISTE Legifrance API](https://piste.gouv.fr/), [Judilibre API](https://www.courdecassation.fr/acces-rapide-judilibre), [DILA JORF](https://journal-officiel.gouv.fr/)
- **Embeddings**: Generated by [Mistral AI](https://mistral.ai/) (`mistral-embed`, 1024 dimensions)

## Credits

Built by the **marIAnne** project.

- Legal codes & circulaires: [PISTE / Legifrance](https://piste.gouv.fr/)
- Jurisprudence: [Judilibre / Cour de cassation](https://www.courdecassation.fr/acces-rapide-judilibre)
- Réponses ministérielles: [DILA / Journal officiel](https://journal-officiel.gouv.fr/)
- Embeddings: [Mistral AI](https://mistral.ai/)
- Backend: [Xano](https://www.xano.com/)
- Dataset hosting: [HuggingFace Hub](https://huggingface.co/)
