// API: Historique des documents générés
// Endpoint: GET /api/doc_generator/historique_documents_generes
// Auth: JWT utilisateurs (commune-scoped)
// Description: Liste paginée des documents générés par l'utilisateur

query "doc_generator/historique_documents_generes" verb=GET {
  api_group = "doc_generator"
  auth = "utilisateurs"
  description = "Historique paginé des documents générés par l'utilisateur"

  input {
    int page?=1 {
      description = "Numéro de page"
    }
    int per_page?=20 {
      description = "Résultats par page"
    }
    text statut?="" {
      description = "Filtrer par statut (brouillon, finalise, signe)"
    }
  }

  stack {
    // Récupérer l'utilisateur
    db.get "utilisateurs" {
      field_name = "id"
      field_value = $auth.id
    } as $user

    // Requête documents générés - scopé commune
    conditional {
      if ($input.statut != "") {
        db.query "documents_generes" {
          where = ($db.documents_generes.communes_id == $user.communes_id)
            && ($db.documents_generes.statut == $input.statut)
          sort = {created_at: "desc"}
          return = {
            type: "list"
            paging: {
              page: $input.page,
              per_page: $input.per_page
            }
          }
        } as $documents
      }
      else {
        db.query "documents_generes" {
          where = ($db.documents_generes.communes_id == $user.communes_id)
          sort = {created_at: "desc"}
          return = {
            type: "list"
            paging: {
              page: $input.page,
              per_page: $input.per_page
            }
          }
        } as $documents
      }
    }

    var $result {
      value = {
        documents: $documents,
        page: $input.page,
        per_page: $input.per_page,
        total: ($documents|count)
      }
    }
  }

  response = $result
}
