// Table: QUEUE_sync
// Purpose: Job queue for server-side autonomous legal article sync pipeline
// Maps to ontology entity: SyncQueueItem (new — to be added)
// Architecture: sync_populate_queue fills queue → sync_worker processes one item per run
// Replaces: client-side sync_all.sh orchestration

table "QUEUE_sync" {
  auth = false
  schema {
    int id {
      description = "Unique identifier for queue item"
    }

    int sync_log_id? {
      table = "LOG_sync_legifrance"
      description = "FK to sync execution log that created this queue item"
    }

    text code_textId {
      description = "PISTE textId of the legal code (e.g. LEGITEXT000006070633)"
    }

    text article_id_legifrance {
      description = "LEGIARTI ID of the article to sync from PISTE API"
    }

    enum status {
      values = ["pending", "processing", "done", "unchanged", "error"]
      description = "Queue item processing status"
    }

    text error_message? {
      description = "Error details if processing failed"
    }

    int chunks_count? {
      description = "Number of text chunks embedded for this article"
    }

    timestamp created_at?=now {
      description = "When the queue item was created"
    }

    timestamp processed_at? {
      description = "When the worker finished processing this item"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "status", op: "asc"}]}
    {type: "btree", field: [{name: "sync_log_id", op: "asc"}]}
    {type: "btree", field: [{name: "code_textId", op: "asc"}]}
  ]
}
