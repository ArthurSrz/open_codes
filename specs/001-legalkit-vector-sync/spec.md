# Spécification fonctionnelle : pipeline de synchronisation LegalKit → vecteurs

**Branche Feature** : `001-legalkit-vector-sync`
**Créé le** : 2026-01-24
**Statut** : Brouillon
**Entrée** : Description utilisateur : "Je veux un pipeline qui interroge le pipeline LegalKit et ajoute des vecteurs à jour dans Xano."

## Scénarios utilisateur & tests *(obligatoire)*

### User Story 1 - Import initial des codes juridiques (Priorité : P1)

En tant qu'administrateur système, je veux importer tous les codes juridiques français depuis LegalKit vers Xano afin que l'assistante IA Marianne puisse effectuer des recherches sémantiques sur des textes de loi à jour.

**Justification de la priorité** : C'est la capacité fondamentale - sans données juridiques importées, aucune recherche légale n'est possible. L'assistante IA Marianne dépend entièrement de ces données pour fournir des conseils juridiques précis aux secrétaires de mairie.

**Test Indépendant** : Peut être entièrement testé en déclenchant une tâche d'import et en vérifiant que les articles d'au moins un code juridique (ex: Code Civil) apparaissent dans la base de données avec des embeddings valides. Apporte une valeur immédiate en activant les recherches juridiques.

**Scénarios d'Acceptation** :

1. **Étant donné** une table REF_codes_legifrance vide, **Quand** le pipeline de synchronisation s'exécute pour la première fois, **Alors** les articles de tous les codes juridiques configurés sont importés avec leurs métadonnées (nom du code, partie, livre, titre, chapitre, section, numéro d'article, contenu)
2. **Étant donné** que des articles sont importés, **Quand** on vérifie le champ embeddings, **Alors** chaque article possède un vecteur valide de 1024 dimensions généré via l'API embeddings Mistral AI
3. **Étant donné** qu'un import est en cours, **Quand** une erreur survient sur un article spécifique, **Alors** le pipeline continue avec les articles restants et journalise l'erreur pour investigation ultérieure

---

### User Story 2 - Mises à jour incrémentales quotidiennes (Priorité : P2)

En tant qu'administrateur système, je veux que le pipeline détecte automatiquement et importe uniquement les articles modifiés ou nouveaux afin que la base juridique reste à jour sans tout réimporter.

**Justification de la priorité** : Les codes juridiques français sont régulièrement mis à jour. Les secrétaires de mairie ont besoin d'accéder aux dernières versions des articles pour fournir des informations précises aux administrés. Cela évite les conseils juridiques obsolètes.

**Test Indépendant** : Peut être testé en modifiant le contenu d'un article dans la source, en exécutant la synchronisation, et en vérifiant que seul l'article modifié est mis à jour tandis que les articles inchangés restent intacts.

**Scénarios d'Acceptation** :

1. **Étant donné** que des articles existent déjà dans la base de données, **Quand** le pipeline de synchronisation détecte un nouvel article dans LegalKit, **Alors** seul le nouvel article est importé avec de nouveaux embeddings
2. **Étant donné** que le contenu d'un article a changé dans LegalKit (champ texte différent), **Quand** le pipeline de synchronisation s'exécute, **Alors** le contenu de l'article et ses embeddings sont mis à jour tout en préservant l'ID de l'article
3. **Étant donné** qu'un article a été abrogé dans LegalKit (etat = "ABROGE"), **Quand** le pipeline de synchronisation s'exécute, **Alors** l'article est marqué comme inactif ou retiré de l'index de recherche actif

---

### User Story 3 - Monitoring et Statut de Synchronisation (Priorité : P3)

En tant qu'administrateur système, je veux surveiller la progression de la synchronisation et consulter l'historique des syncs afin de vérifier que le pipeline fonctionne correctement et résoudre les problèmes.

**Justification de la priorité** : La visibilité opérationnelle est importante pour maintenir la santé du système, mais le système peut fonctionner sans cela initialement.

**Test Indépendant** : Peut être testé en exécutant une synchronisation et en vérifiant que le statut, la progression et les logs de complétion sont accessibles.

**Scénarios d'Acceptation** :

1. **Étant donné** qu'une synchronisation est en cours, **Quand** je vérifie le statut de synchronisation, **Alors** je vois la progression actuelle (articles traités, articles restants, code en cours de traitement)
2. **Étant donné** qu'une synchronisation est terminée, **Quand** je consulte l'historique de synchronisation, **Alors** je vois les statistiques résumées (total articles importés, mis à jour, échoués, durée)
3. **Étant donné** qu'une synchronisation a rencontré des erreurs, **Quand** je consulte le journal de synchronisation, **Alors** je vois les informations d'erreur détaillées incluant les références des articles concernés

