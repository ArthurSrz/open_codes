# Troubleshooting - Legal Sync

## "Not numeric" Error in `sync_legifrance_lancer` API

**Date:** 2026-02-06

**Error:** `{ code: ERROR_FATAL, message: Not numeric. }`

**Context:** Running `sync_legifrance_lancer` API (ID 924) with input:
```json
{
  "code_textId": "LEGITEXT000006070239",
  "force_full": false
}
```

**Root Causes Identified:**

### 1. Invalid Parameter Passed to Function

The `piste_orchestrer_sync` function was calling `piste/piste_sync_code` with a parameter that doesn't exist:

```xanoscript
// WRONG - code_nom parameter doesn't exist in piste_sync_code
function.run "piste/piste_sync_code" {
  input = {
    textId    : $code.textId
    code_nom  : $code.titre    // <-- This parameter doesn't exist!
    force_full: $input.force_full
  }
}
```

**Fix:** Remove the `code_nom` parameter:
```xanoscript
// CORRECT
function.run "piste/piste_sync_code" {
  input = {
    textId    : $code.textId
    force_full: $input.force_full
    log_id    : $sync_log_id
  }
}
```

### 2. Float Division Stored in Integer Field

The `duree_secondes` field in `LOG_sync_legifrance` table is of type `int`, but the duration calculation produces a float:

```xanoscript
// WRONG - Division produces float, but field expects int
var $duree {
  value = ($fin - $debut) / 1000
}
```

**Fix:** Add `|round` filter to convert to integer:
```xanoscript
// CORRECT
var $duree {
  value = (($fin - $debut) / 1000)|round
}
```

### 3. Variable Shadowing in Conditional Branches

The original code had variable shadowing issues:
```xanoscript
else {
  db.query LEX_codes_piste {...} as $codes  // Creates NEW variable, shadows outer $codes
}
```

**Fix:** Use a different variable name and explicitly update:
```xanoscript
else {
  db.query LEX_codes_piste {...} as $active_codes
  var.update $codes {
    value = $active_codes
  }
}
```

**Files Modified:**
- Function `piste_orchestrer_sync` (ID 81) in Xano workspace 5, branch `requete_textes`
- Local file: `/functions/piste/piste_orchestrer_sync.xs`

**Lesson Learned:**
- Always verify function signatures before calling - pass only accepted parameters
- When storing arithmetic results in database fields, match the expected type (use `|round` for int fields)
- Avoid using `as $varname` in conditional branches when you want to update an outer variable

---

## "Not numeric" Error - Full Root Cause Fix (2026-02-06)

**Root Causes (cascading failure):**

### 1. `now` is not numeric in XanoScript

`var $debut { value = now }` stores a **timestamp object**. Arithmetic like `$fin - $debut` fails with "Not numeric" because timestamp objects don't support math operators.

**Fix:** Use `"now"|to_ms` which returns numeric milliseconds:
```xanoscript
var $debut_ms { value = "now"|to_ms }
// Later:
var $duree { value = (("now"|to_ms - $debut_ms) / 1000)|round }
```

For database timestamp fields, use `"now"` (string) which Xano auto-converts.

### 2. Wrong token field name: `access_token` vs `bearer_token`

`piste_auth_token` returned `{ bearer_token: ... }` but `piste_sync_code` accessed `$auth.access_token` (non-existent field) → null token → 401 from PISTE API → catch fires → duration calc triggers "Not numeric".

Both `access_token` and `bearer_token` are reserved/problematic keywords in XanoScript.

**Fix:** Renamed to `api_token` across all 5 functions:
- `piste_auth_token` (76): response field `bearer_token` → `api_token`
- `piste_get_toc` (77): input param `bearer_token` → `api_token`
- `piste_get_article` (68): input param `bearer_token` → `api_token`
- `piste_sync_code` (82): caller uses `$auth.api_token`
- `piste_orchestrer_sync` (81): timestamp arithmetic fixed

### 3. No early returns in XanoScript

`response = ...` inside a `catch` block causes syntax error — it's a function-level declaration, not a control flow statement.

**Fix:** Use guard pattern — initialize `$articles_to_sync = []` before try-catch, populate inside try. If catch fires, the empty array means foreach is a no-op.

### 4. `|to_int` not a valid filter

Use `|round` instead for converting float to integer in XanoScript.

---

