// API: 920_sync_legifrance_lancer_POST
// Purpose: Trigger a sync manually via REST API (T022)
// Method: POST
// Auth: Requires authenticated user with gestionnaire role
// Input: { code_textId?: string, force_full?: boolean }
// Output: { sync_id: int, status: string }

query 920_sync_legifrance_lancer_POST {
  auth: utilisateurs

  input: {
    code_textId: text?          // Optional: sync specific code only
    force_full: boolean = false // Force full sync ignoring hashes
  }

  run {
    // Fetch the authenticated user to check their permissions
    // (auth.extras is not reliably populated with custom fields)
    var user = db.get(utilisateurs, { id: auth.id })

    // Authorization: Only gestionnaires or admins can trigger syncs
    precondition {
      if !(user.gestionnaire == true || auth.role == "admin") {
        throw { status: 403, message: "Accès réservé aux gestionnaires et administrateurs" }
      }
    }

    log.info(text.concat("Sync triggered by user ", auth.id, " for code: ", input.code_textId ?? "ALL"))

    // Call orchestrator (runs synchronously for now)
    // TODO: For production, consider async execution with webhook callback
    var result = call piste_orchestrer_sync(
      code_textId: input.code_textId,
      force_full: input.force_full,
      declencheur: "api"
    )

    return {
      sync_id: result.id,
      status: result.statut,
      message: text.concat("Sync ", result.statut == "TERMINE" ? "completed" : "started")
    }
  }
}
