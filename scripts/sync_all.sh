#!/bin/bash
# DEPRECATED (2026-02-07) — Replaced by server-side queue pipeline:
#   Task sync_populate_queue (ID 13): nightly at 02:00 UTC, fills QUEUE_sync
#   Task sync_worker (ID 14): every 4s, processes 1 article from queue
#   API sync_status (ID 958): monitoring endpoint with queue stats
# This script is kept for reference only. Use Xano tasks instead.
#
# --- Original description ---
# Full sync orchestrator — client-side loop calling Xano API endpoints
# Workaround for XanoScript foreach+external-call hang bug
#
# Usage: ./scripts/sync_all.sh [--skip-chunks] [--code TEXTID]

set -euo pipefail

BASE_URL="https://xsxf-qasi-dpir.p7.xano.io/api:vGO7N_5o:requete_textes"
SLEEP_ARTICLE=0.3    # seconds between article syncs (PISTE rate limit)
SLEEP_CHUNK=0.25     # seconds between chunk embeddings (Mistral rate limit)
MAX_RETRIES=3
TIMEOUT=90

# Parse arguments
SKIP_CHUNKS=false
ONLY_CODE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-chunks) SKIP_CHUNKS=true; shift ;;
    --code) ONLY_CODE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# 5 priority codes from LEX_codes_piste
CODES=(
  "LEGITEXT000006070633"   # CGCT
  "LEGITEXT000006070162"   # Communes
  "LEGITEXT000006070239"   # Électoral
  "LEGITEXT000006074075"   # Urbanisme
  "LEGITEXT000006070721"   # Civil
)

# Stats
TOTAL_ARTICLES=0
TOTAL_CREATED=0
TOTAL_UPDATED=0
TOTAL_UNCHANGED=0
TOTAL_ERRORS=0
TOTAL_CHUNKS=0
START_TIME=$(date +%s)

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# Retry wrapper
call_api() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local attempt=0
  local result=""

  while [ $attempt -lt $MAX_RETRIES ]; do
    if [ "$method" = "GET" ]; then
      result=$(curl -s "$BASE_URL/$endpoint" --max-time $TIMEOUT 2>&1) || true
    else
      result=$(curl -s -X POST "$BASE_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -d "$data" \
        --max-time $TIMEOUT 2>&1) || true
    fi

    # Check for error (Xano errors have "code" field starting with "ERROR")
    if [ -n "$result" ] && ! echo "$result" | grep -q '"code":"ERROR'; then
      echo "$result"
      return 0
    fi

    attempt=$((attempt + 1))
    log "  RETRY $attempt/$MAX_RETRIES for $endpoint"
    sleep 2
  done

  echo "$result"
  return 1
}

log "=========================================="
log "LEGAL SYNC - Full Pipeline"
log "=========================================="
if [ -n "$ONLY_CODE" ]; then
  CODES=("$ONLY_CODE")
  log "Syncing single code: $ONLY_CODE"
fi
log "Codes to sync: ${#CODES[@]}"
log "Skip chunks: $SKIP_CHUNKS"
log ""