## Sync Pipeline Processes 0 Articles (2026-02-06)

**Symptom:** Daily task `sync_legifrance_quotidien` runs successfully (status `TERMINE`) but consistently shows 0 articles processed, 0 articles created, 0 embeddings. 50 consecutive sync logs with identical zero results.

**Root Cause:** `function.run` for functions WITHOUT folder prefix returns `{dbo, id}` metadata instead of the function's actual response.

In `piste_sync_code`, all 6 helper function calls used **unquoted names without folder prefixes**:

```xanoscript
// ALL return metadata {dbo, id} instead of actual response
function.run piste_get_toc { ... } as $toc               // $toc = {dbo, id}
function.run piste_extraire_articles_toc { ... } as $res  // $res = {dbo, id}
function.run piste_get_article { ... } as $article        // same
function.run hash_contenu_article { ... } as $hash        // same
function.run parser_fullSectionsTitre { ... } as $h       // same
function.run mistral_generer_embedding { ... } as $emb    // same
```

So `$toc.sections` was always `null` → `null ?? []` = `[]` → 0 articles extracted → foreach no-op.

**Why no error?** The `try_catch` block caught nothing because `function.run` succeeded (returned metadata). The `$toc.sections ?? []` coalesced to empty array silently.

**Fix:** Move ALL helper functions into folders and use quoted folder paths:

| Before (broken) | After (working) |
|---|---|
| `piste_get_toc` (ID 77) | `piste/piste_get_toc` |
| `piste_extraire_articles_toc` (ID 80) | `piste/piste_extraire_articles_toc` |
| `piste_get_article` (ID 68) | `piste/piste_get_article` |
| `hash_contenu_article` (ID 67) | `utils/hash_contenu_article` |
| `parser_fullSectionsTitre` (ID 78) | `utils/parser_fullSectionsTitre` |
| `mistral_generer_embedding` (ID 79) | `mistral/mistral_generer_embedding` |
| `piste_orchestrer_sync` (ID 81) | `piste/piste_orchestrer_sync` |

Also fixed `$new_hash` → `$new_hash.hash` (hash_contenu_article returns `{hash: "..."}`, not plain string).

Also fixed test endpoints (943-946) using `bearer_token` → `api_token`.

Updated daily task to use `function.run "piste/piste_orchestrer_sync"`.

**Rule:** EVERY `function.run` call in XanoScript must use `"folder/function_name"` syntax — both quoted and with folder prefix. Functions without folder prefixes return metadata, not responses.

---

## Nested function.run Causes Silent Hanging (2026-02-06)

**Symptom:** Sync task runs for 8+ minutes but processes 0 articles. No errors in logs, no progress. `LOG_sync_legifrance` shows `EN_COURS` indefinitely.

**Root Cause:** XanoScript does NOT support nested `function.run` calls (2+ levels deep). When an API endpoint or task calls Function A via `function.run`, and Function A internally calls Function B via `function.run`, the entire process hangs silently.

**Example of broken architecture:**
```
API endpoint → function.run "piste/piste_orchestrer_sync"     (level 1)
                  → function.run "piste/piste_sync_code"       (level 2) ← HANGS
                      → function.run "piste/piste_get_toc"     (level 3)
```

**Diagnosis method:**
1. Created diagnostic endpoint (ID 948) testing each function individually - ALL passed
2. Tested nested call (API → orchestrer_sync → sync_code) - HUNG
3. Confirmed: single-level function.run works, multi-level does not

**Fix:** Flat architecture - move ALL sync logic directly into the Task/API so all `function.run` calls are at exactly 1 level deep:
```
Task → function.run "piste/piste_get_toc"                  (level 1) ✅
Task → function.run "piste/piste_get_article"              (level 1) ✅
Task → function.run "mistral/mistral_generer_embedding"    (level 1) ✅
```

**Files Modified:**
- Task `sync_legifrance_quotidien` (ID 9) - completely rewritten with flat architecture
- Function `piste/piste_orchestrer_sync` (ID 81) - now deprecated
- Function `piste/piste_sync_code` (ID 82) - now deprecated (logic moved to task)

**Rule:** NEVER nest `function.run` calls in XanoScript. All function calls must be at exactly 1 level deep from the calling endpoint/task.

---

## HTTP Timeout on Long-Running Sync (2026-02-06)

