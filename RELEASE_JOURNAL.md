# Journal des releases — Database

<!-- release-journal-state {"dev": "306288842bdd1483804c1578fd5165108da58c6a", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-21 09:10 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `3062888` | 2026-10-21 09:10 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

#### Technique
- Montée du pin CICD de v4.4.0 à v4.4.3 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml` (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)) : aucun effet sur l'API, le BFF, le front ni le schéma, seul le pipeline de release change.
- Corrections successives du job `promote-prod` côté CICD : la release qui n'était jamais publiée (v4.4.1), la création de la release en HTTP 403 (v4.4.2), puis le push du tag refusé faute de permission `workflows` (v4.4.3, poussé avec le token de l'app release).

## Différence dev → staging (en dev, pas encore en staging)

#### Technique
- Montée du pin CICD de v4.4.0 à v4.4.3 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml` (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)) : aucun effet sur l'API, le BFF, le front ni le schéma, seul le pipeline de release change.
- Corrections successives du job `promote-prod` côté CICD : la release qui n'était jamais publiée (v4.4.1), la création de la release en HTTP 403 (v4.4.2), puis le push du tag refusé faute de permission `workflows` (v4.4.3, poussé avec le token de l'app release).

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 09:11 UTC | prod | v3.3.0 | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39574474376) |
| 2026-10-21 09:10 UTC | dev | — | `3062888` | [run](https://github.com/mairie360/Database/actions/runs/39574431117) |
| 2026-10-21 08:27 UTC | dev | — | `db3c2a2` | [run](https://github.com/mairie360/Database/actions/runs/39568811813) |
| 2026-10-21 03:50 UTC | dev | — | `ef11982` | [run](https://github.com/mairie360/Database/actions/runs/39540422847) |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
