# Feature Specification: Legal Sync Pipeline

**Feature Branch**: `003-legal-sync-pipeline`
**Created**: 2026-02-06
**Status**: Final (v2 — Server-Side Queue Pipeline)
**Input**: User description: "Legal Sync Pipeline - A fully autonomous server-side sync system that synchronizes French legal codes from the PISTE Légifrance API into a Xano database with paragraph-aware text chunking and Mistral AI vector embeddings. Uses a queue table + worker pattern to bypass XanoScript foreach limitations."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Initial Sync of Legal Codes (Priority: P1)

As a system administrator, I want to synchronize all 5 priority French legal codes from the official PISTE Légifrance API into the Xano database so that the AI assistant Marianne can perform semantic search over up-to-date legal texts for municipal secretaries.

**Why this priority**: This is the foundational capability. Without legal data imported and embedded, no legal search is possible. The AI assistant Marianne depends entirely on this data to provide accurate legal guidance.

**Independent Test**: Can be fully tested by running `./scripts/sync_all.sh` and verifying that all 5 codes appear in `REF_codes_legifrance` with valid metadata and that corresponding chunks with embeddings exist in `REF_article_chunks`.

**Acceptance Scenarios**:

1. **Given** empty target tables, **When** the sync pipeline runs for the first time, **Then** articles from all 5 configured legal codes are imported into `REF_codes_legifrance` with full metadata (code identifier, article number, status, hierarchical section path, content, content hash)
2. **Given** articles are imported, **When** checking the `REF_article_chunks` table, **Then** each article has one or more chunks with valid 1024-dimensional Mistral embeddings, chunk text, position markers, and full metadata (code, num, etat, fullSectionsTitre)
3. **Given** a sync is running, **When** an error occurs on a specific article (e.g., PISTE API timeout), **Then** the pipeline continues with remaining articles, logs the error, and reports final error count

---

### User Story 2 - Text Chunking for Long Articles (Priority: P1)

As a system administrator, I want long legal articles to be split into semantically coherent chunks so that the full text is embedded and searchable, not just the first 8,000 characters.

**Why this priority**: Many legal articles exceed the 8,000-character embedding limit. Without chunking, significant legal text is lost, degrading search quality for the AI assistant.

**Independent Test**: Can be tested by verifying that articles longer than 8,000 characters have multiple chunks in `REF_article_chunks`, each with valid embeddings, and that chunk positions cover the full article text without gaps.

**Acceptance Scenarios**:

1. **Given** an article with 20,000 characters of content, **When** the pipeline processes it, **Then** it creates 3 chunks (~8,000 chars each) split on paragraph boundaries, each with its own embedding
2. **Given** a short article with 2,000 characters, **When** the pipeline processes it, **Then** it creates exactly 1 chunk covering the full text
3. **Given** chunks exist for an article, **When** checking chunk metadata, **Then** each chunk has `start_position`, `end_position`, `chunk_index`, and the same metadata as the parent article (code, num, etat, fullSectionsTitre)

---

### User Story 3 - Incremental Change Detection (Priority: P2)

As a system administrator, I want the pipeline to detect which articles have changed since the last sync so that only modified articles are re-processed, saving time and API quota.

**Why this priority**: Legal codes are updated regularly. Municipal secretaries need access to the latest article versions. Incremental sync avoids re-processing the entire corpus (~1,630 articles) on each run.

**Independent Test**: Can be tested by running sync twice — first run creates articles, second run detects them as "unchanged" via content hash comparison. Modifying an article's content in the source triggers an "updated" action on next sync.

**Acceptance Scenarios**:

1. **Given** articles already exist in the database with content hashes, **When** the pipeline syncs an article whose content has not changed, **Then** the article is marked "unchanged" and its chunks are not regenerated
2. **Given** an article's content has changed in PISTE (different text), **When** the pipeline syncs, **Then** the article content, hash, and all associated chunks and embeddings are regenerated
3. **Given** a new article appears in a legal code's table of contents, **When** the pipeline syncs, **Then** the article is created with full metadata and chunks

---

### User Story 4 - Sync Monitoring and Progress Reporting (Priority: P3)

As a system administrator, I want to see real-time progress during sync and a final summary report so that I can verify the pipeline is working correctly and troubleshoot issues.

