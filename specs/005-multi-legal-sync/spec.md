# Feature Specification: Multi-Source Legal Data Pipeline

**Feature Branch**: `005-multi-legal-sync`
**Created**: 2026-02-25
**Status**: Draft
**Input**: User description: "Multi-source legal data pipeline extending the existing marIAnne sync pipeline (spec 001) to add three new data sources from the PISTE platform: Judilibre (Court of Cassation decisions with built-in fiches d'arrêts), PISTE Circulaires (ministry circular instructions), and PISTE Réponses ministérielles (parliamentary Q&A). Uses a unified QUEUE_legal_sync table with source_type discriminator and a single unified REF_legal_chunks table. Three new HF dataset configs pushed to ArthurSrz/open_codes."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Jurisprudence Data Available in Open Codes Dataset (Priority: P1)

As a legal researcher or RAG application developer, I want Court of Cassation decisions (with their official fiches d'arrêts) to be available in the `ArthurSrz/open_codes` HuggingFace dataset so that I can run semantic search over French case law using the same embedding infrastructure as the legal codes.

**Why this priority**: Case law is the single most-requested missing layer. Without decisions, a semantic search system returns only legislative text — leaving out how courts actually interpret the law. This unlocks the core use case for enirtcod.fr.

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="jurisprudence")` returns rows with `chunk_text`, `embedding` (1024 floats), `jurisdiction`, `date_decision`, `fiche_arret`, and `url_judilibre`. At least one row exists for each active code in LEX_codes_piste.

**Acceptance Scenarios**:

1. **Given** a nightly sync cycle has completed, **When** loading `open_codes` with config `jurisprudence`, **Then** rows contain at least `chunk_text`, `embedding`, `jurisdiction`, `date_decision`, `fiche_arret`, and `url_judilibre` fields
2. **Given** a decision that was synced in a previous cycle has been updated in Judilibre, **When** the next nightly sync runs, **Then** the old chunks are marked stale and replaced with fresh chunks reflecting the updated content
3. **Given** a decision that already exists in the local database is found again in Judilibre search results, **When** the queue populate task runs, **Then** the decision is NOT re-queued (no duplicate)

---

### User Story 2 — Circulaires Data Available in Open Codes Dataset (Priority: P2)

As a legal practitioner or compliance professional, I want ministry circulaires to be available in the dataset so that I can semantically search official administrative interpretations of the law alongside the primary legal text.

**Why this priority**: Circulaires are the primary channel through which ministries explain how to apply legislation. They form a critical layer of the French administrative doctrine that is systematically absent from open legal datasets.

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="circulaires")` returns rows with `chunk_text`, `embedding`, `ministere`, `numero`, `date_parution`, and `url_legifrance`. At least 10 rows exist after first sync.

**Acceptance Scenarios**:

1. **Given** the nightly Circulaires sync has run, **When** a user loads the `circulaires` config, **Then** each row contains `ministere`, `objet`, `numero`, `date_parution`, and a valid `url_legifrance` link
2. **Given** a circulaire already synced is re-encountered in the PISTE feed, **When** the populate task runs, **Then** no duplicate queue entry is created
3. **Given** a circulaire has been updated since last sync, **When** re-processed by the worker, **Then** its old chunks are marked stale and new chunks replace them

---

### User Story 3 — Réponses Ministérielles Available in Open Codes Dataset (Priority: P3)

As a legal researcher studying legislative intent, I want parliamentary question-and-answer records to be available in the dataset so that I can find how ministers interpreted specific laws at the time of enactment.

