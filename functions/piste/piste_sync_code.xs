// Function: piste_sync_code
// Purpose: Synchronize a single legal code from PISTE to Xano (T015)
// Input: textId of the code to sync
// Output: Sync statistics { articles_traites, articles_crees, articles_maj, articles_erreur }
// Implements: EF-005 (change detection), EF-009 (rate limiting)

function piste_sync_code {
  input: {
    textId: text              // e.g., "LEGITEXT000006070633"
    force_full: boolean = false   // If true, ignore content_hash and update all
    log_id: int?              // Optional LOG_sync_legifrance.id to update progress
  }

  // Initialize counters
  var stats = {
    articles_traites: 0,
    articles_crees: 0,
    articles_maj: 0,
    articles_erreur: 0,
    articles_ignores: 0,
    embeddings_generes: 0
  }

  // Get OAuth token (reuse for all requests in this sync)
  var token = call piste_auth_token()

  // Fetch table of contents
  log.info(text.concat("Fetching TOC for ", textId))
  var toc = call piste_get_toc(textId: textId)

  // Extract all article IDs recursively
  var articles_to_sync = call piste_extraire_articles_toc(sections: toc.sections ?? [])
  log.info(text.concat("Found ", list.length(articles_to_sync), " articles to sync"))

  // Batch processing for rate limiting (10 req/s PISTE, 5 req/s Mistral)
  var batches = list.chunk(articles_to_sync, 50)
  var batch_delay_ms = 100

  foreach batch in batches {
    foreach article_ref in batch {
      try_catch {
        try {
          // Fetch full article from PISTE
          var article = call piste_get_article(article_id: article_ref.id, token: token)

          // Compute content hash
          var new_hash = call hash_contenu_article(
            fullSectionsTitre: article.fullSectionsTitre,
            surtitre: article.surtitre,
            texte: article.texte
          )

          // Check if article exists in database
          var existing = db.query({
            from: REF_codes_legifrance,
            where: { id_legifrance: article_ref.id },
            limit: 1
          })

          var should_update = force_full
          var is_new = list.length(existing) == 0

          if !is_new && !force_full {
            // Check if content changed
            should_update = existing[0].content_hash != new_hash
          }

          if is_new || should_update {
            // Parse hierarchy
            var hierarchy = call parser_fullSectionsTitre(fullSectionsTitre: article.fullSectionsTitre)

            // Generate embedding with rate limiting (5 req/s max for Mistral)
            var embedding_text = text.concat(
              article.fullSectionsTitre ?? "",
              " | ",
              article.surtitre ?? "",
              " | ",
              article.texte ?? ""
            )

            log.info(text.concat("Generating embedding for article ", article_ref.id))

            // Use proper function.run syntax for cross-namespace call
            function.run "mistral/mistral_generer_embedding" {
              input = { texte: embedding_text }
            } as embedding

            log.info(text.concat("Embedding generated, dimension: ", list.length(embedding)))
            stats.embeddings_generes = stats.embeddings_generes + 1

            // Rate limiting: 200ms between Mistral calls (~5 req/s)
            util.sleep(200)

            // Prepare record
            var record = {
              id_legifrance: article.id,
              num: article.num,
              cid: article.cid,
              idEli: article.idEli,
              idEliAlias: article.idEliAlias,
              idTexte: article.idTexte,
              cidTexte: article.cidTexte,
              code: textId,
              texte: article.texte,
              texteHtml: article.texteHtml,
              nota: article.nota,
              notaHtml: article.notaHtml,
              surtitre: article.surtitre,
              historique: article.historique,
              dateDebut: article.dateDebut,
              dateFin: article.dateFin,
              dateDebutExtension: article.dateDebutExtension,
              dateFinExtension: article.dateFinExtension,
              etat: article.etat,
              type_article: article.type,
              nature: article.nature,
              origine: article.origine,
              version_article: article.version,
              versionPrecedente: article.versionPrecedente,
              multipleVersions: article.multipleVersions ?? false,
              sectionParentId: article.sectionParentId,
              sectionParentCid: article.sectionParentCid,
              sectionParentTitre: article.sectionParentTitre,
              fullSectionsTitre: article.fullSectionsTitre,
              ordre: article.ordre,
              partie: hierarchy.partie,
              livre: hierarchy.livre,
              titre: hierarchy.titre,
              chapitre: hierarchy.chapitre,
              section: hierarchy.section,
              sous_section: hierarchy.sous_section,
              paragraphe: hierarchy.paragraphe,
              idTechInjection: article.idTechInjection,
              refInjection: article.refInjection,
              numeroBo: article.numeroBo,
              inap: article.inap,
              infosComplementaires: article.infosComplementaires,
              infosComplementairesHtml: article.infosComplementairesHtml,
              conditionDiffere: article.conditionDiffere,
              infosRestructurationBranche: article.infosRestructurationBranche,
              infosRestructurationBrancheHtml: article.infosRestructurationBrancheHtml,
              renvoi: article.renvoi,
              comporteLiensSP: article.comporteLiensSP ?? false,
              embeddings: embedding,
              content_hash: new_hash,
              last_sync_at: date.now(),
              updated_at: date.now()
            }

            if is_new {
              record.created_at = date.now()
              db.insert({ into: REF_codes_legifrance, values: record })
              stats.articles_crees = stats.articles_crees + 1
            } else {
              db.update({
                table: REF_codes_legifrance,
                where: { id: existing[0].id },
                values: record
              })
              stats.articles_maj = stats.articles_maj + 1
            }
          } else {
            stats.articles_ignores = stats.articles_ignores + 1
          }

          stats.articles_traites = stats.articles_traites + 1

        }
        catch (error) {
          log.error(text.concat("Error syncing article ", article_ref.id, ": ", error.message))
          stats.articles_erreur = stats.articles_erreur + 1
        }
      }
    }

    // Rate limiting: pause between batches
    util.sleep(batch_delay_ms)
  }

  log.info(text.concat("Sync complete for ", textId, ": ", stats.articles_traites, " processed, ", stats.articles_crees, " created, ", stats.articles_maj, " updated, ", stats.articles_ignores, " unchanged"))

  return stats
}
