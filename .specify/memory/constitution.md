<!--
================================================================================
RAPPORT D'IMPACT DE SYNCHRONISATION
================================================================================
Version : N/A → 1.0.0 (création initiale)
Principes modifiés : Aucun (création)
Sections ajoutées :
  - 5 principes architecturaux (Données, IA/LLM, Sécurité, API, Observabilité)
  - Contraintes techniques XanoScript
  - Workflow de développement
  - Gouvernance standard
Sections supprimées : Aucune
Templates nécessitant mise à jour :
  - .specify/templates/plan-template.md : ✅ Compatible (Constitution Check existant)
  - .specify/templates/spec-template.md : ✅ Compatible (structure user stories)
  - .specify/templates/tasks-template.md : ✅ Compatible (phases parallélisables)
TODOs différés : Aucun
================================================================================
-->

# Constitution marIAnne

## Principes Fondamentaux

### I. Architecture Données-Centrée

Toute donnée DOIT être scopée au niveau de la **Commune**. La Commune est l'entité pivot du modèle d'autorisation - aucune requête ne peut contourner cette isolation.

**Règles non-négociables :**
- Chaque table utilisateur DOIT inclure une relation `communes_id` (directe ou transitive)
- Les requêtes `db.query` DOIVENT filtrer par `commune_id` sauf pour les tables de référence (`LEX_*`)
- Le partage inter-communes (EPCI) est optionnel et explicite via flag de visibilité
- Les embeddings vectoriels (1024-dim) DOIVENT utiliser `vector_ip_ops` pour la recherche par similarité

**Rationale :** Les secrétariats de mairie manipulent des données sensibles (RGPD). L'isolation par commune garantit qu'aucune fuite de données ne peut survenir entre collectivités.

### II. Intégration IA/LLM Contrainte

L'assistant Marianne utilise **Mistral AI** avec des contraintes strictes de comportement. Le système MCP orchestre les appels d'outils sans jamais exposer les données brutes au modèle.

**Règles non-négociables :**
- Le system prompt DOIT interdire : accès web, mémorisation cross-session, hallucinations
- La température DOIT rester ≤ 0.3 pour garantir la cohérence des réponses juridiques
- Les outils MCP DOIVENT retourner des résultats que Mistral restitue **verbatim** (pas de reformulation)
- Le seuil de similarité vectorielle DOIT être ≥ 0.8 pour les recherches Légifrance
- Limite de 3 résultats maximum par recherche légale pour éviter la surcharge contextuelle

**Rationale :** Les informations juridiques requièrent une précision absolue. Une reformulation par le LLM pourrait altérer le sens légal d'un article de code.

### III. Sécurité et Autorisation

L'authentification JWT avec enrichissement contextuel (commune_id, gestionnaire) DOIT être appliquée à tout endpoint non-public.

**Règles non-négociables :**
- Chaque endpoint `apis/` DOIT déclarer `auth = "utilisateurs"` sauf exceptions documentées
- Le token JWT DOIT inclure `commune_id` et `gestionnaire` dans les extras
- Durée de vie token : 24 heures maximum
- Les endpoints magic_link DOIVENT expirer en 15 minutes
- Aucun mot de passe ne peut être stocké en clair (bcrypt obligatoire)

**Rationale :** Les données municipales sont sensibles. Un accès non autorisé pourrait compromettre la confiance des administrés.

### IV. Contrat API WeWeb

Les endpoints REST DOIVENT suivre une convention stricte pour garantir l'intégration fluide avec le frontend WeWeb.

**Règles non-négociables :**
- Nommage : `{numero}_{action}_{entite}_{VERBE}.xs` (ex: `908_marianne_editer_conversation_POST.xs`)
- Groupe API : DOIT correspondre au répertoire (`apis/ai/` → `api_group = "AI"`)
- Réponses : timestamps formatés Europe/Paris, URLs complètes pour les images
- Erreurs : codes HTTP standards (400, 401, 403, 404, 500) avec messages en français
- Addons : UNIQUEMENT un seul `db.query` par addon (pas de logique conditionnelle)

**Rationale :** WeWeb est un outil no-code. Les développeurs frontend ont besoin de contrats API prévisibles et auto-documentés.

### V. Observabilité et Traçabilité

Chaque opération critique DOIT être traçable pour le débogage et l'audit.