**Why this priority**: Operational visibility helps maintain system health, but the pipeline can function without it initially.

**Independent Test**: Can be tested by running a sync and observing that progress lines appear every 10 articles, and that a final summary with article counts and duration is printed.

**Acceptance Scenarios**:

1. **Given** a sync is in progress, **When** every 10 articles are processed, **Then** a progress line shows: articles processed, created, updated, unchanged, errors, and chunks count
2. **Given** a sync completes, **When** viewing the output, **Then** a summary report shows: total duration, total articles, breakdown by action (created/updated/unchanged/errors), and total chunks embedded
3. **Given** a sync status endpoint exists, **When** querying it, **Then** it returns the current state of the sync pipeline and last sync statistics

---

### Edge Cases

- **PISTE API temporarily unavailable**: The pipeline retries up to 3 times with a 2-second delay between retries. After max retries, the article is counted as an error and the pipeline continues.
- **OAuth2 token handling**: The `sync_one` endpoint performs OAuth inline for each article, so tokens are always fresh. No mid-sync expiration possible.
- **Mistral AI rate limiting**: The pipeline enforces 250ms delay between embedding calls (~4 requests/second) to stay within rate limits.
- **PISTE API rate limiting**: The pipeline enforces 300ms delay between article syncs to respect PISTE rate limits.
- **Article with extremely long text (>8,000 chars)**: The paragraph-aware chunker splits on `\n\n` boundaries, accumulating paragraphs until the next would exceed ~8,000 characters. Each chunk generates an independent embedding.
- **Article with no content (empty text)**: The article is stored but no chunk is created. This is a valid state for certain abrogated articles.
- **Duplicate chunk prevention**: The `embed_chunk` endpoint checks for existing chunks by `article_id + chunk_index` before creating, ensuring idempotent behavior on re-runs.
- **Database NULL comparison limitation**: XanoScript's `== null` comparison does not reliably detect DB NULL values. Data migration uses delete-and-recreate patterns instead of in-place null-check updates.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST synchronize articles from the 5 priority French legal codes via the PISTE Légifrance API: CGCT (LEGITEXT000006070633, 36 articles), Communes (LEGITEXT000006070162, 66 articles), Electoral (LEGITEXT000006070239, 223 articles), Urbanisme (LEGITEXT000006074075, 301 articles), Civil (LEGITEXT000006070721, 1,004 articles)
- **FR-002**: System MUST authenticate with the PISTE API using OAuth2 client_credentials flow, performing authentication inline per-request to avoid token expiration issues
- **FR-003**: System MUST extract article metadata from PISTE responses including: article ID (id_legifrance), article number (num), status (etat), version (versionArticle), multiple versions flag (isMultipleVersions), full hierarchical section path (fullSectionsTitre), and article content (texte)
- **FR-004**: System MUST compute content hashes for change detection, comparing stored hashes against newly fetched content to determine create/update/unchanged status
- **FR-005**: System MUST split article text into chunks of approximately 8,000 characters maximum, using paragraph boundaries (`\n\n`) as split points to preserve semantic coherence
- **FR-006**: System MUST generate 1024-dimensional vector embeddings for each chunk using the Mistral AI embedding API
- **FR-007**: System MUST store article records in `REF_codes_legifrance` with all metadata fields and a truncated embedding for backward compatibility
- **FR-008**: System MUST store chunk records in `REF_article_chunks` with: article_id (FK), id_legifrance, code, num, etat, fullSectionsTitre, chunk_index, chunk_text, start_position, end_position, and 1024-dim embedding
- **FR-009**: System MUST implement idempotent upsert logic — creating new articles/chunks on first sync and detecting unchanged content on subsequent syncs via content hash comparison
- **FR-010**: System MUST enforce rate limiting: 300ms between PISTE API calls and 250ms between Mistral embedding calls
- **FR-011**: System MUST implement retry logic with up to 3 attempts and 2-second delays for transient API failures
- **FR-012**: System MUST use a queue table + worker pattern (QUEUE_sync + sync_worker task) to work around XanoScript's limitation where `function.run` and `api.request` inside `foreach` loops cause silent hanging. *(Updated v2: replaced client-side bash orchestration with server-side queue pipeline)*
- **FR-013**: System MUST report progress every 10 articles and provide a final summary with article/chunk counts and duration
- **FR-014**: System MUST support selective sync of individual codes via `--code TEXTID` parameter and chunk-skip mode via `--skip-chunks` parameter

