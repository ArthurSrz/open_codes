// API: Créer un nouveau template
// Endpoint: POST /api/admin_templates/creer_template
// Auth: JWT utilisateurs + gestionnaire
// Description: Upload un DOCX, extrait les placeholders, crée le template

query "admin_templates/creer_template" verb=POST {
  api_group = "admin_templates"
  auth = "utilisateurs"
  description = "Crée un nouveau template de document administratif"

  input {
    text nom {
      description = "Nom du template"
    }
    text description?="" {
      description = "Description du template"
    }
    int categorie_id {
      description = "ID de la catégorie"
    }
    attachment fichier_docx {
      description = "Fichier DOCX template avec {{placeholders}}"
    }
    json placeholders?=[] {
      description = "Métadonnées des placeholders (auto-détecté si vide)"
    }
    bool is_global?=false {
      description = "Template global accessible à toutes les communes"
    }
  }

  stack {
    // Vérifier que l'utilisateur est gestionnaire
    db.get "utilisateurs" {
      field_name = "id"
      field_value = $auth.id
    } as $user

    precondition ($user.gestionnaire == true || $user.role == "admin") {
      error_type = "accessdenied"
      error = "Accès réservé aux gestionnaires et administrateurs"
    }

    // Si placeholders non fournis, les extraire automatiquement du DOCX
    var $placeholders_final {
      value = $input.placeholders
    }

    conditional {
      if (($input.placeholders|count) == 0) {
        // Auto-extraction via le pipeline DOCX
        // Note: Inline car function.run nested peut bloquer
        api.request {
          url = $input.fichier_docx.url
          method = "GET"
        } as $docx_dl

        file.unzip {
          content = $docx_dl.response.result
        } as $zip

        var $xml {
          value = ""
        }

        foreach ($zip) {
          each as $f {
            conditional {
              if ($f.name == "word/document.xml") {
                var.update $xml {
                  value = $f.content
                }
              }
              else {
                // skip
              }
            }
          }
        }

        // Extraire les placeholders via regex
        var $matches {
          value = ($xml|regex_match_all:"\\{\\{(\\w+)\\}\\}")
        }

        var $ids_vus {
          value = []
        }

        foreach ($matches) {
          each as $m {
            var $pid {
              value = $m.1
            }
            conditional {
              if (!($ids_vus|contains:$pid)) {
                var.update $ids_vus {
                  value = $ids_vus|push:$pid
                }
                var.update $placeholders_final {
                  value = $placeholders_final|push:{
                    id: $pid,
                    label: ($pid|replace:"_":" "|capitalize),
                    type: "text",
                    required: true
                  }
                }
              }
              else {
                // Déjà vu
              }
            }
          }
        }
      }
      else {
        // Utiliser les placeholders fournis
      }
    }

    // Créer le template
    db.add templates_documents_administratifs {
      data = {
        nom: $input.nom,
        description: $input.description,
        categorie_id: $input.categorie_id,
        communes_id: $user.communes_id,
        is_global: $input.is_global,
        fichier_docx: $input.fichier_docx,
        placeholders: $placeholders_final,
        version: 1,
        actif: true,
        valide_reglementairement: false,
        cree_par: $auth.id,
        created_at: "now"
      }
    } as $template

    var $result {
      value = {
        template_id: $template.id,
        nom: $input.nom,
        placeholders_detectes: ($placeholders_final|count),
        placeholders: $placeholders_final,
        message: "Template créé avec succès. " ~ ($placeholders_final|count) ~ " placeholders détectés."
      }
    }
  }

  response = $result
}
