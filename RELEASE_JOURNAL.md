# Journal des releases — Database

<!-- release-journal-state {"dev": "306288842bdd1483804c1578fd5165108da58c6a", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-21 09:10 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `3062888` | 2026-10-21 09:10 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` : il n'a que les droits partagés (middleware JWT, `check_access`) et aucune table propre. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Promotion manuelle vers staging et prod via `promote-staging.yml` et `promote-prod.yml` (`workflow_dispatch`, `sha` optionnel, un seul run à la fois par cible). (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

#### Changements de comportement
- Un push sur `main` ne déploie plus ni staging ni prod : `cicd.yml` s'arrête à `release-dev`. Staging et prod se lancent à la main. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))
- L'e-mail des utilisateurs (`users.email`) est lisible par tous les rôles d'API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`). Avant, seul `core_api` le lisait. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Connexion avec un token Keycloak sur Project, Calendar, Message et ELearning : avant, la recherche du compte par e-mail échouait en `42501`. Maintenant, `id`, `email` et `is_archived` sont lisibles par chaque API et la recherche aboutit. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Promotion prod : avant, la release n'était pas publiée (v4.4.0), puis le run échouait sur une erreur 403 de l'API releases (v4.4.1), puis le push du tag était refusé faute de permission `workflows` (v4.4.2). Maintenant le tag et la release sont créés avec le token de l'app de release (v4.4.3). (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214))

#### Technique
- Montée de `mairie360/CICD` de v4.2.1 à v4.4.3 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml`. (MAIR-571, MAIR-494, MAIR-612, [#200](https://github.com/mairie360/Database/pull/200), [#202](https://github.com/mairie360/Database/pull/202), [#204](https://github.com/mairie360/Database/pull/204), [#207](https://github.com/mairie360/Database/pull/207), [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214))
- Ajout des secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK` pour l'étape de journal de release. (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202))
- Renovate suit `cicd_version` dans les trois workflows via un `customManagers`, et `-Dcompliance_api_password` est passé dans les docker-compose et le bench ; le test de rôles passe à 36 assertions. (MAIR-494 et MAIR-556, [#187](https://github.com/mairie360/Database/pull/187), [#207](https://github.com/mairie360/Database/pull/207))

## Différence dev → staging (en dev, pas encore en staging)

#### Corrections
- Promotion prod : avant, la release n'était pas publiée à cause d'une erreur 403 puis d'un push de tag refusé. Maintenant le tag et la release sont créés avec le token de l'app de release. (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214))

#### Technique
- Montée de `mairie360/CICD` de v4.4.0 à v4.4.3 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml`, sans autre changement de code. (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214))

## Différence staging → prod (en staging, pas encore en prod)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api`, avec les droits partagés uniquement. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Promotion manuelle vers staging et prod via `promote-staging.yml` et `promote-prod.yml`. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

#### Changements de comportement
- Un push sur `main` ne déploie plus staging ni prod, il s'arrête à `release-dev`. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))
- L'e-mail des utilisateurs est lisible par tous les rôles d'API, et plus seulement par `core_api`. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Connexion avec un token Keycloak sur Project, Calendar, Message et ELearning : avant, la recherche par e-mail échouait en `42501`, maintenant elle aboutit. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Montée de `mairie360/CICD` de v4.2.1 à v4.4.0 dans les workflows, avec ajout des secrets du journal de release (`ANTHROPIC_API_KEY`, `RELEASE_APP_ID`, `RELEASE_APP_PK`). (MAIR-571, MAIR-494, [#202](https://github.com/mairie360/Database/pull/202), [#204](https://github.com/mairie360/Database/pull/204), [#207](https://github.com/mairie360/Database/pull/207))
- Renovate suit `cicd_version` dans les trois workflows, et les docs de promotion sont ajoutées à `CLAUDE.md`. (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207))

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 09:10 UTC | dev | — | `3062888` | [run](https://github.com/mairie360/Database/actions/runs/39574431117) |
| 2026-10-21 08:27 UTC | dev | — | `db3c2a2` | [run](https://github.com/mairie360/Database/actions/runs/39568811813) |
| 2026-10-21 03:50 UTC | dev | — | `ef11982` | [run](https://github.com/mairie360/Database/actions/runs/39540422847) |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
