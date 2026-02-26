// Fonction: template_generer_prompt_chatbot
// Description: Génère le system prompt Mistral pour le chatbot de collecte de données
// Input: template_id (int), placeholders_metadata (json), donnees_collectees (json)
// Output: { system_prompt: text, prochaine_question: text, collecte_complete: bool }
//
// Le chatbot utilise Mistral AI pour poser les questions de manière conversationnelle.
// Cette fonction analyse les placeholders non remplis et génère un prompt
// guidant Mistral pour poser la prochaine question.

function "templates/template_generer_prompt_chatbot" {
  description = "Génère le prompt Mistral pour le chatbot de collecte de données du template"

  input {
    text template_nom {
      description = "Nom du template pour contextualiser les questions"
    }
    json placeholders_metadata {
      description = "Métadonnées JSON des placeholders [{id, label, type, required, question_chatbot}]"
    }
    json donnees_collectees {
      description = "Données déjà collectées {placeholder_id: valeur}"
    }
    text commune_nom {
      description = "Nom de la commune pour les auto-fill"
    }
  }

  stack {
    // Identifier les placeholders non encore remplis (hors auto_fill)
    var $placeholders_manquants {
      value = []
      description = "Placeholders restants à collecter"
    }

    var $placeholders_auto_remplis {
      value = {}
      description = "Placeholders auto-remplis depuis le contexte"
    }

    foreach ($input.placeholders_metadata) {
      each as $ph {
        conditional {
          if ($ph.auto_fill == true) {
            // Auto-fill depuis le contexte (commune, date du jour)
            // Ne pas poser la question
          }
          elseif ($input.donnees_collectees|has_key:($ph.id)) {
            // Déjà collecté, ne rien faire
          }
          else {
            // À collecter
            var.update $placeholders_manquants {
              value = $placeholders_manquants|push:$ph
            }
          }
        }
      }
    }

    // Vérifier si la collecte est terminée
    var $collecte_complete {
      value = (($placeholders_manquants|count) == 0)
    }

    // Générer le system prompt pour Mistral
    var $system_prompt {
      value = "Tu es Marianne, assistante IA des secrétariats de mairie. Tu aides à remplir un document administratif de type '" ~ $input.template_nom ~ "' pour la commune de " ~ $input.commune_nom ~ ".\n\nRègles :\n- Pose UNE SEULE question à la fois, de manière claire et professionnelle\n- Si l'utilisateur donne une réponse ambiguë, demande une clarification\n- Pour les dates, accepte les formats 'JJ/MM/AAAA' ou 'JJ mois AAAA'\n- Pour les nombres, accepte les chiffres avec ou sans unité\n- Confirme chaque réponse avant de passer à la suite\n- Sois bienveillante et aidante, les secrétaires de mairie ont souvent peu de temps"
    }

    // Déterminer la prochaine question
    var $prochaine_question {
      value = ""
    }

    conditional {
      if ($collecte_complete) {
        var.update $prochaine_question {
          value = "Toutes les informations nécessaires ont été collectées. Souhaitez-vous générer le document ou modifier certaines réponses ?"
        }
      }
      else {
        // Prendre le premier placeholder manquant
        var $prochain_ph {
          value = ($placeholders_manquants|first)
        }

        conditional {
          if ($prochain_ph.question_chatbot != null) {
            var.update $prochaine_question {
              value = $prochain_ph.question_chatbot
            }
          }
          else {
            var.update $prochaine_question {
              value = "Quelle est la valeur pour : " ~ $prochain_ph.label ~ " ?"
            }
          }
        }
      }
    }

    // Récapitulatif des données collectées pour le contexte
    var $recap {
      value = ""
    }

    conditional {
      if (($input.donnees_collectees|count) > 0) {
        var.update $recap {
          value = "\n\nDonnées déjà collectées :"
        }
        // Note: le récapitulatif détaillé sera ajouté côté API
      }
      else {
        // Pas encore de données
      }
    }

    var $result {
      value = {
        system_prompt: $system_prompt,
        prochaine_question: $prochaine_question,
        collecte_complete: $collecte_complete,
        nb_manquants: ($placeholders_manquants|count),
        nb_collectes: ($input.donnees_collectees|count),
        prochain_placeholder_id: ($placeholders_manquants|first).id ?? null
      }
    }
  }

  response = $result
}
