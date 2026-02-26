# Tasks: Pipeline Sync Légifrance PISTE

**Input**: Design documents from `/specs/001-legalkit-vector-sync/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Non demandés explicitement - pas de tâches de test générées.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions (Xano/XanoScript)

- **Tables**: `tables/` at repository root
- **Functions**: `functions/` with subdirectories by domain
- **Tasks**: `tasks/` at repository root
- **APIs**: `apis/{group}/` at repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project structure initialization

- [x] T001 Create directory structure `functions/piste/` for PISTE API functions
- [x] T002 Create directory structure `functions/utils/` for utility functions
- [x] T003 [P] Create directory structure `apis/maintenance/` if not exists

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Tables and utility functions that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tables (Schema)

- [x] T004 Extend table schema with 30 new columns in `tables/98_ref_codes_legifrance.xs` per data-model.md (identification, hiérarchie, contenu, temporalité, statut, versioning, métadonnées, sync fields)
- [x] T005 [P] Create table LEX_codes_piste in `tables/116_lex_codes_piste.xs` per data-model.md (textId, titre, slug, actif, priorite, nb_articles, derniere_sync)
- [x] T006 [P] Create table LOG_sync_legifrance in `tables/117_log_sync_legifrance.xs` per data-model.md (statut, articles_traites/crees/maj/erreur, embeddings_generes, erreur_message, duree_secondes)

### Utility Functions

- [x] T007 [P] Create function hash_contenu_article in `functions/utils/hash_contenu_article.xs` - SHA256 hash of (fullSectionsTitre + surtitre + texte) for change detection
- [x] T008 [P] Create function parser_fullSectionsTitre in `functions/utils/parser_fullSectionsTitre.xs` - parse hierarchical path into partie/livre/titre/chapitre/section/sous_section/paragraphe columns
- [x] T009 [P] Verify or create function mistral_generer_embedding in `functions/mistral/mistral_generer_embedding.xs` - POST to Mistral API with truncation at 8000 tokens, return 1024-dim vector

### Configuration

- [ ] T010 Configure environment variables in Xano settings: `PISTE_OAUTH_ID`, `PISTE_OAUTH_SECRET` (values from research.md)

**Checkpoint**: Foundation ready - Tables deployed, utilities available, env configured

---

## Phase 3: User Story 1 - Import initial des codes juridiques (Priority: P1) 🎯 MVP

**Goal**: Importer tous les codes juridiques français depuis l'API PISTE vers Xano avec embeddings Mistral AI pour recherche sémantique.

**Independent Test**: Déclencher une tâche d'import et vérifier que les articles d'au moins un code (ex: Code des collectivités territoriales) apparaissent dans REF_codes_legifrance avec embeddings valides 1024-dim.

### PISTE API Functions

- [x] T011 [US1] Create function piste_auth_token in `functions/piste/piste_auth_token.xs` - OAuth2 client_credentials flow to `https://oauth.piste.gouv.fr/api/oauth/token`, handle 401 errors, retry 3x with backoff on 5xx
- [x] T012 [US1] Create function piste_get_toc in `functions/piste/piste_get_toc.xs` - POST to `/tableMatieres` endpoint with textId and date, return sections structure
- [x] T013 [US1] Create function piste_get_article in `functions/piste/piste_get_article.xs` - POST to `/getArticle` endpoint with article_id, return all 38 fields
- [x] T014 [US1] Create function piste_extraire_articles_toc in `functions/piste/piste_extraire_articles_toc.xs` - recursive extraction of all article IDs from TOC sections, return list with id/num/section_path
- [x] T015 [US1] Create function piste_sync_code in `functions/piste/piste_sync_code.xs` - sync single code: get TOC → extract articles → for each (batch 50): get article → compute hash → check existence → generate embedding if new/changed → INSERT/UPDATE, implement rate limiting (10 req/s PISTE, 5 req/s Mistral)
- [x] T016 [US1] Create function piste_orchestrer_sync in `functions/piste/piste_orchestrer_sync.xs` - create LOG entry → iterate LEX_codes_piste WHERE actif=true ORDER BY priorite → call piste_sync_code for each → update LOG with final stats

### Initial Data

- [ ] T017 [US1] Populate LEX_codes_piste with 5 priority codes via Xano admin: Code des collectivités territoriales (LEGITEXT000006070633, priorite=0), Code des communes (LEGITEXT000006070162, priorite=1), Code électoral (LEGITEXT000006070239, priorite=2), Code de l'urbanisme (LEGITEXT000006074075, priorite=3), Code civil (LEGITEXT000006070721, priorite=4)

### Validation

- [ ] T018 [US1] Test initial sync: manually trigger piste_orchestrer_sync for one code (LEGITEXT000006070633), verify articles appear in REF_codes_legifrance with embeddings != NULL and content_hash populated

**Checkpoint**: User Story 1 complete - Full import capability functional, articles searchable via vector similarity

---

## Phase 4: User Story 2 - Mises à jour incrémentales quotidiennes (Priority: P2)

**Goal**: Synchronisation automatique quotidienne détectant uniquement les articles modifiés/nouveaux via comparaison de hash.

**Independent Test**: Modifier manuellement le contenu d'un article dans REF_codes_legifrance (changer content_hash), relancer sync, vérifier que seul cet article est mis à jour.

### Scheduled Task

- [x] T019 [US2] Create task sync_legifrance_quotidien in `tasks/8_sync_legifrance_quotidien.xs` - schedule daily at 02:00 UTC, call piste_orchestrer_sync with force_full=false

### Incremental Logic Verification

