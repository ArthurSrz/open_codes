# Tasks: Multi-Source Legal Data Pipeline

**Input**: Design documents from `/specs/005-multi-legal-sync/`
**Prerequisites**: plan.md ✅, spec.md ✅

**Organization**: Tasks are grouped by user story. Each story (US1 Judilibre, US2 Circulaires, US3 Réponses) can be implemented and tested independently. US4 (unified export) depends on all three.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files/tables, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the two shared Xano tables that underpin all three data sources

- [ ] T001 Create QUEUE_legal_sync table in Xano Workspace 5 with columns: source_type (string), source_id (string), status (string), created_at (timestamp)
- [ ] T002 Create REF_legal_chunks table in Xano Workspace 5 with columns: source_type (string), source_id (string), chunk_text (text), chunk_index (int), embedding (text), is_stale (boolean default false), zone (string)

**Checkpoint**: Shared tables exist — source-specific tables and tasks can now be created

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Xano environment setup and source-specific tables that block all user stories

**⚠️ CRITICAL**: No user story task implementation can begin until this phase is complete

- [ ] T003 Add JUDILIBRE_KEY_ID environment variable to Xano Workspace 5 (required for Judilibre KeyId header auth)
- [ ] T004 [P] Create REF_decisions_judilibre table in Xano Workspace 5 with columns: id_judilibre (string unique), jurisdiction (string), chamber (string), date_decision (timestamp), solution (string), zone_introduction (text), zone_motivations (text), zone_dispositif (text), fiche_arret (text nullable), url_judilibre (string), last_sync_at (timestamp)
- [ ] T005 [P] Create REF_circulaires table in Xano Workspace 5 with columns: id_circulaire (string unique), numero (string), date_parution (timestamp), ministere (string), objet (text), full_text (text), url_legifrance (string), last_sync_at (timestamp)
- [ ] T006 [P] Create REF_reponses_ministerial table in Xano Workspace 5 with columns: id_reponse (string unique), numero_question (string), date_reponse (timestamp), ministere (string), question_text (text), reponse_text (text), url_legifrance (string), last_sync_at (timestamp)

**Checkpoint**: All 5 Xano tables exist — user story implementation can now begin

---

## Phase 3: User Story 1 — Jurisprudence (Priority: P1) 🎯 MVP

**Goal**: Nightly sync of Court of Cassation decisions into the `jurisprudence` HF dataset config

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="jurisprudence")` returns rows with `chunk_text`, `embedding` (1024 floats), `jurisdiction`, `date_decision`, `fiche_arret`, `url_judilibre`

### Implementation for User Story 1

- [ ] T007 [US1] Create Task A1 (JuriPopulateQueue) in Xano Workspace 5 branch `requete_textes`, scheduled nightly 03:00 UTC: call Judilibre /search for each active code in LEX_codes_piste, loop results using `foreach` + `db.query`/`db.add` only (no external calls in loop), dedup check via `db.query QUEUE_legal_sync WHERE source_type=="judilibre" && source_id=={id}` (single line), insert new items with status "pending"
- [ ] T008 [US1] Create Task B (LegalSyncWorker) in Xano Workspace 5 branch `requete_textes`, scheduled every 4s: implement `db.query QUEUE_legal_sync {status:"pending", return:{type:"single"}}` poll, guard flag pattern (not early return) when null, `db.edit` status to "processing", Judilibre branch only for now — `api.request` to Judilibre /decision with KeyId header, inline `db.add REF_decisions_judilibre` with all fields explicitly mapped, compute `full_text = zone_motivations + " " + zone_dispositif`
- [ ] T009 [US1] Extend Task B to mark stale chunks before re-chunking: `db.query REF_legal_chunks WHERE source_type=="judilibre" && source_id=={item.source_id}`, use `foreach` + `db.edit {is_stale:true}` (safe — db ops only, no external calls)
- [ ] T010 [US1] Extend Task B with 10 unrolled chunking+embedding blocks for Judilibre (blocks 0–9): each block calls `chunker_texte(index=N)` → `mistral_generer_embedding` → inline `db.add REF_legal_chunks {source_type:"judilibre", source_id:..., chunk_text:..., chunk_index:N, embedding:..., is_stale:false, zone:"motivations"}`; final `db.edit QUEUE_legal_sync {status:"completed"}`
- [ ] T011 [US1] Create GET /export_legal_chunks_dataset endpoint in Xano Workspace 5 (v1 branch): params `source_type`, `page`, `per_page`; `db.query REF_legal_chunks WHERE source_type=={source_type} && is_stale==false` with paging inside `return`; join chunk data with source metadata from appropriate source table based on `source_type`
- [ ] T012 [US1] Add `fetch_legal_chunks(base_url, source_type)` function in `scripts/export_to_hf.py` using existing `_paginate()` with endpoint `/export_legal_chunks_dataset` and source_type param
- [ ] T013 [US1] Add `build_jurisprudence_features()` and `build_jurisprudence_dataset(chunks)` functions in `scripts/export_to_hf.py` returning typed `Features` with: chunk_text, embedding (Sequence float32 1024), source_id, chunk_index, jurisdiction, chamber, date_decision, solution, fiche_arret, url_judilibre, zone
- [ ] T014 [US1] Extend `main()` in `scripts/export_to_hf.py` to fetch, build, and push `jurisprudence` config to `ArthurSrz/open_codes` with `config_name="jurisprudence"` in `push_to_hub()` call

**Checkpoint**: US1 complete — `load_dataset("ArthurSrz/open_codes", name="jurisprudence")` returns valid rows with embeddings

---

## Phase 4: User Story 2 — Circulaires (Priority: P2)

**Goal**: Nightly sync of ministry circulaires into the `circulaires` HF dataset config

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="circulaires")` returns rows with `chunk_text`, `embedding`, `ministere`, `numero`, `date_parution`, `url_legifrance`