**Règles non-négociables :**
- Les conversations IA DOIVENT persister tous les messages (user + assistant) avec index d'ordre
- Les créations/modifications DOIVENT inclure `created_at` avec timestamp `"now"`
- Les suppressions DOIVENT utiliser soft-delete (`deleted` flag) sauf pour les données éphémères
- Les erreurs d'appel Mistral DOIVENT être loguées avec le contexte de requête

**Rationale :** Sans traçabilité, le débogage de problèmes IA devient impossible. Les audits RGPD requièrent un historique des accès.

## Contraintes Techniques XanoScript

### Syntaxe et Style

- Les commentaires DOIVENT être sur leur propre ligne avec `//`
- Les expressions chaînées DOIVENT être décomposées en variables intermédiaires si > 3 opérations
- Les blocs `conditional` DOIVENT avoir un `else` explicite même si vide (pour clarté)
- Les variables DOIVENT utiliser le préfixe `$` (ex: `$conversation_id`)

### Patterns Requis

```
// Pattern standard pour endpoint authentifié
query "groupe/action" verb=VERBE {
  api_group = "GROUPE"
  auth = "utilisateurs"

  input { ... }

  stack {
    // 1. Validation entrées
    // 2. Logique métier
    // 3. Opérations DB
    // 4. Formatage réponse
  }

  response { ... }
}
```

### Intégration Mistral

- Endpoint : `https://api.mistral.ai/v1/chat/completions`
- Embeddings : `https://api.mistral.ai/v1/embeddings` avec modèle `mistral-embed`
- Modèle chat : `mistral-small-latest`
- Headers : `Authorization: Bearer $env.MISTRAL_API_KEY`

## Workflow de Développement

### Séquence de Création

1. **Tables** : Créer sans cross-references, puis ajouter les relations
2. **Fonctions** : Extraire la logique réutilisable dans `/functions/`
3. **Outils MCP** : Implémenter dans `/tools/` avec schema JSON strict
4. **Endpoints API** : Créer dans le groupe approprié avec numérotation séquentielle
5. **Addons** : Optimiser les requêtes N+1 dans `/addons/`

### Délégation aux Agents Spécialisés

- **Xano Table Designer** : Schéma et relations de tables
- **Xano Function Writer** : Logique métier réutilisable
- **Xano API Query Writer** : Endpoints REST
- **Xano AI Builder** : Outils MCP et agents IA
- **Xano Addon Writer** : Optimisation des requêtes
- **Xano Unit Test Writer** : Tests avec assertions `expect`

L'orchestrateur (Claude) NE DOIT PAS écrire de XanoScript directement - il délègue aux agents spécialisés.

## Gouvernance

### Procédure d'Amendement

1. Proposition documentée avec rationale
2. Validation de non-régression sur les principes existants
3. Mise à jour de la version selon semantic versioning :
   - MAJEUR : Suppression/redéfinition de principe
   - MINEUR : Ajout de principe ou expansion significative
   - PATCH : Clarifications, corrections typographiques
4. Propagation aux templates dépendants

### Conformité

- Toute PR DOIT être validée contre cette constitution avant merge
- Revue de conformité mensuelle recommandée
- Les violations DOIVENT être documentées dans `Complexity Tracking` du plan.md
- Le fichier `troubleshooting.md` DOIT être mis à jour après résolution de bugs

### Ontologie Computationnelle

L'ontologie `marianne_computational_ontology` sur Grafo (ID: `b45711d8-e2a6-4e9e-9091-4c6b6231b764`) DOIT être consultée avant toute modification architecturale. Elle modélise :
- Entités : Utilisateur, Commune, ConversationIA, MessageIA, ArticleLegifrance, ArticleChunk, OutilMCP, ServeurMCP, APIEndpoint, CodeJuridiquePISTE, OrchestreurClientSide, SyncExecution, TemplateDocumentAdministratif, TemplatePlaceholder, DocumentGenere, CategorieTemplate, SessionGenerationDocument
- Relations : appartientA, initie, contient, expose, interroge, consomme, invoque, genereDepuis, generePar, contientPlaceholders, classeeDans, collecteDonneesPour, CHUNKED_FROM, synchronise, produit, utiliseTemplate, produitDocument, demarre

**Version** : 1.2.0 | **Ratifiée** : 2026-01-24 | **Dernière modification** : 2026-02-07
