// Task: sync_legifrance_quotidien
// Purpose: Daily automated sync of all active legal codes (T019)
// Schedule: Daily at 02:00 UTC (low traffic period)
// Timeout: 4 hours (handles large codes like Code Civil)

task 8_sync_legifrance_quotidien {
  schedule: "0 2 * * *"   // Daily at 02:00 UTC (04:00 Paris winter)

  timeout: 14400000    // 4 hours in milliseconds

  run {
    log.info("Starting daily Légifrance sync...")

    var result = call piste_orchestrer_sync(
      force_full: false,
      declencheur: "task"
    )

    log.info(text.concat(
      "Daily sync completed. Status: ", result.statut,
      ", Duration: ", result.duree_secondes, "s",
      ", Articles: ", result.articles_traites
    ))
  }
}
