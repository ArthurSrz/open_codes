# Plan: Legal Sync Pipeline (Feature 003)

## Summary

This is a **retrospective plan** documenting the completed implementation of the legal sync pipeline. The system autonomously syncs French legal codes from the PISTE Légifrance API into Xano's database with chunking and Mistral AI embeddings for semantic search.

**Implementation Status**: ✅ Complete (2026-02-06)

**Key Characteristics**:
- Fully server-side autonomous operation
- Queue + Worker architecture pattern
- Processes ~1,630 legal articles across 5 codes
- Generates ~1,884 text chunks with embeddings
- Runs nightly with 4-second worker polling
- No client-side orchestration required

## Technical Context

### Platform & Language
- **Language**: XanoScript (Xano platform)
- **Branch**: `requete_textes`
- **Workspace ID**: 5 (MARiaNNE)

### Dependencies
- **PISTE Légifrance API**: OAuth2 authentication, TOC/article fetching
- **Mistral AI Embedding API**: `mistral-embed` model (1024-dim vectors)
- **Xano MCP**: Database operations, task scheduling

### Storage
- **REF_codes_legifrance** (Table ID 98): Main articles with truncated embeddings
- **REF_article_chunks** (Table ID 121): Chunked segments with individual embeddings
- **QUEUE_sync** (Table ID 126): Processing queue with status tracking
- **LOG_sync_legifrance** (Table ID 119): Execution audit trail

### Testing Approach
- Manual testing via Xano Run & Debug interface
- Monitoring via `sync_status` API endpoint (ID 958)
- Production validation through nightly execution logs

### Performance Targets
- **Volume**: ~1,630 articles, ~1,884 chunks
- **Duration**: Complete within 3-hour nightly window
- **Worker Interval**: 4-second polling (prevents API rate limits)
- **Throughput**: ~136 articles/hour with rate limiting

### Critical XanoScript Constraints

These platform limitations shaped the architecture:

1. **foreach + External Calls = Silent Hang**
   - `foreach` loops with `function.run` or `api.request` cause indefinite hanging
   - No error messages, complete silence in logs
   - Forced unrolling of 10 embedding blocks

2. **Nested function.run (2+ levels) = Silent Hang**
   - Cannot call Function A that calls Function B
   - Required flattening of all logic to single level
   - OAuth must be inlined, not extracted to helper function

3. **db.add Rejects Variable References**
   - Cannot pass variable for `data = $my_object`
   - Must inline all field mappings (resulted in ~50 duplicated field lines)

4. **No db.delete Statement**
   - Only `db.get`, `db.add`, `db.edit`, `db.query` exist
   - Used "always add, cleanup later" pattern for chunks

5. **No Early Returns**
   - `response = ...` only valid at function end
   - Required guard flag pattern with try-catch

### Scale & Scope

**Legal Codes Synchronized**:
1. Code Général des Collectivités Territoriales (CGCT) - textId: 36
2. Code des Communes - textId: 66
3. Code de l'Urbanisme - textId: 301
4. Code Électoral - textId: 223
5. Code Civil - textId: 1004

**Processing Statistics** (as of implementation):
- Total articles: ~1,630
- Total chunks: ~1,884
- Average chunks per article: 1.16
- Maximum chunk size: ~8,000 characters
- Embedding dimensions: 1024

## Constitution Compliance Check

### Principle I: Données-Centrée (Data-Centric Architecture)

**Status**: ✅ Compliant

Legal reference data uses `LEX_*` and `REF_*` table prefixes, explicitly exempt from commune scoping per constitution Article I.3. Legal codes are shared reference data across all communes.

**Tables**:
- `REF_codes_legifrance` - Shared legal articles
- `REF_article_chunks` - Shared legal text segments
- `QUEUE_sync` - Infrastructure (not user data)
- `LOG_sync_legifrance` - Infrastructure audit trail

### Principle II: IA/LLM Premier (AI-First Development)

**Status**: ✅ Compliant

Mistral AI embeddings enable semantic similarity search for legal articles. Embeddings are used for retrieval, not reformulation, preserving legal text integrity.

**Implementation**:
- Model: `mistral-embed` (1024 dimensions)
- Usage: Vector similarity search via cosine distance
- Preservation: Original legal text stored alongside embeddings
- Chunking: Paragraph-aware splitting preserves semantic units

### Principle III: Sécurité & Souveraineté (Security & Sovereignty)

**Status**: ✅ Compliant (with documented exception)

