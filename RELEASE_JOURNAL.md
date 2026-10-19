# Journal des releases — Database

<!-- release-journal-state {"dev": "34b523002d5c9b44011bd4c4bc1b795fa8c84bc6", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "5fe90c1df8f337fc22e88966780bc518b7220251", "updated": {"dev": "2026-10-19 20:05 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `5fe90c1` | — |
| dev | — | `34b5230` | 2026-10-19 20:05 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres de connexion `compliance_api` pour Compliance_API. Son mot de passe est fourni par le paramètre Liquibase `-Dcompliance_api_password` ; sans ce paramètre, le rôle est créé `NOLOGIN`. Il ne reçoit que les droits communs à toutes les API : `SELECT (id, email, is_archived)` sur `users` et `EXECUTE` sur `check_access(INT, VARCHAR, VARCHAR, INT)`. Il n'écrit dans aucune table et ne lit pas les noms des utilisateurs. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Avant, seul `core_api` pouvait lire `users.email` : la recherche du compte associé à un jeton Keycloak (`get_user_id_by_email`) échouait en `42501`, et les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning. Maintenant, tous les rôles d'API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) lisent `users (id, email, is_archived)`. Les droits spécifiques sur `users` se limitent désormais à `first_name, last_name` pour `project_api`, `message_api` et `elearning_api`. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Tests pgTAP des rôles d'API étendus à six rôles (plan de 33 à 36), avec un test de la recherche par e-mail et un test du périmètre de `compliance_api`. Le paramètre `-Dcompliance_api_password` est ajouté aux fichiers docker-compose, au bench et aux tests de montée de version, et `CLAUDE.md` est mis à jour. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Workflow `mairie360/CICD` mis à jour en deux étapes : d'abord en v4.2.2, puis en v4.3.1, qui ajoute l'étape de journal des releases et les secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK`. ([#200](https://github.com/mairie360/Database/pull/200), MAIR-571, [#202](https://github.com/mairie360/Database/pull/202))

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Nouveau rôle Postgres de connexion `compliance_api` pour Compliance_API. Son mot de passe est fourni par le paramètre Liquibase `-Dcompliance_api_password` ; sans ce paramètre, le rôle est créé `NOLOGIN`. Il ne reçoit que les droits communs à toutes les API : `SELECT (id, email, is_archived)` sur `users` et `EXECUTE` sur `check_access(INT, VARCHAR, VARCHAR, INT)`. Il n'écrit dans aucune table et ne lit pas les noms des utilisateurs. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Avant, seul `core_api` pouvait lire `users.email` : la recherche du compte associé à un jeton Keycloak (`get_user_id_by_email`) échouait en `42501`, et les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning. Maintenant, tous les rôles d'API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) lisent `users (id, email, is_archived)`. Les droits spécifiques sur `users` se limitent désormais à `first_name, last_name` pour `project_api`, `message_api` et `elearning_api`. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Tests pgTAP des rôles d'API étendus à six rôles (plan de 33 à 36), avec un test de la recherche par e-mail et un test du périmètre de `compliance_api`. Le paramètre `-Dcompliance_api_password` est ajouté aux fichiers docker-compose, au bench et aux tests de montée de version, et `CLAUDE.md` est mis à jour. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Workflow `mairie360/CICD` mis à jour en deux étapes : d'abord en v4.2.2, puis en v4.3.1, qui ajoute l'étape de journal des releases et les secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK`. ([#200](https://github.com/mairie360/Database/pull/200), MAIR-571, [#202](https://github.com/mairie360/Database/pull/202))

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
