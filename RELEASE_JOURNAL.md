# Journal des releases — Database

<!-- release-journal-state {"dev": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-21 01:37 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `1706a71` | 2026-10-21 01:37 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` (`api_roles.sql`), avec les seuls droits partagés (lecture de `users (id, email, is_archived)` et `EXECUTE` sur `check_access`) : il n'a pas encore de table propre. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Changements de comportement
- La lecture de `users.email` est désormais accordée à tous les rôles API (`project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api` en plus de `core_api`), au lieu de `core_api` seul. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Les jetons Keycloak sur Project, Calendar, Message et ELearning échouaient : la recherche du compte par e-mail (`get_user_id_by_email`) répondait `42501` faute de droit SELECT sur `users.email`. Maintenant le droit est accordé à chaque API et la correspondance fonctionne. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- `cicd.yml` passe à mairie360/CICD v4.4.0 : un push sur `main` s'arrête à `release-dev`. Staging et prod sont désormais promus à la main via `promote-staging.yml` et `promote-prod.yml` (une promotion à la fois par cible). (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))
- Montée de CICD v4.2.2 à v4.3.1 (journal des releases, secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID`, `RELEASE_APP_PK` ajoutés), puis mises à jour Renovate v4.2.2 et v4.3.2 et gestionnaire personnalisé `cicd_version` dans `renovate.json`. (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202), [#200](https://github.com/mairie360/Database/pull/200), [#204](https://github.com/mairie360/Database/pull/204))
- Tests de rôles `20_api_roles_test.sql` passés de 33 à 36 assertions ; les tests API tournent sous le rôle de leur API ; mot de passe `compliance_api` ajouté aux compose et au bench ; `CLAUDE.md` documente la promotion. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187), MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

## Différence dev → staging (en dev, pas encore en staging)

_Rien._

## Différence staging → prod (en staging, pas encore en prod)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` (`api_roles.sql`), avec les seuls droits partagés (lecture de `users (id, email, is_archived)` et `EXECUTE` sur `check_access`) : il n'a pas encore de table propre. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Changements de comportement
- La lecture de `users.email` est désormais accordée à tous les rôles API (`project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api` en plus de `core_api`), au lieu de `core_api` seul. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Les jetons Keycloak sur Project, Calendar, Message et ELearning échouaient : la recherche du compte par e-mail (`get_user_id_by_email`) répondait `42501` faute de droit SELECT sur `users.email`. Maintenant le droit est accordé à chaque API et la correspondance fonctionne. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- `cicd.yml` passe à mairie360/CICD v4.4.0 : un push sur `main` s'arrête à `release-dev`. Staging et prod sont désormais promus à la main via `promote-staging.yml` et `promote-prod.yml` (une promotion à la fois par cible). (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))
- Montée de CICD v4.2.2 à v4.3.1 (journal des releases, secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID`, `RELEASE_APP_PK` ajoutés), puis mises à jour Renovate v4.2.2 et v4.3.2 et gestionnaire personnalisé `cicd_version` dans `renovate.json`. (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202), [#200](https://github.com/mairie360/Database/pull/200), [#204](https://github.com/mairie360/Database/pull/204))
- Tests de rôles `20_api_roles_test.sql` passés de 33 à 36 assertions ; les tests API tournent sous le rôle de leur API ; mot de passe `compliance_api` ajouté aux compose et au bench ; `CLAUDE.md` documente la promotion. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187), MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