**Documented Violation**:
- `sync_status` endpoint (ID 958) has NO authentication
- **Why Needed**: Operational monitoring by automated tools
- **Mitigation**: Returns only queue statistics, no user data
- **Simpler Alternative Rejected**: Adding auth blocks automated ops tooling

**Sovereignty Compliance**:
- All processing server-side within Xano
- No client-side dependencies
- PISTE API is French government service
- Mistral AI is European provider

### Principle IV: Contrat API Clair (Clear API Contracts)

**Status**: ✅ Compliant

**sync_status Endpoint**:
- Path: `/maintenance/sync_status`
- Method: GET
- Response: `{total, pending, processing, completed, error, last_sync}`
- Naming: Follows `<domain>_<action>` convention

### Principle V: Observabilité (Observability)

**Status**: ✅ Compliant

**Logging Architecture**:
1. **LOG_sync_legifrance** (Table 119): High-level sync execution tracking
   - Records: Sync start/end timestamps, total articles queued, status
2. **QUEUE_sync** (Table 126): Per-article processing status
   - Records: Article ID, status, attempt count, error messages, timestamps
3. **debug.log statements**: Throughout task execution for real-time monitoring

**Metrics Available**:
- Queue depth via `sync_status` endpoint
- Processing rate via timestamp deltas
- Error rate via status field aggregation
- Execution history via LOG table queries

## Complexity Tracking

### Documented Deviations from Best Practices

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| No auth on `sync_status` (Principle III) | Operational monitoring endpoint for automated tools | Adding auth would require credential management in ops scripts, blocking real-time monitoring |
| 10 unrolled embedding blocks (DRY violation) | `foreach` + `function.run` causes silent platform hang | XanoScript engine deadlock with nested external calls - no workaround exists |
| Inline data objects in `db.add` (~50 fields duplicated) | `db.add` parser rejects variable references in `data` parameter | XanoScript syntax limitation - cannot pass `data = $article_obj` |
| 5 explicit code sync blocks (no loop) | Looping over codes array with `function.run` for TOC fetch hangs | Same foreach + external call platform limitation |
| Inline OAuth in worker (duplicated) | Helper function would create 2-level nesting (worker → helper) which hangs | Nested `function.run` hangs silently - must flatten to single level |
| "Always add, cleanup later" for chunks | No `db.delete` statement in XanoScript | Only `db.get`, `db.add`, `db.edit`, `db.query` exist - deletion requires MCP tool |
| Guard pattern with try-catch everywhere | No early returns in XanoScript | `response = ...` only valid at function end - cannot return from conditional blocks |

**Complexity Score**: 7 major deviations, all forced by platform constraints, not design choices.

## Project Structure

```text
legal-sync/
│
├── specs/003-legal-sync-pipeline/
│   ├── spec.md                        # Feature specification (v2 — server-side queue)
│   ├── plan.md                        # This retrospective plan
│   └── tasks.md                       # Task breakdown with completion status
│
├── tables/
│   └── 126_queue_sync.xs              # QUEUE_sync: Processing queue with status tracking
│
├── tasks/
│   ├── 13_sync_populate_queue.xs      # Nightly queue populator (02:00 UTC)
│   └── 14_sync_worker.xs              # Article processor (every 4 seconds)
│
├── apis/maintenance/
│   └── 958_sync_status.xs             # Queue monitoring endpoint (GET, no auth)
│
├── functions/ (reused from existing codebase)
│   ├── piste/
│   │   ├── piste_get_toc.xs           # Function ID 77: Fetch table of contents
│   │   ├── piste_extraire_articles_toc.xs  # ID 80: Extract article refs from TOC
│   │   └── piste_get_article.xs       # ID 68: Fetch single article details
│   ├── utils/
│   │   ├── hash_contenu_article.xs    # ID 67: SHA256 hash for change detection
│   │   ├── parser_fullSectionsTitre.xs # ID 78: Parse legal section hierarchy
│   │   └── chunker_texte.xs           # ID 83: Paragraph-aware text splitting (~8000 chars)
│   └── mistral/
│       └── mistral_generer_embedding.xs # ID 79: Generate 1024-dim embeddings
│
└── scripts/ (deprecated)
    └── sync_all.sh                     # DEPRECATED (v1 client-side orchestration)
```

## Architecture

### Overview

The system uses a **Queue + Worker** pattern to work around XanoScript's foreach limitations while maintaining autonomous server-side operation.