### Key Entities

- **Legal Article (REF_codes_legifrance)**: A single article from a French legal code, identified by `id_legifrance` (LEGIARTI ID). Contains metadata (code textId, article number, status, hierarchical path, version), full article content, content hash for change detection, and a truncated embedding for backward-compatible search.
- **Article Chunk (REF_article_chunks)**: A segment of a legal article's text, approximately 8,000 characters, split on paragraph boundaries. Contains the chunk text, position markers (start/end), chunk index, parent article reference, duplicated article metadata (code, num, etat, fullSectionsTitre), and a full 1024-dim Mistral embedding for semantic search.
- **Legal Code Reference (LEX_codes_piste)**: Configuration table listing the legal codes to synchronize, identified by PISTE textId. Contains code name and textId mapping.
- **Sync Execution**: A single run of the sync pipeline, tracked by the bash script's output. Reports: duration, total articles per code, breakdown by action (created/updated/unchanged/errors), and total chunks embedded.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 1,630 articles across 5 legal codes are successfully imported — specifically: 36 (CGCT) + 66 (Communes) + 223 (Electoral) + 301 (Urbanisme) + 1,004 (Civil)
- **SC-002**: All articles have corresponding chunks with full metadata — 1,884 total chunks in `REF_article_chunks`, each with populated code, num, etat, fullSectionsTitre, and valid 1024-dim embedding
- **SC-003**: Zero chunks with null metadata fields (code, num, etat) remain in the database after a complete sync
- **SC-004**: Error rate below 1% per code — actual results: 0 errors (CGCT, Communes), 1 error (Electoral, 0.4%), 1 error (Urbanisme, 0.3%), 4 errors (Civil, 0.4%)
- **SC-005**: Incremental re-sync correctly identifies unchanged articles — re-running sync on an already-synced code produces 0 created, 0 updated, and N unchanged
- **SC-006**: Full initial sync of all 5 codes completes within 3 hours — actual measured durations: CGCT ~2min, Communes ~3min, Electoral ~11min, Urbanisme ~14min, Civil ~49min
- **SC-007**: Long articles (>8,000 chars) produce multiple chunks — CGCT averages 2 chunks/article, Electoral averages 2 chunks/article, confirming chunking works for long legal texts

## Architecture Notes

### Server-Side Queue Pipeline (v2 — 2026-02-07)

Fully autonomous Xano-native pipeline. No client involvement. Uses a queue table + worker pattern to bypass XanoScript's `foreach + external call` limitation.

```
2:00 AM ─► sync_populate_queue (Task ID 13, daily)
              │
              ├─ Create sync log (LOG_sync_legifrance, status: EN_COURS)
              ├─ OAuth inline → token
              ├─ For each of 5 codes (explicit sequential blocks, not foreach):
              │   ├─ function.run piste/piste_get_toc → TOC
              │   ├─ function.run piste/piste_extraire_articles_toc → article IDs
              │   └─ foreach (article IDs) { db.add QUEUE_sync (status: pending) }
              └─ Update sync log with total queued count

Every 4s ─► sync_worker (Task ID 14, continuous)
              │
              ├─ db.query QUEUE_sync WHERE status="pending" LIMIT 1
              ├─ If none → no-op (return)
              ├─ Mark "processing"
              ├─ OAuth inline → token
              ├─ function.run piste/piste_get_article → full article
              ├─ function.run utils/hash_contenu_article → hash
              ├─ db.get REF_codes_legifrance → existing check
              ├─ If hash unchanged → mark "unchanged", return
              ├─ function.run utils/parser_fullSectionsTitre → hierarchy
              ├─ Upsert article (db.add or db.edit, data inlined)
              ├─ function.run utils/chunker_texte → chunks array
              ├─ UNROLLED chunk embedding (10 explicit conditional blocks):
              │   if chunk_count >= N: embed + db.add REF_article_chunks + sleep 250ms
              ├─ Mark "done" with chunk count
              └─ On error: mark "error" + log
```

