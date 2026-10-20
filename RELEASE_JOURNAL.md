# Journal des releases — Database

<!-- release-journal-state {"dev": "cb09f0802b4e043ae9a9e6ef882f4f3fd6aa4dad", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "5fe90c1df8f337fc22e88966780bc518b7220251", "updated": {"dev": "2026-10-20 19:11 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `5fe90c1` | — |
| dev | — | `cb09f08` | 2026-10-20 19:11 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres de connexion `compliance_api`, dont le mot de passe vient du paramètre `-Dcompliance_api_password`. Sans ce paramètre, le rôle est créé `NOLOGIN`. Il n'a que les droits communs à toutes les API : `SELECT (id, email, is_archived)` sur `users` et `EXECUTE` sur `check_access`. Il n'écrit dans aucune table et ne lit pas les noms. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Un jeton d'accès Keycloak est de nouveau rattaché à son compte par e-mail (`get_user_id_by_email`) sur toutes les API. Avant, cette recherche échouait avec l'erreur `42501` partout sauf sur `core_api`, donc les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning. Désormais, tous les rôles d'API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) peuvent lire `users (id, email, is_archived)`. Les droits propres à chaque API sur `users` se limitent maintenant à `first_name` et `last_name` (pour `project_api`, `message_api` et `elearning_api`). (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Trois montées de version du workflow `mairie360/CICD` : de v4.2.1 à v4.2.2, puis v4.3.1, puis v4.3.2. Elles ajoutent l'étape de journal des releases et les secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK`. Après la dernière montée, l'input `cicd_version` reste à `v4.3.1` alors que la référence du workflow est `v4.3.2`. (MAIR-571, [#200](https://github.com/mairie360/Database/pull/200), [#202](https://github.com/mairie360/Database/pull/202), [#204](https://github.com/mairie360/Database/pull/204))
- Les tests pgTAP `20_api_roles_test.sql` passent à 36 tests et couvrent `compliance_api`. Le paramètre `-Dcompliance_api_password` est ajouté aux docker-compose, au bench et au script d'upgrade, et `CLAUDE.md` est mis à jour. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Nouveau rôle Postgres de connexion `compliance_api`, dont le mot de passe vient du paramètre `-Dcompliance_api_password`. Sans ce paramètre, le rôle est créé `NOLOGIN`. Il n'a que les droits communs à toutes les API : `SELECT (id, email, is_archived)` sur `users` et `EXECUTE` sur `check_access`. Il n'écrit dans aucune table et ne lit pas les noms. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Un jeton d'accès Keycloak est de nouveau rattaché à son compte par e-mail (`get_user_id_by_email`) sur toutes les API. Avant, cette recherche échouait avec l'erreur `42501` partout sauf sur `core_api`, donc les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning. Désormais, tous les rôles d'API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) peuvent lire `users (id, email, is_archived)`. Les droits propres à chaque API sur `users` se limitent maintenant à `first_name` et `last_name` (pour `project_api`, `message_api` et `elearning_api`). (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Trois montées de version du workflow `mairie360/CICD` : de v4.2.1 à v4.2.2, puis v4.3.1, puis v4.3.2. Elles ajoutent l'étape de journal des releases et les secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK`. Après la dernière montée, l'input `cicd_version` reste à `v4.3.1` alors que la référence du workflow est `v4.3.2`. (MAIR-571, [#200](https://github.com/mairie360/Database/pull/200), [#202](https://github.com/mairie360/Database/pull/202), [#204](https://github.com/mairie360/Database/pull/204))
- Les tests pgTAP `20_api_roles_test.sql` passent à 36 tests et couvrent `compliance_api`. Le paramètre `-Dcompliance_api_password` est ajouté aux docker-compose, au bench et au script d'upgrade, et `CLAUDE.md` est mis à jour. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
