# Journal des releases — Database

<!-- release-journal-state {"dev": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "5fe90c1df8f337fc22e88966780bc518b7220251", "updated": {"dev": "2026-10-21 01:37 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `5fe90c1` | — |
| dev | — | `1706a71` | 2026-10-21 01:37 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)) : il n'a que les droits partagés (lecture de `users (id, email, is_archived)` et `check_access()`) et aucune table propre.
- Nouveaux workflows manuels `promote-staging.yml` et `promote-prod.yml` pour promouvoir un commit de `main` vers staging puis vers prod (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).

#### Changements de comportement
- Un push sur `main` ne déclenche plus que la release dev : staging et prod ne sont plus livrés automatiquement et passent par les workflows de promotion manuels (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).
- La colonne `users.email` devient lisible par tous les rôles API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) ; seul `core_api` la lisait auparavant. Le test 25 vérifie désormais `phone_number` à la place de `email` pour `message_api` (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

#### Corrections
- Les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning : la recherche de l'utilisateur par e-mail (`get_user_id_by_email`) échouait avec l'erreur `42501` (permission denied). Maintenant la lecture de `users.email` est accordée et la recherche aboutit (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

#### Technique
- Mise à jour de la référence mairie360/CICD : v4.2.2 (MAIR-571 [#202](https://github.com/mairie360/Database/pull/202), [#200](https://github.com/mairie360/Database/pull/200)), v4.3.1 avec le journal de release rédigé par Claude (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202)), v4.3.2 ([#204](https://github.com/mairie360/Database/pull/204)) puis v4.4.0 (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)). Aucun effet sur les données ou l'API.
- Renovate : regex `customManagers` pour suivre `cicd_version` dans les trois workflows (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).
- Tests pgTAP `20_api_roles_test.sql` étendus de 33 à 36 tests ; mots de passe `compliance_api` ajoutés aux docker-compose et au bench (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)) : il n'a que les droits partagés (lecture de `users (id, email, is_archived)` et `check_access()`) et aucune table propre.
- Nouveaux workflows manuels `promote-staging.yml` et `promote-prod.yml` pour promouvoir un commit de `main` vers staging puis vers prod (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).

#### Changements de comportement
- Un push sur `main` ne déclenche plus que la release dev : staging et prod ne sont plus livrés automatiquement et passent par les workflows de promotion manuels (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).
- La colonne `users.email` devient lisible par tous les rôles API (`core_api`, `project_api`, `calendar_api`, `message_api`, `elearning_api`, `compliance_api`) ; seul `core_api` la lisait auparavant. Le test 25 vérifie désormais `phone_number` à la place de `email` pour `message_api` (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

#### Corrections
- Les jetons Keycloak ne fonctionnaient pas sur Project, Calendar, Message et ELearning : la recherche de l'utilisateur par e-mail (`get_user_id_by_email`) échouait avec l'erreur `42501` (permission denied). Maintenant la lecture de `users.email` est accordée et la recherche aboutit (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

#### Technique
- Mise à jour de la référence mairie360/CICD : v4.2.2 (MAIR-571 [#202](https://github.com/mairie360/Database/pull/202), [#200](https://github.com/mairie360/Database/pull/200)), v4.3.1 avec le journal de release rédigé par Claude (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202)), v4.3.2 ([#204](https://github.com/mairie360/Database/pull/204)) puis v4.4.0 (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)). Aucun effet sur les données ou l'API.
- Renovate : regex `customManagers` pour suivre `cicd_version` dans les trois workflows (MAIR-494, [#207](https://github.com/mairie360/Database/pull/207)).
- Tests pgTAP `20_api_roles_test.sql` étendus de 33 à 36 tests ; mots de passe `compliance_api` ajoutés aux docker-compose et au bench (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187)).

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