**Key design decisions:**
- **5 explicit code blocks** in populate task (not foreach over codes with function.run — hangs)
- **Unrolled chunk embedding** (10 blocks) instead of foreach + function.run — handles articles up to ~80,000 chars
- **Inline OAuth** per worker run (function.run for auth returns metadata, not response)
- **Inline data objects** in db.add (variable refs cause assign:var syntax error)
- **"Always add, cleanup later"** for chunks — no db.delete in XanoScript
- **Guard pattern** for article_ref_id — declared before conditional, updated in each branch

### Queue Table (QUEUE_sync, ID 126)

| Field | Type | Description |
|-------|------|-------------|
| id | int (PK) | Auto-increment |
| sync_log_id | int (FK) | → LOG_sync_legifrance |
| code_textId | text | PISTE textId |
| article_id_legifrance | text | LEGIARTI ID |
| status | enum | pending / processing / done / unchanged / error |
| error_message | text | Error details |
| chunks_count | int | Chunks embedded |
| created_at | timestamp | Queue insertion time |
| processed_at | timestamp | Worker finish time |

Indexes: btree on `status` (worker polling), `sync_log_id`, `code_textId`.

### Tasks (Xano, branch `requete_textes`)

| Task | ID | Schedule | Purpose |
|------|----|----------|---------|
| `sync_populate_queue` | 13 | Daily 02:00 UTC | Fill QUEUE_sync with article IDs from 5 codes |
| `sync_worker` | 14 | Every 4 seconds | Process 1 article from queue |
| `sync_legifrance_quotidien` | 9 | DEPRECATED | Old task, replaced by above |

### API Endpoints (Xano, branch `requete_textes`)

| Endpoint | ID | Purpose |
|----------|----|---------|
| `sync_status` | 958 | Queue stats + sync logs + article/chunk counts |

### Deprecated Components (v1 — client-side)

The following are superseded by the server-side pipeline:

| Component | ID | Replaced by |
|-----------|----|-------------|
| `scripts/sync_all.sh` | — | `sync_populate_queue` + `sync_worker` |
| `sync_legifrance_quotidien` task | 9 | `sync_populate_queue` + `sync_worker` |
| `piste/piste_orchestrer_sync` function | 81 | `sync_populate_queue` task |
| `piste/piste_sync_code` function | 82 | `sync_worker` task |
| `sync_one` API | 954 | `sync_worker` task |
| `embed_chunk` API | 959 | `sync_worker` task (unrolled inline) |
| `list_article_ids` API | 956 | `sync_populate_queue` task |

### Reused Functions (level-1 calls)

| Function | ID | Called by |
|----------|----|-----------|
| `piste/piste_get_toc` | 77 | sync_populate_queue |
| `piste/piste_extraire_articles_toc` | 80 | sync_populate_queue |
| `piste/piste_get_article` | 68 | sync_worker |
| `utils/hash_contenu_article` | 67 | sync_worker |
| `utils/parser_fullSectionsTitre` | 78 | sync_worker |
| `utils/chunker_texte` | 83 | sync_worker |
| `mistral/mistral_generer_embedding` | 79 | sync_worker (10 unrolled blocks) |

### Known XanoScript Limitations (Documented)

1. `foreach` + `function.run`/`api.request` = silent hang
2. Nested `function.run` (2+ levels deep) = silent hang
3. `function.run` without folder prefix returns metadata, not response
4. `== null` comparison doesn't detect DB NULL values
5. Reserved keywords (`access_token`, `bearer_token`) cause "Access Denied"
6. No `db.delete` statement — use idempotent patterns or Xano MCP tools

## Assumptions

- The PISTE Légifrance API is available and provides real-time data from the official source
- The Mistral AI embedding API is available with sufficient rate limits for sync volumes (~1,884 chunks)
- The Xano workspace (ID 5, branch `requete_textes`) is configured with required environment variables: PISTE_CLIENT_ID, PISTE_CLIENT_SECRET, MISTRAL_API_KEY
- *(v1 only, deprecated)* The bash orchestration script runs on a machine with `curl`, `python3`, and network access to both PISTE and Xano APIs. *(v2: fully server-side, no external client needed)*
- Content hash comparison is sufficient for detecting article changes
- Paragraph-boundary chunking at ~8,000 characters preserves semantic coherence for legal text embedding
- The 5 priority codes represent the immediate needs of municipal secretaries; extension to ~98 codes is planned post-MVP