### Implementation for User Story 2

- [ ] T015 [US2] Create Task A2 (CircPopulateQueue) in Xano Workspace 5 branch `requete_textes`, scheduled nightly 03:15 UTC: call PISTE /CIRCULAIRES endpoint (OAuth2 auth), loop results with `foreach` + `db.query`/`db.add` (safe — no external in loop), dedup check via `db.query REF_circulaires WHERE id_circulaire=={id}`, insert missing items in QUEUE_legal_sync with `source_type:"circulaire"`
- [ ] T016 [US2] Extend Task B (LegalSyncWorker) with Circulaires dispatch branch: when `source_type == "circulaire"`, `api.request` PISTE /CIRCULAIRES/{source_id} (OAuth2), inline `db.add/edit REF_circulaires` with all fields explicitly mapped, compute `full_text = objet + " " + full_text`
- [ ] T017 [US2] Extend Task B stale-chunk marking to cover `source_type=="circulaire"` (same `foreach`+`db.edit` pattern as T009 but for circulaire)
- [ ] T018 [US2] Add 10 unrolled embedding blocks for Circulaires in Task B (same structure as T010): `db.add REF_legal_chunks {source_type:"circulaire", ...}`
- [ ] T019 [US2] Add `build_circulaires_features()` and `build_circulaires_dataset(chunks)` in `scripts/export_to_hf.py` with Features: chunk_text, embedding, source_id, chunk_index, numero, date_parution, ministere, objet, url_legifrance
- [ ] T020 [US2] Extend `main()` in `scripts/export_to_hf.py` to fetch, build, and push `circulaires` config to `ArthurSrz/open_codes`

**Checkpoint**: US2 complete — `load_dataset("ArthurSrz/open_codes", name="circulaires")` returns valid rows

---

## Phase 5: User Story 3 — Réponses Ministérielles (Priority: P3)

**Goal**: Nightly sync of parliamentary Q&A records into the `reponses_legis` HF dataset config

**Independent Test**: `load_dataset("ArthurSrz/open_codes", name="reponses_legis")` returns rows with `chunk_text`, `embedding`, `ministere`, `question_text`, `numero_question`, `url_legifrance`

### Implementation for User Story 3

- [ ] T021 [US3] Create Task A3 (RepPopulateQueue) in Xano Workspace 5 branch `requete_textes`, scheduled nightly 03:30 UTC: call PISTE /QUESTIONS-REPONSES endpoint (OAuth2), loop results with `foreach` + `db.query`/`db.add` (safe), dedup check via `db.query REF_reponses_ministerial WHERE id_reponse=={id}`, insert missing in QUEUE_legal_sync with `source_type:"reponse_ministerielle"`
- [ ] T022 [US3] Extend Task B with Réponses dispatch branch: when `source_type == "reponse_ministerielle"`, `api.request` PISTE /QUESTIONS-REPONSES/{source_id} (OAuth2), inline `db.add/edit REF_reponses_ministerial` all fields explicit, compute `full_text = question_text + " " + reponse_text`
- [ ] T023 [US3] Extend Task B stale-chunk marking for `source_type=="reponse_ministerielle"` (same pattern as T009/T017)
- [ ] T024 [US3] Add 10 unrolled embedding blocks for Réponses in Task B: `db.add REF_legal_chunks {source_type:"reponse_ministerielle", ...}`
- [ ] T025 [US3] Add `build_reponses_features()` and `build_reponses_dataset(chunks)` in `scripts/export_to_hf.py` with Features: chunk_text, embedding, source_id, chunk_index, numero_question, date_reponse, ministere, question_text, url_legifrance
- [ ] T026 [US3] Extend `main()` in `scripts/export_to_hf.py` to fetch, build, and push `reponses_legis` config to `ArthurSrz/open_codes`

