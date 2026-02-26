// API: sync_status (enhanced)
// Purpose: Returns sync pipeline status with queue monitoring
// Endpoint: GET /sync_status (Legifrance API group, ID 46)
// Auth: none (maintenance endpoint)

query sync_status verb=GET {
  api_group = "Legifrance"
  description = "Returns sync pipeline status: queue stats, recent logs, article/chunk counts"

  input {
  }

  stack {
    // Recent sync logs
    db.query "LOG_sync_legifrance" {
      sort = {id: "desc"}
      return = {type: "list", paging: {page: 1, per_page: 5}}
      description = "Last 5 sync logs"
    } as $logs

    // Count synced articles
    db.query "REF_codes_legifrance" {
      where = $db.REF_codes_legifrance.id_legifrance != null
      return = {type: "list", paging: {page: 1, per_page: 1}}
      description = "Count synced articles"
    } as $synced_articles

    // Count chunks
    db.query "REF_article_chunks" {
      return = {type: "list", paging: {page: 1, per_page: 1}}
      description = "Count total chunks"
    } as $chunks

    // Queue stats by status
    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "pending"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $q_pending

    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "processing"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $q_processing

    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "done"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $q_done

    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "unchanged"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $q_unchanged

    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "error"
      return = {type: "list", paging: {page: 1, per_page: 1}}
    } as $q_error

    // Calculate totals and progress
    var $total_pending { value = $q_pending._meta.paging.total ?? 0 }
    var $total_processing { value = $q_processing._meta.paging.total ?? 0 }
    var $total_done { value = $q_done._meta.paging.total ?? 0 }
    var $total_unchanged { value = $q_unchanged._meta.paging.total ?? 0 }
    var $total_error { value = $q_error._meta.paging.total ?? 0 }

    var $total_queued {
      value = $total_pending + $total_processing + $total_done + $total_unchanged + $total_error
    }

    var $total_completed {
      value = $total_done + $total_unchanged + $total_error
    }

    var $progress_pct {
      value = (($total_queued > 0) ? ((($total_completed * 100) / $total_queued)|round) : 0)
    }

    // Recent errors for debugging
    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "error"
      sort = {id: "desc"}
      return = {type: "list", paging: {page: 1, per_page: 5}}
    } as $recent_errors
  }

  response = {
    queue: {
      pending: $total_pending
      processing: $total_processing
      done: $total_done
      unchanged: $total_unchanged
      error: $total_error
      total: $total_queued
      progress_pct: $progress_pct
    }
    recent_errors: $recent_errors
    recent_logs: $logs
    synced_articles: $synced_articles._meta.paging.total ?? 0
    total_chunks: $chunks._meta.paging.total ?? 0
  }
}
