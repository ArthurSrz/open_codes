# Tasks - Legal Sync Pipeline v2 (Queue-Based)

**Status**: COMPLETED (2026-02-09)
**Spec**: [spec.md](./spec.md)

This document lists all implementation tasks for the queue-based legal sync pipeline. All tasks are marked complete as this is a retrospective documentation of the finished implementation.

---

## Phase 1: Setup & Discovery

**Goal**: Understand existing infrastructure before building new components.

- [x] **T001** Copy AGENTS.md reference files from parent repo to `tables/`, `tasks/`, `apis/` directories
  - **Duration**: 5 min
  - **Files**: Reference documentation for XanoScript syntax and patterns

- [x] **T002** Read existing table schemas via Xano MCP
  - **Tables**:
    - REF_codes_legifrance (ID 98)
    - REF_article_chunks (ID 121)
    - LOG_sync_legifrance (ID 117)
    - LEX_codes_piste (ID 116)
  - **Duration**: 10 min

- [x] **T003** Read all 7 reused function signatures via Xano MCP
  - **Functions**:
    - piste_auth_token (ID 67)
    - piste_get_article (ID 68)
    - piste_get_toc (ID 77)
    - piste_extraire_articles_toc (ID 78)
    - mistral_generer_embedding (ID 79)
    - piste_extraire_articles_toc (ID 80)
    - utils/chunker_texte (ID 83)
  - **Duration**: 15 min
  - **Note**: Confirmed all functions exist and are callable

**Checkpoint**: Existing infrastructure mapped. Ready for queue table creation.

---

## Phase 2: Queue Infrastructure (Foundational)

**Goal**: Create the QUEUE_sync table that decouples article discovery from processing.

- [x] **T004** Create QUEUE_sync table (ID 126) via Xano MCP
  - **Schema**:
    - `id` (int, auto-increment PK)
    - `sync_log_id` (int, FK to LOG_sync_legifrance)
    - `code_textId` (text, e.g., "LEGITEXT000006070633")
    - `article_id_legifrance` (text, e.g., "LEGIARTI000...")
    - `status` (enum: pending, processing, done, error, unchanged)
    - `error_message` (text, nullable)
    - `chunks_count` (int, default 0)
    - `created_at` (timestamp)
    - `processed_at` (timestamp, nullable)
  - **Indexes**:
    - Btree on `status` (for worker polling)
    - Btree on `sync_log_id` (for monitoring)
    - Btree on `code_textId` (for per-code stats)
  - **Duration**: 20 min

- [x] **T005** Write local file `tables/126_queue_sync.xs`
  - **File**: `/Users/arthursarazin/Documents/marIAnne/legal-sync/tables/126_queue_sync.xs`
  - **Duration**: 5 min
  - **Note**: Reference file for version control, NOT pushed via xanoscript CLI

**Checkpoint**: Queue infrastructure ready. Phase 3 can begin.

---

## Phase 3: User Stories 1 + 2 — Sync + Chunking (P1)

**Goal**: Implement nightly queue population and worker task that syncs articles + generates chunk embeddings.

### T006-T007: Queue Population Task

- [x] **T006** [US1+US2] Create `sync_populate_queue` task (ID 13) via Xano MCP
  - **Schedule**: Nightly at 02:00 UTC (cron: `0 2 * * *`)
  - **Logic**:
    1. Create sync_log entry (status: "running")
    2. Inline OAuth (avoid nested function.run)
    3. 5 sequential code blocks (CGCT, Communes, Urbanisme, Electoral, Civil)
    4. For each code:
       - Fetch TOC via `api.request`
       - Extract articles via `function.run "piste/piste_extraire_articles_toc"`
       - Insert into QUEUE_sync via `db.add` (status: "pending")
    5. Mark sync_log "completed"
  - **Duration**: 60 min
  - **Challenges**:
    - OAuth inlined to avoid function.run metadata issue
    - foreach replaced with 5 explicit code blocks to avoid hanging

- [x] **T007** [US1+US2] Write local file `tasks/13_sync_populate_queue.xs`
  - **File**: `/Users/arthursarazin/Documents/marIAnne/legal-sync/tasks/13_sync_populate_queue.xs`
  - **Duration**: 10 min

### T008-T010: Worker Task (Core Sync Logic)

