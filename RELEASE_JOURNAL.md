# Journal des releases — Database

<!-- release-journal-state {"dev": "db3c2a2bc1288974ffacc84f71804965df74c39b", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-21 08:27 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `db3c2a2` | 2026-10-21 08:27 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés

- Nouveau rôle Postgres `compliance_api` (mot de passe via `-Dcompliance_api_password`), limité aux droits partagés : lecture de `users (id, email, is_archived)` et `check_access()`. Il n'a pas encore de table propre. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Changements de comportement

- Tous les rôles d'API lisent désormais `users.email` (en plus de `id` et `is_archived`). Auparavant seul `core_api` pouvait lire l'e-mail. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Un push sur `main` ne déclenche plus la promotion vers Staging ni Prod : `cicd.yml` s'arrête à `release-dev`, et la promotion se lance à la main via `promote-staging.yml` et `promote-prod.yml`. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

#### Corrections

- Avant : un jeton Keycloak ne pouvait pas être rattaché à son compte sur Project, Calendar, Message et ELearning (erreur `42501` sur la lecture de l'e-mail) ; seul `core_api` fonctionnait. Maintenant : la correspondance par e-mail est accordée à toutes les APIs. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique

- Épinglage de `mairie360/CICD` mis à jour à plusieurs reprises : v4.2.2 (Renovate, [#200](https://github.com/mairie360/Database/pull/200)), v4.3.1 avec l'étape de journal de releases et ses secrets (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202)), v4.3.2 ([#204](https://github.com/mairie360/Database/pull/204)), v4.4.0 ([#207](https://github.com/mairie360/Database/pull/207)), v4.4.1 ([#210](https://github.com/mairie360/Database/pull/210)) puis v4.4.2 ([#212](https://github.com/mairie360/Database/pull/212)).
- Renovate regroupe la mise à jour de `cicd_version` dans les trois workflows (`renovate.json`) ; `CLAUDE.md` documente la promotion et les rôles API. Les tests pgTAP `20_api_roles_test.sql` passent de 33 à 36 tests. Le diff de #187 est tronqué, la fin n'a pas été vérifiée.

## Différence dev → staging (en dev, pas encore en staging)

#### Technique

- Épinglage de `mairie360/CICD` passé de v4.4.0 à v4.4.1 (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210)), puis de v4.4.1 à v4.4.2 (MAIR-612, [#212](https://github.com/mairie360/Database/pull/212)) dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml`. Le correctif de v4.4.2 concerne la création du tag et de la release par `promote-prod` (HTTP 403 avec v4.4.1). Aucun effet visible sur dev ou staging.

## Différence staging → prod (en staging, pas encore en prod)

#### Changements de comportement

- Un push sur `main` ne déclenche plus la promotion vers Staging ni Prod : `cicd.yml` s'arrête à `release-dev`, et la promotion se lance à la main via `promote-staging.yml` et `promote-prod.yml`. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))
- Tous les rôles d'API lisent désormais `users.email` (en plus de `id` et `is_archived`). Auparavant seul `core_api` pouvait lire l'e-mail. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections

- Avant : un jeton Keycloak ne pouvait pas être rattaché à son compte sur Project, Calendar, Message et ELearning (erreur `42501` sur la lecture de l'e-mail). Maintenant : la correspondance par e-mail est accordée à toutes les APIs. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Nouveautés

- Nouveau rôle Postgres `compliance_api`, limité aux droits partagés (lecture de `users (id, email, is_archived)` et `check_access()`). (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique

- Épinglage de `mairie360/CICD` en v4.3.2 ([#204](https://github.com/mairie360/Database/pull/204)), puis v4.4.0 ([#207](https://github.com/mairie360/Database/pull/207)) et ajout des secrets du journal de releases en v4.3.1 (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202)).
- Renovate regroupe la mise à jour de `cicd_version` dans les trois workflows (`renovate.json`) ; `CLAUDE.md` documente la promotion et les rôles API. Le diff de #187 est tronqué, la fin n'a pas été vérifiée.

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 08:27 UTC | dev | — | `db3c2a2` | [run](https://github.com/mairie360/Database/actions/runs/39568811813) |
| 2026-10-21 03:50 UTC | dev | — | `ef11982` | [run](https://github.com/mairie360/Database/actions/runs/39540422847) |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
