// API: Collecter les données via chatbot
// Endpoint: POST /api/doc_generator/collecter_donnees_chatbot
// Auth: JWT utilisateurs
// Description: Reçoit une réponse utilisateur, l'interprète via Mistral,
//   met à jour les données collectées et retourne la prochaine question.
//   Utilise le MCP serveur Mistral pour interpréter les réponses naturelles.

query "doc_generator/collecter_donnees_chatbot" verb=POST {
  api_group = "doc_generator"
  auth = "utilisateurs"
  description = "Collecte progressive des données via chatbot IA pour remplir un template"

  input {
    int session_id {
      description = "ID de la session de génération"
    }
    text message_utilisateur {
      description = "Réponse de l'utilisateur à la question posée"
    }
    text placeholder_id {
      description = "ID du placeholder auquel l'utilisateur répond"
    }
  }

  stack {
    // Récupérer la session
    db.get "sessions_generation_documents" {
      field_name = "id"
      field_value = $input.session_id
    } as $session

    precondition ($session != null) {
      error_type = "notfound"
      error = "Session non trouvée"
    }

    precondition ($session.utilisateur_id == $auth.id) {
      error_type = "accessdenied"
      error = "Cette session ne vous appartient pas"
    }

    precondition ($session.statut == "en_cours") {
      error_type = "badrequest"
      error = "Cette session est déjà terminée"
    }

    // Récupérer le template pour les métadonnées placeholders
    db.get "templates_documents_administratifs" {
      field_name = "id"
      field_value = $session.template_id
    } as $template

    // Trouver le placeholder actuel dans les métadonnées
    var $placeholder_meta {
      value = null
    }

    foreach ($template.placeholders) {
      each as $ph {
        conditional {
          if ($ph.id == $input.placeholder_id) {
            var.update $placeholder_meta {
              value = $ph
            }
          }
          else {
            // Pas le bon placeholder
          }
        }
      }
    }

    // Interpréter la réponse via Mistral
    // Pour les types simples (text), on prend la réponse telle quelle
    // Pour les dates, on demande à Mistral de formater
    var $valeur_interpretee {
      value = $input.message_utilisateur
    }

    conditional {
      if ($placeholder_meta.type == "date") {
        // Utiliser Mistral pour interpréter la date
        api.request {
          url = "https://api.mistral.ai/v1/chat/completions"
          method = "POST"
          params = {
            model: "mistral-small-latest",
            temperature: 0.1,
            messages: [
              {
                role: "system",
                content: "Tu es un parseur de dates. Convertis le texte en date au format JJ/MM/AAAA. Réponds UNIQUEMENT avec la date, rien d'autre. Si le texte n'est pas une date valide, réponds 'INVALIDE'."
              },
              {
                role: "user",
                content: $input.message_utilisateur
              }
            ]
          }
          headers = []
            |push:("Authorization: Bearer " ~ $env.MISTRAL_API_KEY)
            |push:"Content-Type: application/json"
          description = "Interpréter la date via Mistral"
        } as $mistral_date

        var.update $valeur_interpretee {
          value = $mistral_date.response.result.choices.0.message.content
        }
      }
      elseif ($placeholder_meta.type == "number") {
        // Extraire le nombre de la réponse
        api.request {
          url = "https://api.mistral.ai/v1/chat/completions"
          method = "POST"
          params = {
            model: "mistral-small-latest",
            temperature: 0.1,
            messages: [
              {
                role: "system",
                content: "Tu es un extracteur de nombres. Extrais le nombre du texte. Réponds UNIQUEMENT avec le nombre (chiffres uniquement, sans unité). Si pas de nombre, réponds 'INVALIDE'."
              },
              {
                role: "user",
                content: $input.message_utilisateur
              }
            ]
          }
          headers = []
            |push:("Authorization: Bearer " ~ $env.MISTRAL_API_KEY)
            |push:"Content-Type: application/json"
          description = "Extraire le nombre via Mistral"
        } as $mistral_num

        var.update $valeur_interpretee {
          value = $mistral_num.response.result.choices.0.message.content
        }
      }
      else {
        // Texte simple - garder tel quel
      }
    }

    // Vérifier la validité
    var $est_valide {
      value = ($valeur_interpretee != "INVALIDE" && $valeur_interpretee != "")
    }

    // Mettre à jour les données collectées dans la session
    var $nouvelles_donnees {
      value = $session.donnees_collectees
    }

    conditional {
      if ($est_valide) {
        var.update $nouvelles_donnees {
          value = $nouvelles_donnees|set:($input.placeholder_id):$valeur_interpretee
        }

        db.edit "sessions_generation_documents" {
          field_name = "id"
          field_value = $session.id
          data = {
            donnees_collectees: $nouvelles_donnees
          }
        } as $session_maj
      }
      else {
        // Réponse invalide - ne pas mettre à jour
      }
    }

    // Déterminer le prochain placeholder à collecter
    var $prochain_placeholder {
      value = null
    }
    var $prochaine_question {
      value = ""
    }
    var $collecte_complete {
      value = true
    }

    foreach ($template.placeholders) {
      each as $ph {
        conditional {
          if ($ph.auto_fill != true && !($nouvelles_donnees|has_key:($ph.id)) && $prochain_placeholder == null) {
            var.update $prochain_placeholder {
              value = $ph
            }
            var.update $prochaine_question {
              value = $ph.question_chatbot ?? ("Quelle est la valeur pour : " ~ $ph.label ~ " ?")
            }
            var.update $collecte_complete {
              value = false
            }
          }
          else {
            // Déjà rempli ou auto_fill
          }
        }
      }
    }

    var $result {
      value = {
        valide: $est_valide,
        valeur_interpretee: $valeur_interpretee,
        placeholder_id: $input.placeholder_id,
        donnees_collectees: $nouvelles_donnees,
        collecte_complete: $collecte_complete,
        prochain_placeholder: $prochain_placeholder,
        prochaine_question: $prochaine_question,
        message_erreur: ($est_valide == false) ? "Je n'ai pas compris votre réponse. Pouvez-vous reformuler ?" : null,
        nb_collectes: ($nouvelles_donnees|count),
        nb_total: ($template.placeholders|count)
      }
    }
  }

  response = $result
}
