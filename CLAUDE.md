# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The PostgreSQL database for the Mairie360 platform, managed entirely as Liquibase
migrations. There is no application code — the deliverable is a schema plus a large
set of PL/pgSQL functions, triggers, and views that push business logic (RBAC/ACL
access control, auditing, soft-deletes, session lifecycle) into the database. It is
consumed by other Mairie360 services (a Rust backend is referenced in comments).

Comments and identifiers in the SQL are mostly in French; keep that convention when
editing existing files.

## Commands

```bash
# Run the full test suite (pgTAP via pg_prove). Builds images, exits non-zero on failure.
./test.sh

# Bring up a local dev database with all migrations applied (db on host port 5433)
docker compose up --build

# Tear down local dev db and its volume
docker compose down -v

# Iterate on migrations without rebuilding the db image
docker compose up -d database
docker compose run --rm liquibase --changelog-file=changelog.xml update
```

`./test.sh` also produces a line-coverage report of the PL/pgSQL functions exercised
by the test suite, at `coverage/coverage.lcov` (gitignored). The `database` service
runs with `plpgsql_check` preloaded and `plpgsql_check.profiler=on`
(`docker-compose-test.yml`); after `pg_prove`, `tests/coverage/generate_lcov.py`
queries `plpgsql_profiler_function_tb()` for every plpgsql function in `public`,
maps its body-relative line numbers back to the defining file under
`liquibase/repeatable/` (by locating `CREATE [OR REPLACE] FUNCTION` and the
following `AS $$`), and writes an LCOV file. CI uploads it to Codecov as a separate
`Database-coverage` job in `.github/workflows/cicd.yml` (needs a `CODECOV_TOKEN`
repo secret). `codecov.yml` makes both Codecov statuses `informational`: coverage
is reported but no minimum is enforced. `plpgsql_check` is built from source in `tests/db.Dockerfile` — the
precompiled `postgresql-18-plpgsql-check` apt package is not ABI-compatible with
the official `postgres:18.3-bookworm` image (`undefined symbol: palloc_mul`).

