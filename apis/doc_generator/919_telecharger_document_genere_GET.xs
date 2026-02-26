// API: Télécharger un document généré
// Endpoint: GET /api/doc_generator/telecharger_document_genere
// Auth: JWT utilisateurs (commune-scoped)
// Description: Retourne le fichier DOCX d'un document généré

query "doc_generator/telecharger_document_genere" verb=GET {
  api_group = "doc_generator"
  auth = "utilisateurs"
  description = "Télécharge le fichier DOCX d'un document généré"

  input {
    int document_id {
      description = "ID du document à télécharger"
    }
  }

  stack {
    // Récupérer le document
    db.get "documents_generes" {
      field_name = "id"
      field_value = $input.document_id
    } as $document

    precondition ($document != null) {
      error_type = "notfound"
      error = "Document non trouvé"
    }

    // Vérifier l'accès commune
    db.get "utilisateurs" {
      field_name = "id"
      field_value = $auth.id
    } as $user

    precondition ($document.communes_id == $user.communes_id) {
      error_type = "accessdenied"
      error = "Vous n'avez pas accès à ce document"
    }

    // Audit log du téléchargement
    db.add LOG_generation_documents {
      data = {
        document_id: $document.id,
        template_id: $document.template_id,
        utilisateur_id: $auth.id,
        action: "telechargement",
        statut: "succes",
        created_at: "now"
      }
    } as $log

    var $result {
      value = {
        document_id: $document.id,
        titre: $document.titre,
        statut: $document.statut,
        fichier_docx: $document.fichier_docx,
        created_at: $document.created_at
      }
    }
  }

  response = $result
}