**Symptom:** API endpoint `test_full_sync_pipeline` (ID 947) returns 504 Gateway Timeout after ~120 seconds, even though the sync is still running server-side.

**Root Cause:** Nginx reverse proxy in front of Xano has a ~120s timeout. The PISTE API takes several seconds per article fetch, and with 1,630+ articles, a full sync takes hours.

**Evidence:** After curl timed out, checking the database revealed new articles (IDs 4972, 4973) had been created - proving the sync continued running server-side despite the HTTP timeout.

**Fix:** Move sync logic into a Xano **Task** (scheduled job) instead of an API endpoint. Tasks run server-side without HTTP timeout constraints.

**Key insight:** Xano continues executing logic even after the HTTP response times out. But the client never gets the response, and there is no way to monitor progress via HTTP. Tasks solve both problems.

---

## Null Parameter Causes Instant Orchestrator Failure (2026-02-06)

**Symptom:** Sync log entries show instant failures (0 seconds duration) with error message "Code LEGITEXT000006070239 error" (no actual error details).

**Root Causes:**

### 1. Null force_full parameter
The orchestrator passed `$input.force_full` to `piste_sync_code`, but when called without this parameter, it was null. The receiving function expected a boolean.

**Fix:** Add null coalescing: `force_full: $input.force_full ?? false`

### 2. Error swallowing in catch block
The catch block logged a generic message without including the actual `$error`:
```xanoscript
// WRONG - no actual error info
erreur_message: "Code " ~ $code.textId ~ " error"

// CORRECT - includes $error
erreur_message: "Code " ~ ($code.textId ?? "unknown") ~ ": " ~ $error
```

**Lesson:** Always include `$error` in catch block logging. Without it, debugging is impossible.

---

## Foreach + External Calls Causes Silent Hanging (2026-02-06)

**Symptom:** Any `function.run` or `api.request` placed inside a `foreach` loop causes the entire process to hang silently — no errors, no timeout, just infinite wait. This affects **both** API endpoints and scheduled Tasks.

**Tested combinations:**

| Inside foreach | Result |
|---|---|
| `var.update` | Works |
| `db.add` | Works |
| `function.run` | **HANGS** |
| `api.request` | **HANGS** |

**Diagnosis method:**
1. Created test API endpoint with hardcoded 2-item array
2. Tested `foreach` with just `var.update` → returned `{total: 3}` instantly
3. Tested `foreach` with `function.run "mistral/..."` inside → hung for 60s+
4. Tested `foreach` with inline `api.request` to Mistral → also hung
5. Tested `foreach` with `db.add` → returned error (about missing embedding field), NOT a hang
6. Confirmed: Tasks (scheduled jobs) have the SAME limitation

**Root Cause:** Unknown XanoScript engine limitation. External HTTP calls (`api.request`) and function invocations (`function.run`) inside `foreach` loops enter a deadlock state.

**Fix:** Client-side orchestration using a bash script that calls single-item API endpoints in a loop:

```
┌──────────────────────────────────────────────────┐
│              sync_all.sh (bash)                  │
│                                                  │
│  for each code:                                  │
│    POST /list_article_ids → get all IDs          │
│    for each article_id:                          │
│      POST /sync_one → create/update + get chunks │
│      for each chunk:                             │
│        POST /embed_chunk → embed + store         │
│      sleep 0.3s (PISTE rate limit)               │
└──────────────────────────────────────────────────┘
```

**API Endpoints Created:**
- `sync_one` (ID 954) — Syncs one article, returns chunks array
- `embed_chunk` (ID 959) — Embeds and stores one chunk
- `list_article_ids` (ID 956) — Lists all article IDs from PISTE TOC
- `sync_status` (ID 958) — Monitoring endpoint

**Performance:** ~3 seconds per article (OAuth + PISTE fetch + hash + hierarchy parse + embedding + db.add + chunk + chunk embed). Full sync of 1,630 articles takes ~1.5 hours.

**Rule:** NEVER use `function.run` or `api.request` inside `foreach` in XanoScript. Always move the loop to the client side.

---

## PISTE API Field Name Mismatch (2026-02-06)

**Symptom:** `sync_one` endpoint fails with "Unable to locate var: article.version" when creating new articles.

**Root Cause:** PISTE API uses different field names than what was assumed:

