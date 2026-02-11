"""
Export REF_article_chunks + REF_codes_legifrance from Xano to HuggingFace Hub.

Each row = one chunk enriched with all article metadata from REF_codes_legifrance.
Two Xano endpoints are fetched separately, then merged in Python on id_legifrance.

Usage:
    python export_to_hf.py              # Full export + push to HF Hub
    python export_to_hf.py --dry-run    # Fetch + validate only, no push

Env vars:
    XANO_BASE_URL  - Xano instance base URL (e.g. https://x123.xano.io/api:abc)
    HF_TOKEN       - HuggingFace write token (not needed for --dry-run)
"""

import argparse
import json
import os
import sys

import requests
from datasets import Dataset, Features, Sequence, Value


HF_REPO_ID = "ArthurSrz/french-legal-chunks"
CHUNKS_PER_PAGE = 500
ARTICLES_PER_PAGE = 200


def check_sync_status(base_url: str) -> bool:
    """Return True if sync pipeline is idle (safe to export)."""
    resp = requests.get(f"{base_url}/sync_status", timeout=30)
    resp.raise_for_status()
    data = resp.json()
    queue = data.get("queue", {})
    pending = queue.get("pending", 0)
    processing = queue.get("processing", 0)
    if pending > 0 or processing > 0:
        print(f"Sync still running: {pending} pending, {processing} processing. Aborting.")
        return False
    print(f"Sync idle. {queue.get('done', 0)} done, {data.get('total_chunks', 0)} chunks in DB.")
    return True