---

### Cas Limites

- Que se passe-t-il quand l'API PISTE est temporairement indisponible ?
  - Le pipeline réessaie avec backoff exponentiel (3 tentatives) puis journalise l'échec et envoie une alerte
- Que se passe-t-il quand le token OAuth2 PISTE expire en cours de synchronisation ?
  - Le pipeline détecte l'erreur 401 et rafraîchit automatiquement le token avant de reprendre
- Que se passe-t-il quand les limites de débit de l'API embeddings Mistral AI sont dépassées ?
  - Le pipeline implémente un rate limiting (respectant les limites API) et met en file d'attente les articles restants
- Que se passe-t-il quand un article contient un texte extrêmement long (>8 000 tokens Mistral) ?
  - Le système utilise un chunking intelligent basé sur les subdivisions hiérarchiques du code (sections, paragraphes) pour découper le texte en fragments sémantiquement cohérents. Chaque fragment conserve son contexte hiérarchique (fullSectionsTitre) et génère un embedding indépendant lié à l'article parent via id_legifrance.
- Que se passe-t-il quand la connexion à la base de données échoue en cours de synchronisation ?
  - Le pipeline utilise des lots transactionnels ; les lots échoués sont réessayés ou annulés proprement

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **EF-001** : Le système DOIT récupérer les codes juridiques français directement depuis l'API officielle PISTE (Légifrance) via OAuth2 client_credentials, en utilisant les endpoints `/tableMatieres` et `/getArticle`
- **EF-002** : Le système DOIT extraire l'ensemble des 38 champs de métadonnées disponibles dans le dataset LegalKit : identification (ref, num, id, cid, idEli, idEliAlias, idTexte, cidTexte), contenu (texte, texteHtml, nota, notaHtml, surtitre, historique), temporalité (dateDebut, dateFin, dateDebutExtension, dateFinExtension), statut juridique (etat, type, nature, origine), versioning (version_article, versionPrecedente, multipleVersions), hiérarchie (sectionParentId, sectionParentCid, sectionParentTitre, fullSectionsTitre, ordre), métadonnées techniques (idTechInjection, refInjection, numeroBo, inap), et informations complémentaires (infosComplementaires, infosComplementairesHtml, conditionDiffere, infosRestructurationBranche, infosRestructurationBrancheHtml, renvoi, comporteLiensSP)
- **EF-003** : Le système DOIT générer des embeddings de 1024 dimensions pour chaque article en utilisant l'API embeddings Mistral AI (modèle mistral-embed) à partir de la concaténation des champs `fullSectionsTitre` + `surtitre` + `texte` (contexte hiérarchique + contenu principal)
- **EF-004** : Le système DOIT stocker les articles dans la table REF_codes_legifrance avec toutes les métadonnées et embeddings
- **EF-005** : Le système DOIT détecter les changements d'articles en comparant les hashs de contenu entre les versions source et stockées
- **EF-006** : Le système DOIT supporter la synchronisation de codes juridiques configurables via la table LEX_codes_piste. Le périmètre Phase 1 (MVP) cible 5 codes prioritaires : Code de l'urbanisme (LEGITEXT000006074075), Code civil (LEGITEXT000006070721), Code des collectivités territoriales (LEGITEXT000006070633), Code des communes (LEGITEXT000006070162), Code électoral (LEGITEXT000006070239). L'extension aux ~98 codes disponibles via l'API PISTE est planifiée post-MVP.
- **EF-007** : Le système DOIT gérer la pagination et le streaming pour les grands datasets (certains codes ont des milliers d'articles)
- **EF-008** : Le système DOIT journaliser toutes les opérations de synchronisation avec horodatages, comptages d'articles et détails d'erreurs
- **EF-009** : Le système DOIT respecter les limites de débit de l'API Mistral AI pour éviter les interruptions de service
- **EF-010** : Le système DOIT être planifiable comme tâche récurrente (synchronisation quotidienne)
- **EF-011** : Le système DOIT stocker les deux formats (texte brut et HTML) pour les champs disposant des deux versions (texte/texteHtml, nota/notaHtml, infosComplementaires/infosComplementairesHtml, infosRestructurationBranche/infosRestructurationBrancheHtml) afin de permettre l'affichage riche et la recherche sur texte brut
- **EF-012** : Le système DOIT stocker NULL (et non une chaîne vide) pour les champs absents ou vides dans le dataset source
- **EF-013** : La table REF_codes_legifrance DOIT être étendue avec les 38 champs LegalKit et indexée sur les champs `idEli`, `etat`, `cid` pour optimiser les requêtes de filtrage par identifiant européen et statut juridique

### Entités Clés

- **ArticleJuridique (Source)** : Représente un article brut du dataset LegalKit avec l'ensemble des 38 champs disponibles :
  - *Identification* : `ref`, `num`, `id`, `cid`, `idEli`, `idEliAlias`, `idTexte`, `cidTexte`
  - *Contenu* : `texte`, `texteHtml`, `nota`, `notaHtml`, `surtitre`, `historique`
  - *Temporalité* : `dateDebut`, `dateFin`, `dateDebutExtension`, `dateFinExtension`
  - *Statut juridique* : `etat`, `type`, `nature`, `origine`
  - *Versioning* : `version_article`, `versionPrecedente`, `multipleVersions`
  - *Hiérarchie* : `sectionParentId`, `sectionParentCid`, `sectionParentTitre`, `fullSectionsTitre`, `ordre`
  - *Métadonnées techniques* : `idTechInjection`, `refInjection`, `numeroBo`, `inap`
  - *Informations complémentaires* : `infosComplementaires`, `infosComplementairesHtml`, `conditionDiffere`, `infosRestructurationBranche`, `infosRestructurationBrancheHtml`, `renvoi`, `comporteLiensSP`
- **REF_codes_legifrance (Cible)** : Table Xano stockant les articles avec tous les 38 champs LegalKit + embeddings Mistral 1024-dim pour recherche vectorielle
- **ExécutionSync** : Représente une exécution unique du pipeline de synchronisation avec statut, timing et statistiques
- **ErreurSync** : Enregistre les erreurs de traitement d'articles individuels avec contexte pour dépannage

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **CS-001** : Les 5 codes juridiques prioritaires (Code de l'urbanisme, Code civil, Code des collectivités territoriales, Code des communes, Code électoral - estimé ~15 000 articles) sont entièrement importés dans les 24 heures suivant le déploiement initial. L'extension aux ~98 codes disponibles via l'API PISTE est prévue en Phase post-MVP.
- **CS-002** : Les synchronisations incrémentales quotidiennes se terminent en moins de 30 minutes pour les mises à jour quotidiennes typiques
- **CS-003** : 99,5% des articles ont des embeddings valides (moins de 0,5% d'échecs de génération d'embeddings)
- **CS-004** : L'assistante IA Marianne peut retourner des articles juridiques pertinents pour 95% des requêtes légales (mesuré par seuil de similarité sémantique ≥0,8)
- **CS-005** : Les échecs de synchronisation sont détectés et alertés dans les 5 minutes suivant leur occurrence
- **CS-006** : Fraîcheur des articles : les articles importés reflètent les données source LegalKit datant de moins de 48 heures

## Clarifications

### Session 2026-01-24

- Q: Quels groupes de métadonnées voulez-vous stocker dans REF_codes_legifrance ? → A: Option D - Tous les 38 champs disponibles du dataset LegalKit
- Q: Comment gérer les champs vides et les doublons texte/HTML ? → A: Option B - Dual format (texte brut + HTML), NULL pour champs vides
- Q: Quels champs textuels inclure dans la génération des embeddings ? → A: Option B - Contenu + contexte (fullSectionsTitre + surtitre + texte)
- Q: Quelle stratégie de migration de schéma et d'indexation ? → A: Option B - Index ciblés sur idEli, etat, cid
- Q: Quels codes juridiques inclure dans le périmètre de synchronisation ? → A: Phase 1 MVP - 5 codes prioritaires (Code de l'urbanisme, Code civil, Code des collectivités territoriales, Code des communes, Code électoral). Extension post-MVP vers ~98 codes disponibles via API PISTE.
- Q: Source de données ? → A: API PISTE directe (datasets HuggingFace obsolètes depuis 6 mois)
- Q: Runtime d'exécution ? → A: XanoScript natif (pas de dépendance Python externe)

## Hypothèses

- L'API PISTE (Légifrance officiel) est disponible et fournit des données en temps réel depuis la source officielle
- L'API embeddings Mistral AI est disponible et les limites de débit sont suffisantes pour les volumes de synchronisation (estimé ~15 000 articles pour les 5 codes prioritaires MVP, extensible à 200 000+ articles pour les ~98 codes disponibles via l'API PISTE)
- Le schéma existant de la table REF_codes_legifrance est suffisant pour stocker toutes les métadonnées requises
- La connectivité réseau entre l'infrastructure Xano et Hugging Face/Mistral AI est fiable
- Les champs de structure hiérarchique dans REF_codes_legifrance (partie, livre, titre, etc.) peuvent être dérivés du champ fullSectionsTitre de LegalKit