| Assumed Name | Actual PISTE Field |
|---|---|
| `$article.version` | `$article.versionArticle` |
| `$article.multipleVersions` | `$article.isMultipleVersions` |

**Fix:** Updated all `db.add` and `db.edit` statements to use correct PISTE field names.

**Lesson:** Always dump the raw API response first (`test_article_fields` endpoint) to verify exact field names before writing mapping code.

---

## XanoScript `== null` Comparison Doesn't Work for DB Field Null Checks (2026-02-06)

**Symptom:** Backfill logic in `embed_chunk` endpoint (ID 959) never executes. Chunks with null `code` field are found by `db.query`, but the conditional `$existing_chunk.code == null` never evaluates to true.

**Context:** After adding metadata columns (code, num, etat, fullSectionsTitre) to `REF_article_chunks`, 299 existing chunks had null values. The backfill logic was supposed to detect null fields and update them:

```xanoscript
// ❌ BROKEN - this condition NEVER fires, even when code IS null in the DB
conditional {
  if ($existing_chunk.code == null || $existing_chunk.code == "") {
    db.edit "REF_article_chunks" {
      field_name = "id"
      field_value = $existing_chunk.id
      data = {
        code: $input.code
        num: $input.num
      }
    } as $updated_chunk
  }
}
```

**Root Cause:** XanoScript's `== null` comparison does not work as expected for database field values that are NULL. The null value from the database is likely represented differently internally (e.g., as an undefined property or a special null object) that doesn't match the XanoScript `null` literal.

**Workaround:** Delete-and-recreate strategy instead of in-place backfill:
1. Delete all chunks with null metadata using Xano MCP `deleteTableContentBySearch`
2. Re-run sync to recreate chunks with full metadata from the start

**Lesson:** Don't rely on `== null` for detecting missing/null database field values in XanoScript. Use delete-and-recreate patterns for data migration instead of in-place updates based on null checks.

---

## Incorrect TextIds in Sync Script (2026-02-06)

**Symptom:** Sync script creates articles with wrong `code` values. 124 articles created with `LEGITEXT000006071154` which doesn't correspond to any of the 5 target codes.

**Root Cause:** The CODES array in `sync_all.sh` had wrong textIds for Communes and Urbanisme:

| Code | Wrong TextId | Correct TextId |
|------|-------------|----------------|
| Communes | LEGITEXT000006070200 | LEGITEXT000006070162 |
| Urbanisme | LEGITEXT000006071154 | LEGITEXT000006074075 |

The wrong IDs were guessed instead of being looked up from the `LEX_codes_piste` reference table.

**Fix:** Corrected the CODES array using values from `LEX_codes_piste` table (queried via Xano MCP).

**Cleanup:** Deleted 124 orphaned articles with `code=LEGITEXT000006071154` from `REF_codes_legifrance` (table 98).

**Lesson:** Always verify reference data (like textIds) from the source database table, never guess or assume values.

---

## Issue: db.add Rejects Variable References for `data` Parameter

**Date:** 2026-02-07
**Context:** Creating `sync_worker` task (ID 14) with db.add for article upsert
**Error:** `Syntax error, while parsing: 'db.add REF_codes_legifrance {' - Invalid kind for data - assign:var`

**Broken code:**
```xanoscript
// ❌ Variable reference in db.add data parameter
var $article_data {
  value = {
    id_legifrance: $article.id
    num: $article.num
    // ... many fields
  }
}

db.add REF_codes_legifrance {
  data = $article_data  // ← FAILS: "Invalid kind for data - assign:var"
}
```

**Root cause:** XanoScript's `db.add` statement does not accept variable references for the `data` parameter. The parser expects an inline object literal, not a `$variable`.

**Fix:** Inline all fields directly in the `db.add` block:
```xanoscript
// ✅ Inline data object in db.add
db.add REF_codes_legifrance {
  data = {
    id_legifrance: $article.id
    num: $article.num
    etat: $article.etat
    // ... all fields inline
  }
}
```

**Impact:** For the sync_worker task, this meant duplicating ~50 fields in both the `db.add` (new article) and `db.edit` (existing article) branches. Verbose but necessary.

**Lesson:** In XanoScript, `db.add` and potentially `db.edit` require inline object literals for `data`. Never assign to a variable first. This applies even if the variable is a simple object — the parser rejects the `assign:var` pattern at the syntax level.