- [ ] T020 [US2] Verify piste_sync_code handles incremental updates: check hash comparison logic, ensure articles with unchanged hash are skipped, ensure articles with etat="ABROGE" are marked inactive

### Validation

- [ ] T021 [US2] Test incremental sync: run sync twice, verify second run processes only changed/new articles (check LOG_sync_legifrance.articles_maj vs articles_crees)

**Checkpoint**: User Story 2 complete - Daily automated sync operational with incremental detection

---

## Phase 5: User Story 3 - Monitoring et Statut de Synchronisation (Priority: P3)

**Goal**: APIs REST pour surveiller la progression des syncs et consulter l'historique.

**Independent Test**: Lancer une sync via API, interroger le statut pendant l'exécution, vérifier que la progression est visible, puis consulter l'historique après complétion.

### API Endpoints

- [x] T022 [P] [US3] Create API endpoint in `apis/maintenance/920_sync_legifrance_lancer_POST.xs` - auth=utilisateurs, input: code_textId (optional), force_full (bool), create LOG entry, call piste_orchestrer_sync async, return sync_id
- [x] T023 [P] [US3] Create API endpoint in `apis/maintenance/921_sync_legifrance_statut_GET.xs` - auth=utilisateurs, input: sync_id (optional, default=latest), return LOG entry with progression (articles_traites, statut, erreur_message)
- [x] T024 [P] [US3] Create API endpoint in `apis/maintenance/922_sync_legifrance_historique_GET.xs` - auth=utilisateurs, input: limit (default=10), offset (default=0), return list of LOG entries ordered by debut_sync DESC

### Validation

- [ ] T025 [US3] Test monitoring APIs: POST to lancer → GET statut repeatedly → verify progression updates → GET historique → verify sync appears in history with correct stats

**Checkpoint**: User Story 3 complete - Full observability via REST APIs

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [x] T026 [P] Update troubleshooting.md if any issues encountered during implementation
- [ ] T027 Run quickstart.md validation: test PISTE OAuth with curl, test article retrieval, verify full pipeline
- [ ] T028 Verify all indexes created on REF_codes_legifrance (idEli, etat, cid, id_legifrance, code)
- [ ] T029 Final sync validation: trigger full sync of all 7 priority codes, verify CS-003 (99.5% embeddings valid)

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (Foundational) ◄── BLOCKS ALL USER STORIES
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
Phase 3 (US1)  Phase 4 (US2)  Phase 5 (US3)
   P1 MVP       depends on      independent
                US1 functions
    │              │              │
    └──────────────┴──────────────┘
                   │
                   ▼
            Phase 6 (Polish)
```

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on Phase 2 (Foundational) - Can start immediately after foundation
- **User Story 2 (P2)**: Depends on US1 functions (piste_sync_code, piste_orchestrer_sync) being complete
- **User Story 3 (P3)**: Depends on Phase 2 only - Can run in parallel with US1/US2

### Within Each User Story

1. PISTE functions in order: auth_token → get_toc → get_article → extraire_articles_toc → sync_code → orchestrer_sync
2. Data population after functions
3. Validation after implementation

### Parallel Opportunities

**Phase 2 (Foundational)**:
```bash
# Tables can be created in parallel:
Task: T004 - REF_codes_legifrance extension
Task: T005 - LEX_codes_piste
Task: T006 - LOG_sync_legifrance

# Utility functions can be created in parallel:
Task: T007 - hash_contenu_article
Task: T008 - parser_fullSectionsTitre
Task: T009 - mistral_generer_embedding
```

**Phase 5 (US3)**:
```bash
# All 3 API endpoints can be created in parallel:
Task: T022 - 920_sync_legifrance_lancer_POST
Task: T023 - 921_sync_legifrance_statut_GET
Task: T024 - 922_sync_legifrance_historique_GET
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (3 tasks)
2. Complete Phase 2: Foundational (7 tasks) - **CRITICAL GATE**
3. Complete Phase 3: User Story 1 (8 tasks)
4. **STOP and VALIDATE**: Test import with 1 code
5. Deploy if ready - Marianne can now search legal articles!

### Incremental Delivery

1. Setup + Foundational → Foundation ready (~10 tasks)
2. Add User Story 1 → Test independently → **MVP deployed** (8 tasks)
3. Add User Story 2 → Automated daily sync (3 tasks)
4. Add User Story 3 → Monitoring APIs (4 tasks)
5. Polish → Production ready (4 tasks)

### Parallel Team Strategy

With multiple developers after Phase 2:
- Developer A: User Story 1 (PISTE functions)
- Developer B: User Story 3 (Monitoring APIs) - can start immediately
- Developer C: User Story 2 (after US1 functions done)

---

## Summary

| Phase | Tasks | Parallel | Story |
|-------|-------|----------|-------|
| Phase 1: Setup | 3 | 1 | - |
| Phase 2: Foundational | 7 | 5 | - |
| Phase 3: US1 Import | 8 | 0 | P1 MVP |
| Phase 4: US2 Incrémental | 3 | 0 | P2 |
| Phase 5: US3 Monitoring | 4 | 3 | P3 |
| Phase 6: Polish | 4 | 1 | - |
| **Total** | **29** | **10** | - |

---

## Notes

- [P] tasks = different files, no dependencies within phase
- XanoScript specifics: use `external.request` for HTTP calls, `db.query` for DB operations
- Agent delegation: Xano Table Designer for tables, Xano Function Writer for functions, Xano API Query Writer for endpoints, Xano Task Writer for scheduled tasks
- Commit after each task completion
- Push to Xano backend after each phase with `#tool:xano.xanoscript/push_all_changes_to_xano`