def _paginate(base_url: str, endpoint: str, key: str, per_page: int) -> list[dict]:
    """Generic paginator for Xano export endpoints."""
    all_items = []
    page = 1
    while True:
        url = f"{base_url}{endpoint}?page={page}&per_page={per_page}"
        print(f"  Fetching {key} page {page}...", end=" ")
        resp = requests.get(url, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        # Xano paging wraps items: data[key] = {items: [...], itemsTotal, pageTotal, ...}
        wrapper = data.get(key, {})
        items = wrapper.get("items", []) if isinstance(wrapper, dict) else wrapper
        # Use Xano paging metadata (more reliable than computed total_pages)
        total = wrapper.get("itemsTotal", data.get("total", 0)) if isinstance(wrapper, dict) else data.get("total", 0)
        total_pages = wrapper.get("pageTotal", data.get("total_pages", 1)) if isinstance(wrapper, dict) else data.get("total_pages", 1)
        print(f"{len(items)} items (total: {total}, page {page}/{total_pages})")
        all_items.extend(items)
        if page >= total_pages:
            break
        page += 1
    return all_items


def fetch_all_chunks(base_url: str) -> list[dict]:
    """Paginate through the chunks export endpoint."""
    return _paginate(base_url, "/export_chunks_dataset", "chunks", CHUNKS_PER_PAGE)


def fetch_all_articles(base_url: str) -> list[dict]:
    """Paginate through the articles export endpoint."""
    return _paginate(base_url, "/export_articles_dataset", "articles", ARTICLES_PER_PAGE)


def fetch_code_names() -> dict[str, str]:
    """Hardcoded LEX_codes_piste lookup: textId -> titre (only 5 codes)."""
    return {
        "LEGITEXT000006070633": "Code général des collectivités territoriales",
        "LEGITEXT000006070162": "Code des communes",
        "LEGITEXT000006070239": "Code électoral",
        "LEGITEXT000006074075": "Code de l'urbanisme",
        "LEGITEXT000006070721": "Code civil",
    }


def merge_chunks_with_articles(chunks: list[dict], articles: list[dict]) -> list[dict]:
    """Denormalize: enrich each chunk with its parent article metadata."""
    # Index articles by id_legifrance for O(1) lookup
    article_by_id = {a["id_legifrance"]: a for a in articles}
    # Code textId -> human-readable name
    code_names = fetch_code_names()

    merged = []
    orphans = 0
    for chunk in chunks:
        article = article_by_id.get(chunk.get("id_legifrance"))
        if article is None:
            orphans += 1
            continue
        row = {**chunk, **{f"article_{k}": v for k, v in article.items()
                           if k not in ("id", "content_hash", "last_sync_at")}}
        # Keep chunk-level id_legifrance (not prefixed)
        row["id_legifrance"] = chunk["id_legifrance"]
        # DB column is contenu_article, but schema expects article_texte
        if "article_contenu_article" in row:
            row["article_texte"] = row.pop("article_contenu_article")
        # Resolve code textId to human-readable name
        row["code_name"] = code_names.get(chunk.get("code"), chunk.get("code", ""))
        merged.append(row)

    if orphans > 0:
        print(f"  WARNING: {orphans} chunks had no matching article (skipped)")
    return merged


def build_dataset_features() -> Features:
    """Define the HuggingFace Dataset schema for the denormalized chunk+article rows.

    Each row is a chunk enriched with article metadata. Article fields are
    prefixed with "article_" (except id_legifrance which is shared).

    Chunk fields:
        id_legifrance, chunk_index, chunk_text, start_position, end_position,
        embedding (1024 floats), code, num, etat, fullSectionsTitre

    Article fields (prefixed "article_"):
        article_code, article_num, article_cid, article_idEli,
        article_idEliAlias, article_idTexte, article_cidTexte,
        article_texte, article_texteHtml, article_nota, article_notaHtml,
        article_surtitre, article_historique,
        article_dateDebut, article_dateFin,
        article_dateDebutExtension, article_dateFinExtension,
        article_etat, article_type_article, article_nature, article_origine,
        article_version_article, article_versionPrecedente,
        article_multipleVersions,
        article_sectionParentId, article_sectionParentCid,
        article_sectionParentTitre, article_fullSectionsTitre,
        article_ordre,
        article_partie, article_livre, article_titre, article_chapitre,
        article_section, article_sous_section, article_paragraphe,
        article_infosComplementaires, article_infosComplementairesHtml,
        article_conditionDiffere,
        article_infosRestructurationBranche, article_infosRestructurationBrancheHtml,
        article_renvoi, article_comporteLiensSP,
        article_idTechInjection, article_refInjection,
        article_numeroBo, article_inap

    Return a datasets.Features dict mapping column names to types.
    Available types: Value("string"), Value("int32"), Value("int64"),
                     Value("float32"), Value("bool"),
                     Sequence(Value("float32"), length=1024)

    Tip: You don't have to include ALL article fields — choose what's useful
    for dataset consumers (legal researchers, RAG systems, etc.)
    """
    
    
    return Features({
        # --- Chunk fields ---
        "chunk_text": Value("string"),
        "embedding": Sequence(Value("float32"), length=1024),
        "id_legifrance": Value("string"),
        "code_name": Value("string"),
        "chunk_index": Value("int32"),
        "start_position": Value("int32"),
        "end_position": Value("int32"),
        "code": Value("string"),
        "num": Value("string"),
        "etat": Value("string"),
        "fullSectionsTitre": Value("string"),
        # --- Article identifiers ---
        "article_id_legifrance": Value("string"),
        "article_code": Value("string"),
        "article_num": Value("string"),
        "article_cid": Value("string"),
        "article_idEli": Value("string"),
        "article_idEliAlias": Value("string"),
        "article_idTexte": Value("string"),
        "article_cidTexte": Value("string"),
        # --- Article content ---
        "article_texte": Value("string"),
        "article_texteHtml": Value("string"),
        "article_nota": Value("string"),
        "article_notaHtml": Value("string"),
        "article_surtitre": Value("string"),
        "article_historique": Value("string"),
        # --- Article dates ---
        "article_dateDebut": Value("string"),
        "article_dateFin": Value("string"),
        "article_dateDebutExtension": Value("string"),
        "article_dateFinExtension": Value("string"),
        # --- Article status & classification ---
        "article_etat": Value("string"),
        "article_type_article": Value("string"),
        "article_nature": Value("string"),
        "article_origine": Value("string"),
        "article_version_article": Value("string"),
        "article_versionPrecedente": Value("string"),
        "article_multipleVersions": Value("bool"),
        # --- Article hierarchy ---
        "article_sectionParentId": Value("string"),
        "article_sectionParentCid": Value("string"),
        "article_sectionParentTitre": Value("string"),
        "article_fullSectionsTitre": Value("string"),
        "article_ordre": Value("int32"),
        "article_partie": Value("string"),
        "article_livre": Value("string"),
        "article_titre": Value("string"),
        "article_chapitre": Value("string"),
        "article_section": Value("string"),
        "article_sous_section": Value("string"),
        "article_paragraphe": Value("string"),
        # --- Article extras ---
        "article_infosComplementaires": Value("string"),
        "article_infosComplementairesHtml": Value("string"),
        "article_conditionDiffere": Value("string"),
        "article_infosRestructurationBranche": Value("string"),
        "article_infosRestructurationBrancheHtml": Value("string"),
        "article_renvoi": Value("string"),
        "article_comporteLiensSP": Value("bool"),
        "article_idTechInjection": Value("string"),
        "article_refInjection": Value("string"),
        "article_numeroBo": Value("string"),
        "article_inap": Value("string"),
    })
    


def transform_row(raw: dict, features: Features) -> dict:
    """Map a merged chunk+article dict to the dataset schema."""
    row = {}
    for col_name in features:
        value = raw.get(col_name)
        # Coerce embedding from potential JSON string to list of floats
        if col_name == "embedding" and isinstance(value, str):
            value = json.loads(value)
        row[col_name] = value
    return row


def generate_dataset_card() -> str:
    """Generate the HF dataset card (README.md) content."""
    return """---
license: etalab-2.0
language:
  - fr
tags:
  - legal
  - french-law
  - embeddings
  - legifrance
  - mistral
size_categories:
  - 1K<n<10K
---

# French Legal Code Chunks with Embeddings

Chunked articles from 5 French legal codes sourced from
[Legifrance](https://www.legifrance.gouv.fr/) via the PISTE API,
with 1024-dimensional embeddings generated by Mistral AI.

Each row is a text chunk enriched with full article metadata from the parent
legal code article.

## Dataset Description

- **Source**: [PISTE Legifrance API](https://piste.gouv.fr/) (official French government legal database)
- **License**: [Licence Ouverte / Etalab 2.0](https://www.etalab.gouv.fr/licence-ouverte-open-licence/)
- **Embeddings**: Mistral AI `mistral-embed` (1024 dimensions)
- **Update frequency**: Daily (nightly sync at 02:00 UTC, dataset push at 06:00 UTC)
- **Rows**: ~1,630 chunks from ~1,630 articles

### Legal codes included

| Code ID | Name |
|---------|------|
| `LEGITEXT000006070633` | Code general des collectivites territoriales |
| `LEGITEXT000006070162` | Code des communes |
| `LEGITEXT000006070239` | Code electoral |
| `LEGITEXT000006074075` | Code de l'urbanisme |
| `LEGITEXT000006070721` | Code civil |

## Schema

### Chunk fields
| Column | Type | Description |
|--------|------|-------------|
| `chunk_text` | string | Text content of the chunk |
| `embedding` | float32[1024] | Mistral AI embedding vector |
| `id_legifrance` | string | Legifrance article identifier |
| `code_name` | string | Human-readable code name (e.g. "Code civil") |
| `chunk_index` | int32 | Chunk position within the article (0-indexed) |
| `start_position` | int32 | Character offset in original article text |
| `end_position` | int32 | End character offset in original article text |
| `code` | string | Legal code identifier (e.g. LEGITEXT000006070721) |
| `num` | string | Article number (e.g. "L. 1234-5") |
| `etat` | string | Article status (VIGUEUR, ABROGE, etc.) |
| `fullSectionsTitre` | string | Full hierarchy path in the code |

### Article metadata fields (prefixed `article_`)

#### Identifiers
| Column | Type | Description |
|--------|------|-------------|
| `article_id_legifrance` | string | Legifrance article ID |
| `article_code` | string | Legal code ID |
| `article_num` | string | Article number |
| `article_cid` | string | Consolidated ID |
| `article_idEli` | string | ELI (European Legislation Identifier) |
| `article_idEliAlias` | string | ELI alias |
| `article_idTexte` | string | Text ID |
| `article_cidTexte` | string | Consolidated text ID |

#### Content
| Column | Type | Description |
|--------|------|-------------|
| `article_texte` | string | Full article plain text |
| `article_texteHtml` | string | Full article HTML |
| `article_nota` | string | Article notes (plain text) |
| `article_notaHtml` | string | Article notes (HTML) |
| `article_surtitre` | string | Article subtitle |
| `article_historique` | string | Article history |

#### Dates & Status

**Date format**: `article_dateDebut` and `article_dateFin` are stored as **Unix timestamps in milliseconds** (string type). This is the raw format returned by the Legifrance PISTE API.

To convert to a human-readable date in Python:

```python
from datetime import datetime, timezone

timestamp_ms = "1301529600000"
dt = datetime.fromtimestamp(int(timestamp_ms) / 1000, tz=timezone.utc)
print(dt)  # 2011-03-31 00:00:00+00:00
```

Special value: `32472144000000` (year 2999) means "no end date" — the article is in force indefinitely.

| Column | Type | Description |
|--------|------|-------------|
| `article_dateDebut` | string | Effective start date (Unix ms) |
| `article_dateFin` | string | Effective end date (Unix ms, `32472144000000` = indefinite) |
| `article_dateDebutExtension` | string | Extension start date (Unix ms) |
| `article_dateFinExtension` | string | Extension end date (Unix ms) |
| `article_etat` | string | Status: `VIGUEUR` (in force), `ABROGE` (repealed), etc. |
| `article_type_article` | string | Article type |
| `article_nature` | string | Legal nature |
| `article_origine` | string | Origin (e.g. `LEGI`) |
| `article_version_article` | string | Version identifier |
| `article_versionPrecedente` | string | Previous version ID |
| `article_multipleVersions` | bool | Has multiple versions |

#### Hierarchy
| Column | Type | Description |
|--------|------|-------------|
| `article_sectionParentId` | string | Parent section ID |
| `article_sectionParentCid` | string | Parent section consolidated ID |
| `article_sectionParentTitre` | string | Parent section title |
| `article_fullSectionsTitre` | string | Full hierarchy path |
| `article_ordre` | int32 | Sort order within the code |
| `article_partie` | string | Partie (e.g. "Partie legislative") |
| `article_livre` | string | Livre |
| `article_titre` | string | Titre |
| `article_chapitre` | string | Chapitre |
| `article_section` | string | Section |
| `article_sous_section` | string | Sous-section |
| `article_paragraphe` | string | Paragraphe |

#### Extras
| Column | Type | Description |
|--------|------|-------------|
| `article_infosComplementaires` | string | Additional info (plain text) |
| `article_infosComplementairesHtml` | string | Additional info (HTML) |
| `article_conditionDiffere` | string | Deferred condition |
| `article_infosRestructurationBranche` | string | Branch restructuring info |
| `article_infosRestructurationBrancheHtml` | string | Branch restructuring (HTML) |
| `article_renvoi` | string | Cross-references |
| `article_comporteLiensSP` | bool | Contains SP links |
| `article_idTechInjection` | string | Technical injection ID |
| `article_refInjection` | string | Injection reference |
| `article_numeroBo` | string | BO number |
| `article_inap` | string | INAP code |

## Usage

```python
from datasets import load_dataset
from datetime import datetime, timezone

ds = load_dataset("ArthurSrz/french-legal-chunks", split="train")

# Access a chunk with its embedding and article metadata
row = ds[0]
print(row["code_name"])                # e.g. "Code civil"
print(row["chunk_text"][:200])
print(len(row["embedding"]))           # 1024

# Convert dates from Unix ms to datetime
date_debut = datetime.fromtimestamp(int(row["article_dateDebut"]) / 1000, tz=timezone.utc)
print(date_debut)                      # e.g. 2011-03-31 00:00:00+00:00

# Filter by legal code
code_civil = ds.filter(lambda x: x["code_name"] == "Code civil")

# Filter active articles only
en_vigueur = ds.filter(lambda x: x["article_etat"] == "VIGUEUR")

# Use embeddings for semantic search
import numpy as np
query_emb = np.array(ds[0]["embedding"])
```

## Provenance

Built by the [marIAnne](https://github.com/ArthurSrz/open_codes) project.
Sync pipeline fetches articles nightly from PISTE Legifrance, chunks them,
and generates embeddings via Mistral AI.
"""


def main():
    parser = argparse.ArgumentParser(description="Export Xano chunks to HuggingFace")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and validate only, no push")
    args = parser.parse_args()

    base_url = os.environ.get("XANO_BASE_URL")
    hf_token = os.environ.get("HF_TOKEN")

    if not base_url:
        print("ERROR: XANO_BASE_URL environment variable is required")
        sys.exit(1)
    if not args.dry_run and not hf_token:
        print("ERROR: HF_TOKEN environment variable is required (or use --dry-run)")
        sys.exit(1)

    # Step 1: Check sync status
    print("Checking sync status...")
    if not check_sync_status(base_url):
        sys.exit(1)

    # Step 2: Fetch all data from both tables
    print("Fetching chunks from Xano...")
    raw_chunks = fetch_all_chunks(base_url)
    print(f"Total chunks fetched: {len(raw_chunks)}")

    print("Fetching articles from Xano...")
    raw_articles = fetch_all_articles(base_url)
    print(f"Total articles fetched: {len(raw_articles)}")

    if len(raw_chunks) == 0:
        print("ERROR: No chunks found. Aborting.")
        sys.exit(1)

    # Step 3: Merge chunks with article metadata
    print("Merging chunks with article metadata...")
    merged = merge_chunks_with_articles(raw_chunks, raw_articles)
    print(f"Merged rows: {len(merged)}")

    # Step 4: Build dataset with typed schema
    features = build_dataset_features()
    if features is None:
        print("ERROR: build_dataset_features() returned None — implement it first!")
        sys.exit(1)

    rows = [transform_row(r, features) for r in merged]
    ds = Dataset.from_list(rows, features=features)
    print(f"Dataset built: {ds}")
    print(f"Sample embedding length: {len(ds[0]['embedding'])}")

    # Validate embeddings
    bad = sum(1 for row in ds if len(row["embedding"]) != 1024)
    if bad > 0:
        print(f"WARNING: {bad} chunks have non-1024 embeddings")

    if args.dry_run:
        print("DRY RUN complete. Dataset looks good. Skipping push.")
        return

    # Step 5: Push to HuggingFace Hub with dataset card
    print(f"Pushing to HuggingFace Hub: {HF_REPO_ID}...")
    ds.push_to_hub(
        HF_REPO_ID,
        token=hf_token,
        commit_message=f"Daily update: {len(ds)} chunks from {len(raw_articles)} articles",
    )

    # Push dataset card
    from huggingface_hub import HfApi
    api = HfApi(token=hf_token)
    api.upload_file(
        path_or_fileobj=generate_dataset_card().encode(),
        path_in_repo="README.md",
        repo_id=HF_REPO_ID,
        repo_type="dataset",
        commit_message="Update dataset card",
    )

    print(f"Done! Dataset available at https://huggingface.co/datasets/{HF_REPO_ID}")


if __name__ == "__main__":
    main()
