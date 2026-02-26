# Implementation Plan: Multi-Source Legal Data Pipeline

**Feature Branch**: `005-multi-legal-sync`
**Created**: 2026-02-25
**Spec**: [spec.md](spec.md)

## Tech Stack

- **Backend**: Xano (XanoScript tasks and API endpoints), Workspace ID: 5, branch `requete_textes`
- **Embeddings**: Mistral AI `mistral-embed` (1024-dim), same as existing pipeline
- **Data sources**: PISTE Judilibre API (KeyId auth), PISTE Circulaires fund (OAuth2), PISTE QUESTIONS-REPONSES fund (OAuth2)
- **Export**: Python 3.12+, `requests`, `datasets` (HuggingFace)
- **Tests**: pytest, same structure as `scripts/tests/test_data_quality.py`
- **CI/CD**: GitHub Actions `.github/workflows/push-hf-dataset.yml` (no changes needed)

## Architecture

### Unified Queue+Worker (mirrors spec 001 pattern exactly)

```
PISTE APIs
  ├─ Judilibre /search       → Task A1: JuriPopulateQueue  (03:00 UTC)
  ├─ CIRCULAIRES endpoint     → Task A2: CircPopulateQueue  (03:15 UTC)
  └─ QUESTIONS-REPONSES       → Task A3: RepPopulateQueue   (03:30 UTC)
             │ (all write to QUEUE_legal_sync with source_type)
             ▼
    Task B: LegalSyncWorker (every 4s)
      reads source_type → dispatches fetch+chunk+embed
             │
             ▼
  ┌─────────────────────────────────────┐
  │  Source metadata tables:            │
  │   REF_decisions_judilibre           │
  │   REF_circulaires                   │
  │   REF_reponses_ministerial          │
  └─────────────────────────────────────┘
             │
             ▼
  REF_legal_chunks (unified, source_type discriminator)
             │
             ▼
  /export_legal_chunks_dataset (Xano endpoint)
             │
             ▼
  scripts/export_to_hf.py (3 new configs)
             │
             ▼
  ArthurSrz/open_codes (jurisprudence | circulaires | reponses_legis)
```

## New Xano Tables (Workspace 5)

### QUEUE_legal_sync
| Column | Type | Notes |
|--------|------|-------|
| source_type | string | judilibre \| circulaire \| reponse_ministerielle |
| source_id | string | Decision ID / circulaire ID / Q-R ID |
| status | string | pending / processing / completed / error |
| created_at | timestamp | auto |

### REF_decisions_judilibre
| Column | Type | Notes |
|--------|------|-------|
| id_judilibre | string | unique key |
| jurisdiction | string | |
| chamber | string | |
| date_decision | timestamp | |
| solution | string | |
| zone_introduction | text | |
| zone_motivations | text | best for RAG |
| zone_dispositif | text | the holding |
| fiche_arret | text | nullable — official summary |
| url_judilibre | string | |
| last_sync_at | timestamp | |

### REF_circulaires
| Column | Type | Notes |
|--------|------|-------|
| id_circulaire | string | unique key |
| numero | string | |
| date_parution | timestamp | |
| ministere | string | |
| objet | text | subject/abstract |
| full_text | text | |
| url_legifrance | string | |
| last_sync_at | timestamp | |

### REF_reponses_ministerial
| Column | Type | Notes |
|--------|------|-------|
| id_reponse | string | unique key |
| numero_question | string | |
| date_reponse | timestamp | |
| ministere | string | |
| question_text | text | |
| reponse_text | text | |
| url_legifrance | string | |
| last_sync_at | timestamp | |

### REF_legal_chunks
| Column | Type | Notes |
|--------|------|-------|
| source_type | string | discriminator |
| source_id | string | FK to appropriate source table |
| chunk_text | text | |
| chunk_index | int | 0-9 |
| embedding | text | JSON array, 1024-dim |
| is_stale | boolean | default false |
| zone | string | for Judilibre: motivations/dispositif/etc. |

## Xano Tasks

### Task A1 — JuriPopulateQueue (nightly 03:00 UTC)
```
api.request → Judilibre /search?query={active_code}&date_start={30_days_ago}
foreach result.id (safe — no external calls inside loop):
  db.query QUEUE_legal_sync WHERE source_type=="judilibre" && source_id==id
  if NOT found: db.add QUEUE_legal_sync {source_type:"judilibre", source_id:id, status:"pending"}
```

### Task A2 — CircPopulateQueue (nightly 03:15 UTC)
```
api.request → PISTE /CIRCULAIRES (paginated, OAuth2, last 30 days)
foreach circulaire.id (safe):
  db.query REF_circulaires WHERE id_circulaire==id
  if NOT found or stale: db.add QUEUE_legal_sync {source_type:"circulaire", ...}
```

