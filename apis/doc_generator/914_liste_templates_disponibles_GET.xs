// API: Liste des templates disponibles
// Endpoint: GET /api/doc_generator/liste_templates_disponibles
// Auth: JWT utilisateurs (commune-scoped)
// Description: Retourne les templates actifs accessibles par l'utilisateur
//   (templates de sa commune + templates globaux)
//   Note: || (OR) non supporté dans where → split en 2 queries + merge

query "doc_generator/liste_templates_disponibles" verb=GET {
  api_group = "Doc Generator"
  auth = "utilisateurs"

  input {
    // Filtrer par catégorie (0 = toutes)
    int categorie_id?
  }

  stack {
    db.get utilisateurs {
      field_name = "id"
      field_value = $auth.id
    } as $user

    // Query 1: templates de la commune
    db.query templates_documents_administratifs {
      where = $db.templates_documents_administratifs.actif == true && $db.templates_documents_administratifs.communes_id == $user.commune_id
      sort = {nom: "asc"}
      return = {type: "list", paging: {page: 1, per_page: 50}}
    } as $templates_commune

    // Query 2: templates globaux
    db.query templates_documents_administratifs {
      where = $db.templates_documents_administratifs.actif == true && $db.templates_documents_administratifs.is_global == true
      sort = {nom: "asc"}
      return = {type: "list", paging: {page: 1, per_page: 50}}
    } as $templates_globaux

    // Fusionner les résultats
    var $templates {
      value = $templates_commune|merge:$templates_globaux
    }
  }

  response = $templates
}