After the unit tests, `test.sh` runs the **upgrade test** (MAIR-413,
`docker-compose-upgrade.yml`, compose project `database-upgrade`): it extracts
the `liquibase/` tree of the release deployed in prod (`UPGRADE_BASELINE`,
default `v1.3.0`, fetched with `git fetch --depth 1` when the tag is missing)
into `.upgrade-baseline/`, migrates an empty database with it, loads
`tests/upgrade/seed.sql`, checks that HEAD refuses to migrate without admin
credentials, applies HEAD twice with credentials (runAlways replay), rolls back
to the previous release tag (so the newest release's `<rollback>`s run) and updates
again, then `pg_prove`s
`tests/upgrade/*_test.sql`. Bump `UPGRADE_BASELINE` together with the prod
`liquibase.image.tag` in Deploiment. The rollback goes back to the git tag
before the newest one, so the whole newest `releases/vX.Y.Z/` folder is undone.

`tests/30_schema_lint_test.sql` (MAIR-476) is a static lint of the migrated
schema: duplicate indexes, non-unique indexes made redundant by a wider one,
unindexed or mistyped foreign keys, tables without primary key, `SECURITY
DEFINER` functions without `search_path`, duplicate triggers. Its `lint_known_*`
temp tables (tolerated findings) are empty since MAIR-477 (`releases/v3.0.0`):
any finding fails the suite. An index only makes another redundant when both use the
same access method (a trigram GIN on `last_name` is not covered by a B-tree starting
with it). `bench/lint.sql` prints the
same rules plus informational ones (`timestamp` without time zone, `int4`
surrogate keys).

**Load test** (`./performance_test.sh` → `bench/run.sh`, MAIR-476): for each data
scale (1, then 2), migrates an empty database (`bench/docker-compose-bench.yml`,
project `database-bench`, `pg_stat_statements` + `auto_explain`), loads
`bench/seed.sql` (scale 1 ≈ 20k users, 2M messages, 2M access_logs, 200k events)
and runs each `bench/scripts/*.sql` with pgbench (`-D scale=N`: the scripts pick
ids across the whole scaled range). Those scripts replay the SQL the APIs send on
their hot paths (copied from the `APIs/*/src/database/` views, plus the
`is_user_active` check API_lib makes on every request): when an API query
changes, update its script. Each script is checked against
`bench/thresholds.conf`, mostly on criteria that do not depend on the machine:
- **blocks**: shared/local/temp blocks touched per transaction at scale 1
  (top-level statements of `pg_stat_statements`). It depends on the plans and the
  data only, so the threshold is strict (about 1.5x the measured value);
- **growth**: blocks per transaction at scale 2 / scale 1, at most 1.3. A query
  that reads about 2x more blocks when the data doubles scans instead of using an
  index and will not hold as the data grows;
- **ms**: average latency at scale 1, a loose safety net (CPU-bound or lock-bound
  regressions) since it depends on the machine.
A script without a threshold fails. Results go to `bench/results/` (gitignored,
`summary.txt` holds the table). The whole run takes about 9 minutes;
`bench/run.sh --quick` runs scale 1 only (no growth check) to iterate locally.
CICD runs `./performance_test.sh` in `database_cicd.yml` (job `performance_tests`,
on PRs too); `release-staging` needs it, so a breach blocks the promotion to
staging but not dev.

There is no way to run a single test file through `test.sh` — it
always runs `pg_prove` over `tests/*.sql`. To run one file, exec into a running
db container: `psql -U postgres -d core -f /path/to/tests/NN_x_test.sql` (each test
file is wrapped in `BEGIN; … ROLLBACK;` so it is self-cleaning).

CI (`.github/workflows/cicd.yml`) delegates everything to the shared
`mairie360/CICD` reusable workflow; releases are cut by semantic-release on pushes
to `main` using **conventionalcommits** (`feat!:` / `BREAKING CHANGE` → major).

## Migration architecture

`liquibase/changelog.xml` is the root. It `<include>`s one folder per git tag
(semantic-release version) that shipped changesets, then the repeatable changelog:

- `releases/v1.3.0/` — the release deployed in prod; former schema versions
  v1.0.0–v1.2.0 (`01`–`23`);
- `releases/v2.0.0/` — former v1.3.0–v1.8.0 (`01`–`11`);
- `releases/v3.0.0/` — former v1.9.0–v1.12.0 (`01`–`06`);
- `releases/v3.1.0/` — first folder with the MAIR-491 identity (`mair-<n>-NN`,
  `logicalFilePath="releases"`).

Until MAIR-490 the folders were named after a schema version unrelated to the git
tags. The regrouped changesets keep their id (`rel-1.X.0-NN`) and their former
changelog path as `logicalFilePath`, the identity Liquibase stored in
`databasechangelog` on every instance: never change either, or Liquibase runs them
again. Each folder ends with a `tag-vX.Y.Z` changeset that tags the database with
the git tag; `v1.3.0` and `v2.0.0` were added afterwards, so they carry a
precondition (`onFail="CONTINUE"`, since `MARK_RAN` still writes the tag) that skips
them on a database already past the next tag. Such databases (dev, staging) also
keep the former tags `v1.7.0`–`v1.12.0`.

What each former schema version did, in order:

1. **`rel-1.0.0-*`** (`releases/v1.3.0/01`–`14`) — versioned, run-once changesets.
   Ordered `NN__init_*.sql` files (`01__init_tables` → `14__init_projects`) that
   build the schema module by module: core tables/audit, sessions, roles,
   resources, permissions, rights, groups, access_control, retention policies,
   then the feature modules (calendar, messaging, e-learning, projects).
   All use `splitStatements="false"` because the files contain `DO $$ … $$` blocks
   and function bodies.

2. **`rel-1.1.0-*`** (`releases/v1.3.0/15`–`16`) — the second shipped release
   (FK indexes + missing primary keys).

3. **`rel-1.2.0-*`** (`releases/v1.3.0/17`–`23`) — front-coverage additions
   (profile bio, user prefs/notif settings, calendar & e-learning metadata,
   `task_assignees` multi-assign, `conversations.kind` + message mentions/business
   links, extended enums). Additive only; `tasks.assigned_to` /
   `calendar_event_metadata` retirements are deferred to a later release, and the
   `files` / e-mail modules are out of scope for now. New constraints on
   pre-existing tables are added `NOT VALID` (enforced going forward, no deploy
   failure on legacy data — `VALIDATE CONSTRAINT` is a later ops step).

4. **`rel-1.3.0-*`** (`releases/v2.0.0/01`) — `chk_users_password_hashed`
   (`NOT VALID`, MAIR-169): `users.password` must hold an argon2id PHC hash
   from now on. Existing plaintext rows are grandfathered by the constraint
   and migrated in place by `repeatable/users/migrate_legacy_password.sql`
   (called from the API login path, or a one-off admin script for accounts
   that never reconnect); hashing itself happens outside Postgres (pgcrypto
   has no argon2id), so this repo only stores and validates the hash shape.

5. **`rel-1.4.0-*`** (`releases/v2.0.0/02`–`03`) — SSO identities (MAIR-141):
   `user_identities` (`user_id`, `provider`, `subject`; unique per
   `(provider, subject)` and per `(user_id, provider)`) and `users.password`
   made nullable for SSO-only accounts (`chk_users_password_hashed` still
   applies to non-NULL values). The behaviour lives in `repeatable/auth/`:
   `link_user_identity()` (idempotent write path of the Keycloak migration
   job), `resolve_user_identity()` (SSO login, NULL for archived users) and
   `v_users_sso_export` (users + role names + provider links the job reads).
   The migration job itself (Keycloak side) is not in this repo.

6. **`rel-1.5.0-*`** (`releases/v2.0.0/04`–`05`) — explicit read acknowledgement (MAIR-269):
   `conversation_read_cursors` (`user_id`, `conversation_id`, `last_read_message_id`; kept apart
   from `unread_counters` because those rows are deleted when they reach zero, which would forget
   the cursor), `idx_messages_conversation_id_id` for the recount, and `messages.id` loses its
   column default. The behaviour lives in `repeatable/messages/`: `fn_acknowledge_read()` moves the
   cursor forward only (`GREATEST`), recounts the messages after it written by someone else
   (recipients only: group members of a group conversation, non-excluded members of a direct one)
   and rewrites `unread_counters`; it answers NULL when the message is not in the conversation.
   `fn_before_message_insert()` (`BEFORE INSERT` on `messages`) takes
   `pg_advisory_xact_lock(360, conversation_id)` — the same lock as the acknowledgement, held until
   commit — and only then draws the id (`nextval` when none is given, explicit ids are kept), so
   within a conversation a message committed later always has a higher id and one cursor is enough.
   No backfill: existing counters are left as is and corrected by the first acknowledgement.
   Deploy it before (or with) the Message_API release that calls `fn_acknowledge_read`.

7. **`rel-1.6.0-*`** (`releases/v2.0.0/06`) — validates the constraints left `NOT VALID` by
   v1.2.0/v1.3.0 (MAIR-236). Legacy rows are repaired first with the least destructive fix (dangling
   reference or out-of-range value reset to NULL/default, a file-based attachment without URL is
   re-typed `other`; nothing is deleted), then `VALIDATE CONSTRAINT` runs. `chk_users_password_hashed`
   is validated only when no plaintext password remains, otherwise it stays `NOT VALID` with a
   NOTICE. The retention side lives in `repeatable/retention/`: `fn_ensure_access_logs_partitions()`
   (monthly `access_logs_yYYYYmMM` partitions, moves rows out of the DEFAULT partition, also run at
   deploy) and `fn_apply_retention_policies()` (deletes expired `sessions`, drops expired
   `access_logs` partitions; `COLD_STORAGE` policies are skipped, no target exists yet). Neither is
   executable by PUBLIC/API roles; the platform must schedule the latter (CronJob in Deploiment,
   not part of this repo).

8. **`rel-1.7.0-*`** (`releases/v2.0.0/07`) — `uq_users_email_lower`, unique index on
   `lower(email)` (MAIR-413); the migration stops and lists the accounts when two e-mails
   differ only by case. First changeset with a `<rollback>`: every changeset since has one.
   Older ones have no rollback, going back past it means restoring a dump.

9. **`rel-1.8.0-*`** (`releases/v2.0.0/08`–`11`) — schema side of the 2 October 2026 audit of the
   APIs, one changeset per file, each with a `<rollback>` (`NN__x.rollback.sql`). Deploy it
   before (or with) the API releases that use these columns.
   - `08__event_approval` (MAIR-392): the approval of an event lives on `events` (`approval_status`
     `event_validation_status`, `approval_decided_by` → `users` `ON DELETE SET NULL`,
     `approval_decided_at`; `chk_events_approval_decision`: a pending event carries no decision),
     backfilled from the member statuses (`refused` > `pending` > `validated`).
     `event_members.validation_status` is kept but no longer read by Calendar_API.
     `v_securable_events` (`events.*`) is recreated so it carries the new columns.
   - `09__task_description_comments_history` (MAIR-393): `tasks.description` (`TEXT NOT NULL
     DEFAULT ''`, ≤ 5000 chars) and `tasks.updated_by` (author of the last write, set by Project_API
     on every INSERT/UPDATE; NULL = system write, e.g. `fn_archive_user()`). `task_comments`
     (`task_id`, `author_id`, `message` 1–2000 chars, `created_at`) replaces
     `tasks.custom_fields->'comments'`. `task_history` gains `action` (`task_created` /
     `task_updated` / `status_changed`), `changes` (`{"<field>": {"from", "to"}}`) and `label` (free
     text of migrated legacy entries only), and is written exclusively by
     `repeatable/project/fn_log_task_change.sql` (`SECURITY DEFINER`, `AFTER INSERT OR UPDATE ON
     tasks`, signs with `NEW.updated_by`); project_api only has `SELECT` on it. The legacy
     `custom_fields` `comments` / `history` arrays are moved into the tables and stripped from the
     JSONB (the rollback puts them back).
   - `10__conversation_creator_and_replies` (MAIR-394): `conversations.created_by` (creator,
     `ON DELETE SET NULL`, backfilled with the earliest member): only the creator or an
     administrator may add members or remove someone else. `messages.reply_to_id` (the API's
     `citation`) with a composite foreign key `(conversation_id, reply_to_id) → messages
     (conversation_id, id)` `ON DELETE SET NULL (reply_to_id)`, so a reply always quotes a message
     of the same conversation (`uq_messages_conversation_id_id` backs it).
   - `11__messaging_moderation_log` (MAIR-394): no foreign key, snapshot of the deleted content;
     one row per message of someone else or conversation deleted by an administrator,
     INSERT-only for `message_api`.

10. **`rel-1.9.0-*`** (`releases/v3.0.0/01`–`02`) — one direct conversation per pair of agents
   (MAIR-478), with its `<rollback>`. `conversations.direct_user_low` /
   `direct_user_high` (→ `users` `ON DELETE CASCADE`) hold the two participants of a `direct`
   conversation, lowest id first; `chk_conversations_direct_pair` requires them (and no group) for
   `direct` and forbids them otherwise, `uq_conversations_direct_pair` allows one direct
   conversation per pair. Message_API had written `kind = 'direct'` for every conversation without
   a group: the backfill keeps `direct` only for the conversations without a group titled
   `Direct <id>` (the BFF's) or untitled whose members, title id, creator and message authors make
   exactly two agents, merges the duplicates of a pair into the oldest one (messages, membership,
   unread counters added up, earliest read cursor), gives a participant who had left a hidden row
   back (`is_excluded = TRUE`, how Message_API now hides a direct conversation) and turns everything
   else into `group`. The rollback drops the columns and restores the v1.2.0 `kind` rule; merges and
   hidden rows stay. `02__conversations_resource` declares the `conversations` resource and its
   permissions, and gives the role rights `12__init_messaging.sql` meant to give (they matched nothing,
   so `check_access()` answered `-1` for any conversation); Message_API asks it who may delete a
   conversation. **Deploy it with the Message_API release of MAIR-478**: older Message_API
   versions insert `direct` conversations without a pair, which the constraint now refuses.

11. **`rel-1.10.0-*`** (`releases/v3.0.0/03`) — phone number as country + national number
   (MAIR-480): `users.phone_country` (ISO 3166-1 alpha-2) and `users.phone_number` (national
   significant number, digits only, no trunk prefix: `0612345678` is stored `FR` / `612345678`),
   both set or both NULL (`chk_users_phone`, written with `COALESCE` because a CHECK passes on
   NULL). Legacy French numbers (`0…`, overseas departments by prefix, `33…`) are backfilled; any
   other legacy value keeps the constraint `NOT VALID` with a NOTICE listing the users.
   `create_user()` takes `p_phone_country` as its last parameter. Legacy writers that still send a
   French national number without its country (the mairie360_api_lib test fixtures, an older API
   during a deploy) are converted by `repeatable/users/trigger_normalize_legacy_phone.sql` with the
   backfill rules; any other number without a country is refused (`23514`). The release rollback
   drops that trigger, the next update recreates it.

12. **`rel-1.11.0-*`** (`releases/v3.0.0/04`–`05`) — findings of the schema lint and bench of MAIR-476,
   fixed by MAIR-477, rollback per changeset.
   - `04__drop_redundant_indexes`: drops the five indexes the lint reported as duplicates or
     prefixes of a wider index (`idx_sessions_token_lookup`, `idx_messages_conversation_id_id`,
     `idx_task_history_task_id`, `idx_user_roles_user`, `idx_permissions_resource_id`).
   - `05__users_search_trigram`: `pg_trgm` and GIN trigram indexes on `users.first_name`,
     `last_name`, `email`, `first_name || ' ' || last_name` and `last_name || ' ' || first_name`,
     for the `ILIKE '%term%'` searches of Core_API. The APIs must build full names with `||`:
     `concat_ws` is not IMMUTABLE, cannot be indexed, and one unindexed branch of the `OR` brings
     back the sequential scan. Do not add a B-tree on `(last_name, first_name, id)`: the planner
     then walks it for broad searches (22 ms instead of 1.2 ms on 10 000 users).
   - The duplicate trigger `trg_users_updated_at` is dropped by its repeatable file
     (`repeatable/users/trigger_user_update.sql` now only holds the `DROP TRIGGER IF EXISTS`).
   `tests/33_users_search_trigram_test.sql` checks the indexes and that the API search plan uses
   them; the bench holds `core_directory_search` to the strict thresholds (126 blocks per
   transaction, growth 1.20).

13. **`rel-1.12.0-*`** (`releases/v3.0.0/06`) — event dates bounded to
   `[1970-01-01, 3000-01-01)` UTC (MAIR-481), rollback per changeset.
   `06__events_date_window` deletes the events outside that window, or repeating along a rule
   outside it, with their members, message links and group ACL entries, then the rules outside
   it (fuzzing pollution: Postgres prints years outside 0001–9999 in a form Calendar_API cannot
   parse back, so these rows made `GET /events/{id}` and `GET /calendar` answer 500), and adds
   `chk_events_date_window` and `chk_recurrence_date_window` (a rule's `end_date`, the day after
   its last occurrence, may equal `3000-01-01`; `NULL` = never ends). The rollback only drops the
   constraints. Calendar_API applies the same window and answers 400 first.
   `tests/34_events_date_window_test.sql` covers the constraints, the upgrade test the cleanup.

14. **`mair-477-01`** (`releases/v3.1.0/01`) — B-tree `idx_users_name_order` on
   `users (last_name, first_name, id)`, the order of Core_API's admin user list (MAIR-477, found
   by the MAIR-474 load test): without it each page sorted every user (10 143 blocks per
   transaction at a random page in the bench, 249 now). Core_API only orders by it without a
   search; with one it collects the matches first through the trigram indexes, otherwise the
   generic plan of the prepared query walks this index for a selective search (directory search
   126 → 986 blocks). `tests/35_users_name_order_test.sql` checks the index and the page plan;
   `tests/33` drops it in its transaction to read the trigram plans; the bench holds
   `core_admin_users` (OFFSET pages: growth 1.48 by design) and `core_directory_search`.

15. **`mair-477-02`** (`releases/v3.1.0/02`) — one trigram GIN `idx_users_search_text_trgm` on the
   expression `lower(first_name || ' ' || last_name || chr(31) || last_name || ' ' || first_name
   || chr(31) || email)`, replacing the five trigram indexes of `rel-1.11.0-02`. The searches of
   Core_API matched five `ILIKE` joined by OR: a broad term read the whole table, five `ILIKE` per
   row (14 to 74 ms on 10 000 users, the main load of Core_API's Postgres under the MAIR-474 load
   test); one `LIKE` on this expression takes 0.7 to 3.9 ms, generic plans included. `chr(31)`
   keeps a term from matching across fields. An expression index, not a generated column:
   `v_users_active` / `v_users_archived` select `users.*` and would carry a column the rollback
   could not drop. Core_API must write the exact expression; `tests/33` checks the plan.
16. **`mair-502-01`** (`releases/v3.1.0/03`) — `tasks.archived_at`: a completed task is archived.
   The repeatable trigger `tr_before_task_archive` (`project/fn_set_task_archived_at.sql`) sets it
   when a task becomes `completed` (keeping the first date while it stays completed) and clears it
   when it is reopened; the changeset backfills the completed tasks (`updated_at`). Partial indexes
   `idx_tasks_project_active` (`project_id, created_at, id`, the order of Project_API's lists) and
   `idx_tasks_project_archived` (`project_id, archived_at DESC, id DESC`). Project_API shows the
   active tasks in the project detail and the archived ones in their own list; its counters count
   both. This `feat` renamed the unreleased `releases/v3.0.1` into `releases/v3.1.0` (MAIR-491).

Then **`repeatable/changelog-repeatable.xml`** — every changeset here is
   `runOnChange="true"`, so editing the referenced `.sql` re-applies it. This is
   where all views (`v_*`), functions (`fn_*`), triggers, and the admin seed live,
   grouped by domain folder: `access/`, `auth/`, `calendar/`, `common/`,
   `elearning/`, `groups/`, `messages/`, `project/`, `ressources/`, `roles/`,
   `security/`, `sessions/`, `users/`. Order within the file matters: views first,
   then shared helpers, then per-domain functions, then triggers. Adding a `.sql`
   file here does nothing until you also add a `runOnChange="true"` changeset for
   it in `changelog-repeatable.xml`, with an empty `<rollback/>` like the others
   (a rollback only forgets the changeset, the next `update` re-applies the file).

### Rules for changing the schema

- **Never edit a file under `releases/`** once it has shipped — Liquibase tracks
  checksums and will fail. New changesets go in the folder of the git tag that
  will ship them, `releases/vX.Y.Z/` with its `changelog-vX.Y.Z.xml`, created by
  the first change after a tag and `<include>`d from `changelog.xml` (before the
  repeatable include). Name it after the version semantic-release will cut from
  the commits merged since the last tag (`fix` → patch, `feat` → minor, breaking →
  major) and close it with a `tag-vX.Y.Z` changeset. Every changeset carries a
  `<rollback>`. A schema change needs a commit type that releases (`fix:`,
  `feat:`…), not `chore:` / `refactor:`.
- **Identity of new changesets (MAIR-491).** The changelog of a new folder sets
  `logicalFilePath="releases"` on its `<databaseChangeLog>`, and its changesets are
  named after their ticket, `id="mair-<n>-NN"` (`author="dev"`), plus
  `id="tag-vX.Y.Z"` for the closing tag. Their identity then does not depend on the
  folder: when the folder has to be renamed (another `feat` merged before the prod
  release turned `v3.0.1` into `v3.1.0`, as MAIR-502 did), dev and staging do not run them again,
  and only the renamed `tag-vX.Y.Z` runs. The `rel-1.X.0-NN` ids are frozen.
- **Release folder gate (CICD `release_folder`, MAIR-491).** Between staging and the
  Prod approval, CICD computes the version `release-prod` will cut (semantic-release
  dry run) and compares the release changesets with the last tag, by identity and
  content. It fails, and the prod release is skipped, when a shipped changeset was
  modified or removed (one holding only a `tagDatabase` may go), when a new changeset
  is outside `releases/v<next>/` or no release is cut, when that folder does not end
  with `tag-v<next>`, or when a new changeset breaks the identity rule above. The job
  summary says what to fix; fix it with a PR (usually a folder rename). To check a
  branch before merging: `python3 <CICD checkout>/actions/release-folder/check_release_folder.py
  . <last tag> <expected version>`.
- **A new `releases/vX.Y.Z/` folder must also be added to `LIQUIBASE_SEARCH_PATH`**
  in `docker-compose.yml`, `docker-compose-test.yml` and
  `bench/docker-compose-bench.yml` — the changesets use
  `sqlFile path="NN__x.sql"` and Liquibase resolves those against the search path,
  not the changelog dir. Miss this and `update` fails with a file-not-found.
- **Repeatable objects** (views/functions/triggers) *are* meant to be edited in
  place. Write them idempotently: `CREATE OR REPLACE` for functions/views,
  `DROP … IF EXISTS` + recreate for triggers, and `DROP FUNCTION IF EXISTS` first
  when changing a function's signature (see `access/fn_check_access.sql`).
- If a repeatable object depends on a schema change, the schema change must land as
  a new `releases/` changeset in the same PR.

## Key domain concepts

- **Two-tier access control.** Global RBAC (`roles` → `rights` → `permissions` →
  `resources`) plus row-level `access_control` (ACL) entries keyed by
  `resource_instance_id` and granted to either a `user_id` or a `group_id` (XOR
  constraint). `check_access(user_id, resource_name, action, instance_id)` in
  `repeatable/access/fn_check_access.sql` is the single entry point callers use;
  it returns an int status and dynamically queries `public.<resource_name>` by id,
  only for names listed in `resources` (-1 otherwise). It is executable by the API
  roles only, not PUBLIC. Archived users keep their `user_roles` (so `restore_user`
  gives them back) but `is_admin()` and `check_access()` deny them.
- **Soft delete.** `users` is never hard-deleted. `DELETE` goes through the
  `v_users_active` / `v_users_archived` views, which have `INSTEAD OF` triggers
  that set `is_archived = TRUE` and `status = 'archived'`. `restore_user(id)`
  reverses it. Filtered index `idx_users_not_archived` stands in for partitioning.
- **Immutable audit.** `users_audit_log` and `access_logs` are append-only —
  triggers `RAISE EXCEPTION` (SQLSTATE `P0001`) on any `DELETE`/`UPDATE`. Tests
  assert this. `access_logs` is `PARTITION BY RANGE (timestamp)` with a `DEFAULT`
  partition.
- **Protected rows.** Triggers block renaming/deleting critical roles
  (`roles/fn_protect_critical_roles.sql`, `fn_protect_role_names.sql`). The admin
  user is row `id = 1`, seeded by `seed_admin_account()` in
  `repeatable/common/create_admin.sql` from `-Dadmin_email` / `-Dadmin_password`
  (argon2id hash). The public template account (`admin@example.invalid`) is only
  seeded with `-Dallow_template_admin=true` (both compose files here; e2e and the
  API/BFF test stacks must pass it too). Without credentials nor that flag the
  migration fails while `id = 1` is missing or still the template account.
- **Sessions** have server-computed expiration and archive/logout triggers
  (`repeatable/sessions/*`, `auth/fn_logout_on_archive.sql`).
- **Per-API Postgres roles (MAIR-114).** `core_api`, `project_api`,
  `calendar_api`, `message_api` and `elearning_api` are created by
  `repeatable/security/api_roles.sql`, and their privileges are set by
  `repeatable/security/api_grants.sql`. Both files are `runAlways` and are the
  last changesets. Passwords come from `-D<role>_password` changelog parameters
  (Deploiment's Liquibase job, and both compose files locally). Without them, a
  new role is created `NOLOGIN` and an existing role keeps its password.
  `api_grants.sql` revokes everything, then grants again: a **new table or view
  is unreachable by every API until you add it there**. `20_api_roles_test.sql`
  pins each role's writable tables. Functions and triggers run with the calling
  API's rights, so a trigger that writes logs/audit or touches another domain's
  tables must be `SECURITY DEFINER SET search_path = public, pg_temp` (see
  `fn_archive_user`, `check_access`, and the session log triggers).

## Tests

`tests/NN_*.sql` are pgTAP scripts (`SELECT plan(N); … SELECT * FROM finish();`)
wrapped in `BEGIN/ROLLBACK`. `docker-compose-test.yml` runs migrations, installs
the `pgtap` extension, then `pg_prove`s the whole directory (glob `tests/*.sql`, so
the `_test` suffix is not load-bearing — `15_performance_indexes.sql` and
`16_default_bigint.sql` are schema-invariant checks that don't follow it). When you
add a function/trigger/view, add or extend the matching numbered test file and keep
the `plan(N)` count in sync.

## Known inconsistencies (don't "fix" incidentally)

- The repeatable folder is spelled `ressources/` (French) but the table and the
  resource name it serves are `resources` (English). Match the existing spelling
  of whichever you're referencing.
- `tmp/archives_tests.sql` is scratch, not wired into `pg_prove` or Liquibase.
- Test filenames are noisy: some carry a `_test` suffix and some don't, and
  `13_projec_test.sql` is misspelled. `16_default_bigint.sql` actually asserts
  every table has a primary key, not anything about bigint defaults.
- Postgres/Liquibase versions differ on purpose-or-neglect across images:
  `Dockerfile` (pg 18.6, Renovate-managed), `tests/db.Dockerfile` (pg 18.3),
  `tests/test.Dockerfile` (pg 16 + Liquibase 4.25.1), `liquibase/Dockerfile`
  (Liquibase 5.0.4 pinned by digest, JDBC driver checked by sha256, no test
  tooling).
- `liquibase/liquibase.properties` and `.env` are stale (old db name
  `mairie_360_database`, host `postgres`); the compose files inject
  `LIQUIBASE_COMMAND_*` env vars and use db `core` instead.
- `DATABASE.md` is an early design sketch and does **not** match the shipped
  schema (e.g. it shows a `modules` table and a bcrypt `CHAR(60)` password;
  `01__init_tables.sql` is authoritative). Treat the `releases/` SQL as the source
  of truth.

## Pull request reviewers

Every PR requests a review from the whole team, minus its author: `CarolinHugo`, `LAURETbenjamin`, `MathTek` and `Quentintnrl` (`gh pr create … --reviewer CarolinHugo,LAURETbenjamin,MathTek`). `.github/CODEOWNERS` makes GitHub request them automatically as well.
