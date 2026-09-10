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

There is no lint step and no way to run a single test file through `test.sh` — it
always runs `pg_prove` over `tests/*.sql`. To run one file, exec into a running
db container: `psql -U postgres -d core -f /path/to/tests/NN_x_test.sql` (each test
file is wrapped in `BEGIN; … ROLLBACK;` so it is self-cleaning).

CI (`.github/workflows/cicd.yml`) delegates everything to the shared
`mairie360/CICD` reusable workflow; releases are cut by semantic-release on pushes
to `main` using **conventionalcommits** (`feat!:` / `BREAKING CHANGE` → major).

## Migration architecture

`liquibase/changelog.xml` is the root. It `<include>`s, in order:

1. **`releases/v1.0.0/changelog-v1.0.0.xml`** — versioned, run-once changesets.
   Ordered `NN__init_*.sql` files (`01__init_tables` → `14__init_projects`) that
   build the schema module by module: core tables/audit, sessions, roles,
   resources, permissions, rights, groups, access_control, retention policies,
   then the feature modules (calendar, messaging, e-learning, projects).
   All use `splitStatements="false"` because the files contain `DO $$ … $$` blocks
   and function bodies.

2. **`releases/v1.1.0/changelog-v1.1.0.xml`** — the second shipped release
   (FK indexes + missing primary keys). Changeset ids follow `rel-1.1.0-NN`,
   `author="dev"`. New releases go in their own `releases/vX.Y.Z/` folder the
   same way.

3. **`releases/v1.2.0/changelog-v1.2.0.xml`** — front-coverage additions
   (profile bio, user prefs/notif settings, calendar & e-learning metadata,
   `task_assignees` multi-assign, `conversations.kind` + message mentions/business
   links, extended enums). Additive only; `tasks.assigned_to` /
   `calendar_event_metadata` retirements are deferred to a later release, and the
   `files` / e-mail modules are out of scope for now. New constraints on
   pre-existing tables are added `NOT VALID` (enforced going forward, no deploy
   failure on legacy data — `VALIDATE CONSTRAINT` is a later ops step).

4. **`repeatable/changelog-repeatable.xml`** — every changeset here is
   `runOnChange="true"`, so editing the referenced `.sql` re-applies it. This is
   where all views (`v_*`), functions (`fn_*`), triggers, and the admin seed live,
   grouped by domain folder: `access/`, `auth/`, `calendar/`, `common/`,
   `elearning/`, `groups/`, `messages/`, `project/`, `ressources/`, `roles/`,
   `security/`, `sessions/`, `users/`. Order within the file matters: views first,
   then shared helpers, then per-domain functions, then triggers. Adding a `.sql`
   file here does nothing until you also add a `runOnChange="true"` changeset for
   it in `changelog-repeatable.xml`.

### Rules for changing the schema

- **Never edit a file under `releases/`** once it has shipped — Liquibase tracks
  checksums and will fail. Add a new `releases/vX.Y.Z/` folder with its own
  `changelog-vX.Y.Z.xml` and `<include>` it from `changelog.xml` (before the
  repeatable include).
- **A new `releases/vX.Y.Z/` folder must also be added to `LIQUIBASE_SEARCH_PATH`**
  in both `docker-compose.yml` and `docker-compose-test.yml` — the changesets use
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
  it returns an int status and dynamically queries `public.<resource_name>` by id.
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
  user is row `id = 1`, seeded by `repeatable/common/create_admin.sql`.
- **Sessions** have server-computed expiration and archive/logout triggers
  (`repeatable/sessions/*`, `auth/fn_logout_on_archive.sql`).

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
  (Liquibase 5.0).
- `liquibase/liquibase.properties` and `.env` are stale (old db name
  `mairie_360_database`, host `postgres`); the compose files inject
  `LIQUIBASE_COMMAND_*` env vars and use db `core` instead.
- `DATABASE.md` is an early design sketch and does **not** match the shipped
  schema (e.g. it shows a `modules` table and a bcrypt `CHAR(60)` password;
  `01__init_tables.sql` is authoritative). Treat the `releases/` SQL as the source
  of truth.