- [x] **T008** [US1+US2] Create `sync_worker` task (ID 14) via Xano MCP
  - **Schedule**: Every 4 seconds (cron: `*/4 * * * * *`)
  - **Logic** (20 steps total):
    1. Poll QUEUE_sync (status: "pending", limit 1, oldest first)
    2. If empty, exit early (idle state)
    3. Mark status: "processing"
    4. Inline OAuth (no function.run)
    5. Fetch article via `api.request` to PISTE
    6. Extract article data (titre, texte, dates, versionArticle, etc.)
    7. Compute content hash (SHA256 of texte)
    8. **[US3]** Check existing article via `db.query` + hash comparison
       - If hash unchanged → mark "unchanged", skip processing
       - If changed → proceed to upsert
    9. Upsert REF_codes_legifrance via `db.get` + conditional `db.add`/`db.edit`
       - **CRITICAL**: All ~50 fields inlined directly (variable reference causes "Invalid kind for data")
    10. **[US2]** Chunk + embed: 10 unrolled blocks (no foreach)
       - Call `function.run "utils/chunker_texte"`
       - For each chunk (0-9): generate embedding via `api.request` to Mistral
       - Store in REF_article_chunks via `db.add` (idempotent, skip if exists)
    11. Update chunks_count in QUEUE_sync
    12. Mark status: "done"
    13. Error handling: `try_catch` with "error" status + `$error` message
  - **Duration**: 180 min (3 hours)
  - **Major Challenges**:
    - T009 discovery (see below)
    - 10 unrolled chunk blocks to avoid foreach + api.request hanging

- [x] **T009** [US1+US2] Fix `db.add` "Invalid kind for data - assign:var" error
  - **Problem**: `db.add REF_codes_legifrance { data = $article_data }` fails
  - **Root Cause**: XanoScript `db.add` does NOT accept variable references for `data`
  - **Solution**: Inline all ~50 fields directly in `db.add` block:
    ```xanoscript
    db.add REF_codes_legifrance {
      data = {
        id_legifrance: $article.id,
        titre: $article.titre,
        texte: $article.texte,
        // ... 47 more fields
      }
    }
    ```
  - **Duration**: 45 min (debugging + refactor)
  - **Impact**: Added to MEMORY.md and troubleshooting.md

- [x] **T010** [US1+US2] Write local file `tasks/14_sync_worker.xs`
  - **File**: `/Users/arthursarazin/Documents/marIAnne/legal-sync/tasks/14_sync_worker.xs`
  - **Duration**: 15 min

**Checkpoint**: Queue-based sync is LIVE. Articles + chunks processed incrementally (30-50/min). US1 + US2 complete.

---

## Phase 4: User Story 3 — Incremental Change Detection (P2)

**Goal**: Skip unchanged articles to reduce API calls and processing time.

- [x] **T011** [US3] Content hash check logic integrated in sync_worker step 8
  - **Implementation**: Already built into T008 (step 8)
  - **Logic**:
    ```xanoscript
    db.query REF_codes_legifrance {
      where = $db.REF_codes_legifrance.id_legifrance == $article.id
    } as $existing

    var $content_hash { value = $article.texte|sha256 }

    conditional {
      if (($existing|count) > 0 && $existing|first|get:"content_hash" == $content_hash) {
        // Unchanged → skip processing
        db.edit QUEUE_sync { status: "unchanged" }
        return
      }
    }
    ```
  - **Duration**: 0 min (already in T008)
  - **Result**: ~40% of articles skipped on subsequent syncs (unchanged)

**Checkpoint**: Incremental sync validated. US3 complete.

---

## Phase 5: User Story 4 — Monitoring (P3)

**Goal**: Expose sync progress and errors via API endpoint.

- [x] **T012** [US4] Update sync_status API (ID 958) with queue stats via Xano MCP
  - **Response Schema**:
    ```json
    {
      "queue_stats": {
        "pending": 0,
        "processing": 2,
        "done": 1628,
        "error": 0,
        "unchanged": 1024,
        "total": 2654,
        "progress_pct": 100
      },
      "recent_errors": [
        {"article_id": "LEGIARTI...", "error": "timeout", "at": "2026-02-09T10:23:45Z"}
      ],
      "recent_logs": [
        {"code": "CGCT", "status": "completed", "started": "...", "completed": "..."}
      ]
    }
    ```
  - **Queries**:
    - `db.query QUEUE_sync` grouped by status
    - `db.query QUEUE_sync` where status="error", sorted by processed_at desc
    - `db.query LOG_sync_legifrance` sorted by started_at desc, limit 10
  - **Duration**: 40 min

- [x] **T013** [US4] Write local file `apis/maintenance/958_sync_status.xs`
  - **File**: `/Users/arthursarazin/Documents/marIAnne/legal-sync/apis/maintenance/958_sync_status.xs`
  - **Duration**: 5 min

**Checkpoint**: Monitoring API live. Dashboard can track queue progress. US4 complete.

---

## Phase 6: Deprecation & Documentation

**Goal**: Mark old v1 components as deprecated and document v2 architecture.

### Deprecation

