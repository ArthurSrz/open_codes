// API: 922_sync_legifrance_historique_GET
// Purpose: Get sync execution history with pagination (T024)
// Method: GET
// Auth: Requires authenticated user
// Input: { limit?: int, offset?: int }
// Output: Array of LOG_sync_legifrance entries

query 922_sync_legifrance_historique_GET {
  auth: utilisateurs

  input: {
    limit: int = 10             // Results per page (max 100)
    offset: int = 0             // Pagination offset
  }

  run {
    // Validate limit
    var safe_limit = math.min(input.limit, 100)

    // Query history
    var history = db.query({
      from: LOG_sync_legifrance,
      order_by: [{ debut_sync: "desc" }],
      limit: safe_limit,
      offset: input.offset
    })

    // Get total count for pagination
    var total = db.count({ from: LOG_sync_legifrance })

    // Format response
    var items = list.map(history, sync => {
      return {
        id: sync.id,
        statut: sync.statut,
        code_textId: sync.code_textId,
        declencheur: sync.declencheur,
        debut_sync: sync.debut_sync,
        fin_sync: sync.fin_sync,
        duree_secondes: sync.duree_secondes,
        articles_traites: sync.articles_traites,
        articles_crees: sync.articles_crees,
        articles_maj: sync.articles_maj,
        articles_erreur: sync.articles_erreur,
        erreur_message: sync.erreur_message
      }
    })

    return {
      items: items,
      pagination: {
        total: total,
        limit: safe_limit,
        offset: input.offset,
        has_more: input.offset + safe_limit < total
      }
    }
  }
}