### Task A3 — RepPopulateQueue (nightly 03:30 UTC)
```
api.request → PISTE /QUESTIONS-REPONSES (paginated, OAuth2, last 30 days)
foreach reponse.id (safe):
  db.query REF_reponses_ministerial WHERE id_reponse==id
  if NOT found: db.add QUEUE_legal_sync {source_type:"reponse_ministerielle", ...}
```

### Task B — LegalSyncWorker (every 4s — follows Task 14 pattern)
```
1. db.query QUEUE_legal_sync {status:"pending", return:single} → item
2. if null: exit (guard flag pattern)
3. db.edit QUEUE_legal_sync item {status:"processing"}
4. if item.source_type == "judilibre":
     api.request → Judilibre /decision?id={item.source_id} (KeyId header)
     db.add/edit REF_decisions_judilibre (all fields inlined)
     full_text = zone_motivations + " " + zone_dispositif
   elif item.source_type == "circulaire":
     api.request → PISTE /CIRCULAIRES/{item.source_id} (OAuth2)
     db.add/edit REF_circulaires (all fields inlined)
     full_text = objet + " " + full_text
   elif item.source_type == "reponse_ministerielle":
     api.request → PISTE /QUESTIONS-REPONSES/{item.source_id} (OAuth2)
     db.add/edit REF_reponses_ministerial (all fields inlined)
     full_text = question_text + " " + reponse_text
5. Mark old chunks is_stale=true for (source_type, source_id)
6. 10 unrolled blocks: chunk(full_text, N) → mistral_embed → db.add REF_legal_chunks
7. db.edit QUEUE_legal_sync {status:"completed"}
```

**XanoScript 7-rule compliance**:
- Rule 1: No foreach+external — Task B processes ONE item per run (triggered every 4s)
- Rule 2: No nested function.run — OAuth inline, no helper functions
- Rule 3: db.add fields all inlined explicitly
- Rule 4: No db.delete — use is_stale flag for stale chunks
- Rule 5: Guard flag pattern replaces early return (if item null → set completed=true → skip processing block)
- Rule 6: util.sleep value=4 (4 seconds), NOT value=4000
- Rule 7: No task.run — tasks scheduled via Xano dashboard

## New Xano API Endpoint

### GET /export_legal_chunks_dataset
- Params: `source_type` (filter), `page`, `per_page`
- Returns: REF_legal_chunks + source metadata (joined via source_type)
- Reuses same paging wrapper pattern as existing endpoints (itemsTotal, pageTotal)

## Python Export Changes

### scripts/export_to_hf.py additions
Three new functions per source config:

```python
# Per config: fetch_legal_chunks(base_url, source_type) → uses _paginate()
# Per config: build_[source]_features() → Features dict
# Per config: push_[source]_config(ds, token)

# Main extended to call all three new configs after existing default config
```

### New HF dataset configs
| Config | source_type filter | Key metadata fields |
|--------|--------------------|---------------------|
| `jurisprudence` | judilibre | jurisdiction, chamber, date_decision, solution, fiche_arret, url_judilibre, zone |
| `circulaires` | circulaire | numero, date_parution, ministere, objet, url_legifrance |
| `reponses_legis` | reponse_ministerielle | numero_question, date_reponse, ministere, question_text, url_legifrance |

## Test Coverage (scripts/tests/test_data_quality.py additions)

- `test_legal_chunks_dedup()` — no duplicate (source_type, source_id, chunk_index)
- `test_legal_chunks_no_stale()` — all exported chunks have is_stale=false
- `test_legal_chunks_embeddings()` — all embeddings are 1024 floats
- `test_judilibre_has_fiche_arret_field()` — field exists (nullable ok)
- `test_circulaires_has_ministere()` — ministere not null
- `test_reponses_has_question_text()` — question_text not null

## Key Files to Modify

| File | Change |
|------|--------|
| `scripts/export_to_hf.py` | Add 3 new fetch+build+push functions + extend main() |
| `scripts/tests/test_data_quality.py` | Add 6+ new test cases for new source types |

## Key Files to Create

| File | Description |
|------|-------------|
| `specs/005-multi-legal-sync/spec.md` | Feature spec (done) |
| `specs/005-multi-legal-sync/tasks.md` | This file's tasks |

## XanoScript Gotchas to Watch

- `where` compound conditions must be on single line (no line breaks)
- `db.query return={type:"single"}` for queue polling
- `paging` block inside `return`, not as sibling
- Filter syntax: `|round:0:"floor"` NOT `|round(0, "floor")`