```
┌─────────────────────────────────────────────────────────────────┐
│                    sync_populate_queue (Task 13)                │
│                     Runs: Daily at 02:00 UTC                    │
│                                                                  │
│  1. Create LOG_sync_legifrance entry (sync_debut timestamp)    │
│  2. Inline OAuth (PISTE API authentication)                     │
│  3. For each of 5 codes (explicit sequential blocks):          │
│     - function.run "piste/piste_get_toc"                       │
│     - function.run "piste/piste_extraire_articles_toc"         │
│     - foreach article_ref in extracted_articles {              │
│         db.add QUEUE_sync {                                     │
│           code_legifrance_id, id_legifrance, textId,           │
│           status: "pending", priorite: 5                        │
│         }                                                        │
│       }                                                          │
│  4. Update LOG entry (sync_fin, nb_articles_synchronises)      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Creates queue items
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       QUEUE_sync (Table 126)                    │
│                                                                  │
│  Fields: id, code_legifrance_id, id_legifrance, textId,        │
│          status, priorite, tentatives, erreur_message,          │
│          cree_le, modifie_le, traite_le                        │
│                                                                  │
│  Status values: pending | processing | completed | error       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Polled every 4 seconds
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     sync_worker (Task 14)                       │
│                   Runs: Every 4 seconds                         │
│                                                                  │
│  1. db.query QUEUE_sync (status = pending, limit 1, priority)  │
│  2. If no work: response = {status: "idle"}, exit early        │
│  3. Mark item as "processing" (db.edit)                        │
│  4. Inline OAuth (PISTE API authentication)                     │
│  5. function.run "piste/piste_get_article"                     │
│  6. function.run "utils/hash_contenu_article"                  │
│  7. Check if article exists + hash changed (db.get)            │
│  8. Upsert article in REF_codes_legifrance (db.add or db.edit)│
│  9. UNROLLED: 10 explicit embedding blocks (chunk 0-9):        │
│     - function.run "utils/chunker_texte" (get specific index)  │
│     - function.run "mistral/mistral_generer_embedding"         │
│     - db.add REF_article_chunks (always add, cleanup later)    │
│ 10. Mark queue item as "completed" (db.edit)                   │
│ 11. Catch errors: mark as "error", increment tentatives        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Stores results
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              REF_codes_legifrance (Table 98)                    │
│  Main article records with metadata + truncated embedding      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ One-to-many
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              REF_article_chunks (Table 121)                     │
│  Individual text chunks (~8000 chars) with embeddings          │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

#### 1. Queue Pattern to Avoid foreach + function.run

**Problem**: XanoScript's foreach loops with `function.run` cause silent indefinite hanging.

**Solution**:
- Populate task creates queue items with simple `db.add` (no external calls inside foreach)
- Worker task polls queue, processes one item at a time
- No loops with external calls anywhere in the pipeline

#### 2. Five Explicit Code Sync Blocks

**Problem**: Looping over array of code IDs with `function.run` inside foreach hangs.

**Implementation** in `sync_populate_queue`:
```xanoscript
// Block 1: CGCT (textId: 36)
function.run "piste/piste_get_toc" { input = {textId: "36"} } as $toc_cgct
function.run "piste/piste_extraire_articles_toc" { input = {...} } as $articles_cgct
foreach ($articles_cgct.articles) {
  each as $article_ref {
    db.add QUEUE_sync { data = {...} }  // No external calls in loop
  }
}

// Block 2: Code des Communes (textId: 66)
// ... identical structure

// Blocks 3-5: Urbanisme, Electoral, Civil
```

**Why Not a Loop**: `foreach ($code_ids) { function.run "get_toc" }` would hang silently.

#### 3. Unrolled 10 Chunk Embedding Blocks

**Problem**: Cannot loop over chunks array with `function.run` for embeddings.

**Implementation** in `sync_worker`:
```xanoscript
// Chunk 0
function.run "utils/chunker_texte" { input = {texte: $full_text, chunk_index: 0} } as $chunk_0
conditional {
  if ($chunk_0 != null) {
    function.run "mistral/mistral_generer_embedding" { input = {texte: $chunk_0.chunk_text} } as $emb_0
    db.add REF_article_chunks { data = {chunk_index: 0, embedding: $emb_0, ...} }
  }
}

// Chunk 1
function.run "utils/chunker_texte" { input = {texte: $full_text, chunk_index: 1} } as $chunk_1
conditional {
  if ($chunk_1 != null) {
    function.run "mistral/mistral_generer_embedding" { input = {texte: $chunk_1.chunk_text} } as $emb_1
    db.add REF_article_chunks { data = {chunk_index: 1, embedding: $emb_1, ...} }
  }
}