**Checkpoint**: US3 complete — all three new source configs now populate nightly

---

## Phase 6: User Story 4 — Unified Nightly Export (Priority: P1)

**Goal**: Pytest suite passes for all 4 configs; GitHub Action exports all 4 in a single run

**Independent Test**: GitHub Action `push-hf-dataset.yml` exits 0 and `ArthurSrz/open_codes` has four configs: `default`, `jurisprudence`, `circulaires`, `reponses_legis`

### Implementation for User Story 4

- [ ] T027 [US4] Add pytest tests in `scripts/tests/test_data_quality.py`: `test_legal_chunks_no_stale_judilibre()`, `test_legal_chunks_no_stale_circulaires()`, `test_legal_chunks_no_stale_reponses()` — assert all exported chunks have `is_stale=false` per source_type
- [ ] T028 [US4] [P] Add pytest tests in `scripts/tests/test_data_quality.py`: `test_legal_chunks_dedup()` — assert no duplicate `(source_type, source_id, chunk_index)` in REF_legal_chunks
- [ ] T029 [US4] [P] Add pytest tests in `scripts/tests/test_data_quality.py`: `test_legal_chunks_embeddings()` — assert all chunks have embedding of length 1024; `test_judilibre_fiche_arret_field_exists()` — assert fiche_arret column exists (nullable ok); `test_circulaires_has_ministere()` — ministere not null; `test_reponses_has_question_text()` — question_text not null
- [ ] T030 [US4] Add empty-source guard in `main()` of `scripts/export_to_hf.py`: if any of the three new source configs returns 0 rows, abort with named error before any push
- [ ] T031 [US4] Merge `requete_textes` branch to `v1` in Xano Workspace 5 to activate scheduled execution of Tasks A1, A2, A3, and B

**Checkpoint**: US4 complete — full four-config nightly pipeline active and validated

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T032 [P] Update `specs/005-multi-legal-sync/checklists/requirements.md` to mark all items complete
- [ ] T033 Update `CLAUDE.md` with new table IDs, endpoint IDs, and task IDs discovered during implementation
- [ ] T034 Update `scripts/README.md` (if exists) or export script docstring with documentation for the three new config functions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (tables must exist first)
- **Phase 3 (US1)**: Depends on Phase 2 — Judilibre pipeline is MVP
- **Phase 4 (US2)**: Depends on Phase 2 — can start in parallel with Phase 3 after Phase 2
- **Phase 5 (US3)**: Depends on Phase 2 — can start in parallel with Phases 3/4 after Phase 2
- **Phase 6 (US4)**: Depends on Phases 3+4+5 all complete
- **Phase 7 (Polish)**: Depends on Phase 6

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependencies on US2/US3
- **US2 (P2)**: Can start after Phase 2 — no dependencies on US1/US3
- **US3 (P3)**: Can start after Phase 2 — no dependencies on US1/US2
- **US4 (P1)**: Depends on US1 + US2 + US3 all producing data

### Parallel Opportunities

- T004, T005, T006 (source tables) can be created in parallel
- T007–T014 (US1), T015–T020 (US2), T021–T026 (US3) can all run in parallel after Phase 2
- T027, T028, T029 (test additions) can run in parallel within Phase 6

---

## Parallel Example: Phases 3, 4, 5

```
After Phase 2 completes:
  Thread A: T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014  (US1)
  Thread B: T015 → T016 → T017 → T018 → T019 → T020                  (US2)
  Thread C: T021 → T022 → T023 → T024 → T025 → T026                  (US3)
Then: Phase 6 (US4) after all three threads complete
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Create shared tables (T001, T002)
2. Complete Phase 2: Environment + source tables (T003–T006)
3. Complete Phase 3: US1 Judilibre pipeline end-to-end (T007–T014)
4. **STOP and VALIDATE**: `load_dataset("ArthurSrz/open_codes", name="jurisprudence")` returns valid rows
5. Proceed to US2/US3 in parallel

### Incremental Delivery

1. Phase 1+2 → Foundation ready
2. Phase 3 (US1) → Jurisprudence config live — **first new dataset available**
3. Phase 4 (US2) → Circulaires config live
4. Phase 5 (US3) → Réponses config live
5. Phase 6 (US4) → Tests pass, all 4 configs in unified nightly export

---

## Notes

- All Xano XanoScript tasks must comply with 7-rule checklist (see plan.md)
- `util.sleep` in Task B must use `value=4` (seconds), never `value=4000`
- `where` compound conditions (`&&`) must be on single line — no line breaks
- `db.add` fields must be inlined — no variable references in `data` block
- `paging` block goes **inside** `return`, not as sibling of `where`/`sort`
- Always read current XanoScript with `include_xanoscript=true` before any `updateTask` call