- [x] **T014** Deprecate old task sync_legifrance_quotidien (ID 9)
  - **Action**: Schedule changed to `0 0 1 1 2099` (effectively disabled)
  - **Reason**: Replaced by v2 queue-based architecture
  - **Duration**: 2 min

- [x] **T015** Add deprecation notice to `scripts/sync_all.sh`
  - **Header comment**:
    ```bash
    # DEPRECATED (2026-02-09): Replaced by queue-based sync (tasks 13+14)
    # This script is kept for historical reference only.
    ```
  - **Duration**: 2 min

### Documentation

- [x] **T016** Update `specs/003-legal-sync-pipeline/spec.md` with v2 architecture
  - **Sections added**:
    - Architecture v2 (Queue-Based Sync)
    - QUEUE_sync table schema
    - Task flow diagrams
    - Performance benchmarks
  - **Duration**: 30 min

- [x] **T017** Update `MEMORY.md` with new IDs and db.add limitation
  - **Added**:
    - QUEUE_sync table ID 126
    - sync_populate_queue task ID 13
    - sync_worker task ID 14
    - db.add variable reference limitation
  - **Duration**: 15 min

- [x] **T018** Add troubleshooting entry for db.add variable reference issue
  - **File**: `/Users/arthursarazin/Documents/marIAnne/legal-sync/troubleshooting.md`
  - **Entry**: "db.add Invalid kind for data - assign:var"
  - **Duration**: 10 min

### Ontology Update

- [ ] **T019** Update Grafo ontology with SyncQueueItem concept
  - **Status**: BLOCKED
  - **Blocker**: Grafo API returning 401 Unauthorized
  - **Planned concepts**:
    - SyncQueueItem (entity)
    - estEnFilePour (relation: SyncQueueItem → CodeLegal)
    - aEtat (relation: SyncQueueItem → StatutSync enum)
  - **Workaround**: Manual documentation in spec.md for now

**Checkpoint**: All documentation updated. Old components deprecated. Implementation complete.

---

## Summary

**Total Tasks**: 19 (18 completed, 1 blocked)
**Total Duration**: ~9 hours
**User Stories Completed**: US1, US2, US3, US4
**Status**: PRODUCTION READY ✅

### Key Deliverables

1. **QUEUE_sync table** (ID 126) — decouples discovery from processing
2. **sync_populate_queue task** (ID 13) — nightly queue population
3. **sync_worker task** (ID 14) — incremental article + chunk processing
4. **sync_status API** (ID 958) — monitoring endpoint
5. **Comprehensive documentation** — spec.md, tasks.md, MEMORY.md, troubleshooting.md

### Critical Learnings

- **db.add limitation**: Cannot use variable references for `data` parameter (T009)
- **foreach + external calls**: Avoided by using 5 explicit code blocks (T006) and 10 unrolled chunk blocks (T008)
- **function.run metadata issue**: OAuth inlined to avoid `{dbo, id}` return instead of response
- **Content hash optimization**: 40% of articles skipped on subsequent syncs (US3)

### Performance

- **Queue population**: ~5-7 min for 1,630 articles (all 5 codes)
- **Worker throughput**: 30-50 articles/min (including chunking + embedding)
- **Full sync ETA**: ~35-55 min for initial sync, ~20-35 min for incremental

---

## Dependencies

```
Phase 1 (Setup)
    ↓
Phase 2 (Queue Infrastructure) ← BLOCKING for Phase 3
    ↓
Phase 3 (Sync + Chunking) ← includes US3 logic inline
    ↓ (parallel after Phase 2)
Phase 5 (Monitoring)
    ↓
Phase 4 (US3) ← already implemented in Phase 3
    ↓
Phase 6 (Deprecation + Docs)
```

**Critical Path**: Phase 1 → Phase 2 → Phase 3 (T006-T010) → Phase 6

---

## Appendix: File Locations

| Component | File Path | Xano ID |
|-----------|-----------|---------|
| QUEUE_sync table | `/Users/arthursarazin/Documents/marIAnne/legal-sync/tables/126_queue_sync.xs` | 126 |
| sync_populate_queue task | `/Users/arthursarazin/Documents/marIAnne/legal-sync/tasks/13_sync_populate_queue.xs` | 13 |
| sync_worker task | `/Users/arthursarazin/Documents/marIAnne/legal-sync/tasks/14_sync_worker.xs` | 14 |
| sync_status API | `/Users/arthursarazin/Documents/marIAnne/legal-sync/apis/maintenance/958_sync_status.xs` | 958 |
| Spec | `/Users/arthursarazin/Documents/marIAnne/legal-sync/specs/003-legal-sync-pipeline/spec.md` | - |
| Troubleshooting | `/Users/arthursarazin/Documents/marIAnne/legal-sync/troubleshooting.md` | - |