// ... Chunks 2-9 (identical structure)
```

**Trade-off**: 500+ lines of duplicated code vs. platform stability.

#### 4. Inline OAuth Per Worker Run

**Problem**: Extracting OAuth to helper function creates 2-level nesting (worker → helper) which hangs.

**Implementation**: OAuth `api.request` block duplicated in both tasks (~30 lines each).

#### 5. Inline Data Objects in db.add

**Problem**: `db.add` with `data = $variable` causes parser errors.

**Implementation**:
```xanoscript
// ❌ Does not work
var $article_data {
  value = {id_legifrance: $article.id, titre: $article.titre, ...}
}
db.add REF_codes_legifrance { data = $article_data }

// ✅ Must inline all ~50 fields
db.add REF_codes_legifrance {
  data = {
    id_legifrance: $article.id,
    code_id: $article.codeId,
    titre: $article.titre,
    contenu_article: $article.texte,
    // ... 46 more fields
  }
}
```

#### 6. "Always Add, Cleanup Later" for Chunks

**Problem**: No `db.delete` statement exists in XanoScript.

**Implementation**: Worker always adds new chunks without deleting old ones. Cleanup via Xano MCP `deleteTableContentBySearch` tool run manually.

**Future**: Could add `date_sync` field and delete chunks where `date_sync < latest_sync` using MCP.

#### 7. Guard Pattern for Null Safety

**Problem**: Cannot use early returns (`response = ...` inside conditional blocks causes syntax error).

**Implementation**:
```xanoscript
// Initialize outside try-catch
var $article_ref_id { value = null }

try_catch {
  try {
    // Populate on success
    var.update $article_ref_id { value = $article.id }
  }
  catch {
    // Leave as null, downstream code checks it
  }
}

// Safe: Only proceeds if populated
conditional {
  if ($article_ref_id != null) {
    // Continue with chunking/embedding
  }
}
```

### Monitoring & Observability

**sync_status Endpoint** (ID 958):
```json
{
  "total": 1630,
  "pending": 245,
  "processing": 1,
  "completed": 1384,
  "error": 0,
  "last_sync": "2026-02-06T02:15:43Z"
}
```

**Key Metrics**:
- Processing rate: `completed / (now - last_sync)`
- Error rate: `error / total`
- ETA: `pending / processing_rate`

## Implementation Timeline

| Date | Milestone |
|------|-----------|
| 2026-01-28 | v1: Client-side bash script (`sync_all.sh`) — functional but violates sovereignty |
| 2026-02-03 | Discovery: foreach + function.run = platform hang |
| 2026-02-04 | Architecture pivot: Queue + Worker pattern designed |
| 2026-02-06 | v2: Server-side implementation completed |
| 2026-02-06 | Validated: ~1,630 articles synced successfully |

## Known Limitations

1. **Maximum 10 Chunks Per Article**: Unrolled block count hardcoded. Articles >80,000 chars will be truncated.
2. **No Automatic Chunk Cleanup**: Old chunks accumulate. Manual MCP tool deletion required.
3. **4-Second Polling Overhead**: Worker runs even when queue empty, consumes task execution quota.
4. **No Retry Backoff**: Failed items reprocessed at same priority. Could benefit from exponential backoff.
5. **No Concurrent Workers**: Single worker thread. Could parallelize with multiple offset queries.

## Future Improvements

1. **Dynamic Chunk Processing**: Replace unrolled blocks with iterative single-chunk-at-a-time pattern (requires architectural change)
2. **Automatic Chunk Garbage Collection**: Add `date_sync` field, delete stale chunks via scheduled MCP task
3. **Adaptive Polling**: Increase worker interval when queue consistently empty
4. **Priority Queue Intelligence**: Boost priority for frequently accessed articles
5. **Differential TOC Sync**: Only queue articles with changed `dateTexte` or `dateModification`

## Related Specifications

- **Feature 001**: PISTE API Integration (functions 76, 77, 68, 80)
- **Feature 002**: Text Chunking & Embeddings (functions 79, 83)
- **Constitution**: Article I.3 (LEX_/REF_ table scoping exemption)

---

**Document Status**: ✅ Retrospective — Implementation Complete
**Last Updated**: 2026-02-06
**Workspace**: MARiaNNE (ID 5)
**Branch**: `requete_textes`