for CODE in "${CODES[@]}"; do
  log "━━━ Code: $CODE ━━━"

  # Step 1: Get article list
  log "Fetching article list..."
  ARTICLES_JSON=$(call_api POST "list_article_ids" "{\"textId\":\"$CODE\"}") || {
    log "ERROR: Failed to get article list for $CODE"
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    continue
  }

  ARTICLE_IDS=$(echo "$ARTICLES_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = d.get('ids', [])
for aid in ids:
    print(aid)
" 2>/dev/null)

  ARTICLE_COUNT=$(echo "$ARTICLE_IDS" | grep -c . || echo 0)
  log "Found $ARTICLE_COUNT articles"

  CODE_CREATED=0
  CODE_UPDATED=0
  CODE_UNCHANGED=0
  CODE_ERRORS=0
  CODE_CHUNKS=0
  IDX=0

  while IFS= read -r AID; do
    [ -z "$AID" ] && continue
    IDX=$((IDX + 1))

    # Step 2: Sync one article
    RESULT=$(call_api POST "sync_one" "{\"textId\":\"$CODE\",\"article_id\":\"$AID\"}") || {
      log "  [$IDX/$ARTICLE_COUNT] ERROR syncing $AID"
      CODE_ERRORS=$((CODE_ERRORS + 1))
      continue
    }

    ACTION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action','error'))" 2>/dev/null || echo "error")
    RECORD_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('record_id',0))" 2>/dev/null || echo "0")
    NUM=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('num','?'))" 2>/dev/null || echo "?")

    case "$ACTION" in
      created)   CODE_CREATED=$((CODE_CREATED + 1)) ;;
      updated)   CODE_UPDATED=$((CODE_UPDATED + 1)) ;;
      unchanged) CODE_UNCHANGED=$((CODE_UNCHANGED + 1)) ;;
      *)         CODE_ERRORS=$((CODE_ERRORS + 1)) ;;
    esac

    # Step 3: Embed chunks (if not skipping and article was created/updated)
    if [ "$SKIP_CHUNKS" = false ] && [ "$ACTION" != "error" ] && [ "$RECORD_ID" != "0" ]; then
      CHUNK_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('chunks',[])))" 2>/dev/null || echo "0")

      if [ "$CHUNK_COUNT" -gt 0 ]; then
        # Extract chunks and embed each one
        for CIDX in $(seq 0 $((CHUNK_COUNT - 1))); do
          CHUNK_DATA=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['chunks'][$CIDX]
print(json.dumps({
  'article_id': d['record_id'],
  'id_legifrance': d['article_id'],
  'code': '$CODE',
  'num': d.get('num', ''),
  'etat': d.get('etat', ''),
  'fullSectionsTitre': d.get('fullSectionsTitre', ''),
  'chunk_index': c['index'],
  'chunk_text': c['text'],
  'start_position': c['start'],
  'end_position': c['end']
}))
" 2>/dev/null)

          CHUNK_RESULT=$(call_api POST "embed_chunk" "$CHUNK_DATA") || {
            log "    CHUNK ERROR: $AID chunk $CIDX"
            continue
          }

          CHUNK_ACTION=$(echo "$CHUNK_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action','error'))" 2>/dev/null || echo "error")
          if [ "$CHUNK_ACTION" = "created" ] || [ "$CHUNK_ACTION" = "updated" ]; then
            CODE_CHUNKS=$((CODE_CHUNKS + 1))
          fi

          sleep "$SLEEP_CHUNK"
        done
      fi
    fi

    # Progress every 10 articles
    if [ $((IDX % 10)) -eq 0 ] || [ "$IDX" -eq "$ARTICLE_COUNT" ]; then
      log "  [$IDX/$ARTICLE_COUNT] +$CODE_CREATED created, ~$CODE_UPDATED updated, =$CODE_UNCHANGED unchanged, x$CODE_ERRORS errors, chunks:$CODE_CHUNKS"
    fi

    sleep "$SLEEP_ARTICLE"
  done <<< "$ARTICLE_IDS"

  log "Code $CODE done: $CODE_CREATED created, $CODE_UPDATED updated, $CODE_UNCHANGED unchanged, $CODE_ERRORS errors, $CODE_CHUNKS chunks"

  TOTAL_ARTICLES=$((TOTAL_ARTICLES + IDX))
  TOTAL_CREATED=$((TOTAL_CREATED + CODE_CREATED))
  TOTAL_UPDATED=$((TOTAL_UPDATED + CODE_UPDATED))
  TOTAL_UNCHANGED=$((TOTAL_UNCHANGED + CODE_UNCHANGED))
  TOTAL_ERRORS=$((TOTAL_ERRORS + CODE_ERRORS))
  TOTAL_CHUNKS=$((TOTAL_CHUNKS + CODE_CHUNKS))
  log ""
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "=========================================="
log "SYNC COMPLETE"
log "Duration: ${DURATION}s"
log "Articles: $TOTAL_ARTICLES total"
log "  Created:   $TOTAL_CREATED"
log "  Updated:   $TOTAL_UPDATED"
log "  Unchanged: $TOTAL_UNCHANGED"
log "  Errors:    $TOTAL_ERRORS"
log "Chunks embedded: $TOTAL_CHUNKS"
log "=========================================="