**Why this priority**: Réponses ministérielles capture legislative intent — the "why" behind a law. They are frequently cited in legal briefs but scattered across JO archives. Making them searchable is a unique open-data contribution.

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="reponses_legis")` returns rows with `chunk_text`, `embedding`, `ministere`, `question_text`, `numero_question`, and `url_legifrance`.

**Acceptance Scenarios**:

1. **Given** the nightly Q&R sync has run, **When** loading the `reponses_legis` config, **Then** each row includes `question_text`, `reponse_text` (within the chunk), `ministere`, and `date_reponse`
2. **Given** a réponse was previously synced, **When** its source record is found again in PISTE, **Then** no duplicate queue entry is created
3. **Given** a réponse chunk was created before a metadata update, **When** the worker reprocesses it, **Then** stale chunks are replaced via the `is_stale` flag

---

### User Story 4 — Unified Nightly Export Covers All Four Dataset Configs (Priority: P1)

As the pipeline operator, I want the existing GitHub Actions nightly export job to automatically include all three new source types so that I do not need to maintain or schedule separate export jobs.

**Why this priority**: Operational simplicity is critical. A single broken export script should not take down just one config — the system must succeed or fail as a whole, with clear per-config validation.

**Independent Test**: Triggering the GitHub Action `push-hf-dataset.yml` results in `ArthurSrz/open_codes` having four configs: `default`, `jurisprudence`, `circulaires`, `reponses_legis`. Pytest suite passes before export.

**Acceptance Scenarios**:

1. **Given** all three new sync tasks have run at least once, **When** the GitHub Action runs at 06:00 UTC, **Then** it pushes data for all four configs in a single run without manual intervention
2. **Given** pytest finds data quality issues in one new source, **When** the export runs, **Then** the entire export is blocked
3. **Given** one of the new source tables is empty, **When** the export runs, **Then** the action fails with a clear error naming the empty source

---

### Edge Cases

- **Judilibre rate limiting**: If the worker receives a 429 from Judilibre, the queue item must be marked `error` (not `completed`) to allow retry on next worker cycle.
- **Missing `fiche_arret` field**: Some decisions may not have an official summary. The system must accept `null` for `fiche_arret` without failing the sync.
- **Empty PISTE Circulaires response**: If the API returns 0 results for a given period, the populate task exits cleanly with no queue items created.
- **Duplicate `source_id` across source types**: A string like "12345" could appear as both a circulaire ID and a decision ID. Dedup checks must use `(source_type, source_id)` composite key, never `source_id` alone.
- **Embedding failure for a chunk**: If Mistral embedding returns an error for one chunk, the entire item is marked `error` in the queue. Partial chunk sets must not be written to `REF_legal_chunks`.
- **Worker queue drain during export**: The export script logs a warning if any `processing` items remain in the queue. Stale-chunk filtering ensures consistency regardless.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST nightly collect Court of Cassation decisions from Judilibre and queue them using `KeyId` header authentication with the PISTE Judilibre service
- **FR-002**: System MUST nightly collect ministry circulaires from the PISTE Circulaires fund and queue them for processing
- **FR-003**: System MUST nightly collect réponses ministérielles from the PISTE QUESTIONS-REPONSES fund and queue them for processing
- **FR-004**: All three populate tasks MUST write to the unified `QUEUE_legal_sync` table with a `source_type` field (`judilibre` | `circulaire` | `reponse_ministerielle`)
- **FR-005**: System MUST deduplicate queue entries before insertion using `(source_type, source_id)` composite key — no item should be queued twice with the same combination
- **FR-006**: A unified worker task MUST process items from `QUEUE_legal_sync`, dispatching on `source_type` to fetch full records from the appropriate PISTE endpoint
- **FR-007**: For Judilibre decisions, the worker MUST extract and store `zone_motivations`, `zone_dispositif`, and `fiche_arret` in `REF_decisions_judilibre`
- **FR-008**: For all source types, the worker MUST chunk the full text (max 10 chunks per item, unrolled, following the Task 14 pattern) and generate 1024-dim Mistral embeddings stored in `REF_legal_chunks`
- **FR-009**: `REF_legal_chunks` MUST use a unified schema with `source_type`, `source_id`, `chunk_text`, `chunk_index`, `embedding`, and `is_stale` fields
- **FR-010**: Before re-chunking an item, the worker MUST mark all existing chunks for that `(source_type, source_id)` as stale (`is_stale = true`)
- **FR-011**: System MUST provide a paginated `export_legal_chunks_dataset` Xano endpoint accepting `source_type` as a filter parameter and returning source metadata joined with chunk data
- **FR-012**: The export script MUST push three new HuggingFace dataset configs (`jurisprudence`, `circulaires`, `reponses_legis`) to `ArthurSrz/open_codes` with typed schemas
- **FR-013**: Pytest test suite MUST be extended to validate deduplication, stale-chunk filtering, and embedding completeness for each new source type
- **FR-014**: All four dataset configs MUST be exported in the same nightly GitHub Action run; test failure on any config blocks the entire export
- **FR-015**: Worker tasks MUST follow XanoScript 7-rule constraints: no `foreach` with external calls, no nested `function.run`, `db.add` fields inlined, no `db.delete`, no early returns, `util.sleep` in seconds

### Key Entities

- **Legal Sync Queue Item** (`QUEUE_legal_sync`): A work item with `source_type` discriminator, `source_id`, and `status`. The unified entry point for all three new sources.
- **Court of Cassation Decision** (`REF_decisions_judilibre`): Metadata and zoned text (introduction, motivations, dispositif) of a single decision, plus its `fiche_arret` official summary.
- **Circulaire** (`REF_circulaires`): A ministerial instruction document with `ministere`, `numero`, `objet`, and full text.
- **Réponse Ministérielle** (`REF_reponses_ministerial`): A parliamentary Q&A record with `question_text`, `reponse_text`, `ministere`, and `date_reponse`.
- **Legal Chunk** (`REF_legal_chunks`): A text chunk with 1024-dim embedding, linked to any of the three source types via `(source_type, source_id)`. Has `is_stale` flag for stale-chunk management.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After first successful sync cycle, `load_dataset("ArthurSrz/open_codes", name="jurisprudence")` returns at least 50 rows with valid 1024-dim embeddings
- **SC-002**: After first successful sync cycle, `circulaires` and `reponses_legis` configs each return at least 10 rows with valid 1024-dim embeddings
- **SC-003**: The pytest test suite passes for all four configs with zero failures before each HuggingFace push
- **SC-004**: The `QUEUE_legal_sync` table contains zero duplicate `(source_type, source_id)` combinations after any populate task run
- **SC-005**: The `REF_legal_chunks` table contains zero non-stale duplicate `(source_type, source_id, chunk_index)` combinations after any worker run
- **SC-006**: The nightly GitHub Action exports all four configs in a single run completing in under 30 minutes
- **SC-007**: All chunk rows in the exported datasets have `embedding` fields of exactly 1024 floats — zero rows with missing or malformed embeddings

---

## Assumptions

- The PISTE Judilibre service uses `KeyId` header authentication separate from Legifrance OAuth. An environment variable `JUDILIBRE_KEY_ID` will be added to the Xano workspace.
- The PISTE Circulaires and QUESTIONS-REPONSES funds use the same OAuth2 client credentials as the existing Legifrance integration. If this proves incorrect, a separate auth block will be added to Task B.
- The `fiche_arret` field in the Judilibre `/decision` API response is nullable; the system will not fail if it is absent.
- Judilibre `/search` accepts a `date_start` parameter to limit results to recent decisions, enabling incremental syncs.
- All source text lengths remain within the existing 10-chunk limit (~80,000 chars). Longer texts are truncated at chunk 9.
- The existing `_paginate()` utility in `export_to_hf.py` is reusable for the new endpoint without modification.
