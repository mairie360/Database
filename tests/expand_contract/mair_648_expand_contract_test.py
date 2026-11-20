"""Non-regression tests of the expand/contract check of the migrations.

A migration must not break the APIs of the previous release, so that a release can be rolled
back without restoring the database. Run: python3 -m unittest discover -s tests/expand_contract -p '*_test.py'
"""

import unittest

from check_expand_contract import find_violations

BASELINE = "v3.4.0"
RELEASED = {"v3.3.0", "v3.4.0"}
BASE_TREE = {
    "liquibase/releases/v3.4.0/01__tasks.sql": (
        "CREATE TABLE tasks (id BIGINT PRIMARY KEY, title TEXT, assigned_to INT);\n"
        "CREATE TABLE legacy_notes (id BIGINT PRIMARY KEY);\n"
    ),
    "liquibase/repeatable/users/create_user.sql": (
        "DROP FUNCTION IF EXISTS create_user(VARCHAR, INT);\n"
        "CREATE OR REPLACE FUNCTION create_user(p_email VARCHAR, p_role INT) RETURNS INT\n"
        "AS $$ SELECT 1 $$ LANGUAGE sql;\n"
    ),
}


def check(new_files: dict[str, str], baseline: dict[str, str] | None = None) -> list[str]:
    current = dict(BASE_TREE)
    current.update(new_files)
    return find_violations(current, BASE_TREE if baseline is None else baseline, BASELINE,
                           RELEASED)


def new_release(sql: str) -> dict[str, str]:
    return {"liquibase/releases/v3.5.0/01__change.sql": sql}


class ExpandOnlyChangesPass(unittest.TestCase):
    def test_unchanged_tree_passes(self):
        self.assertEqual(check({}), [])

    def test_additive_changes_pass(self):
        self.assertEqual(check(new_release(
            "CREATE TABLE task_labels (id BIGINT PRIMARY KEY);\n"
            "ALTER TABLE tasks ADD COLUMN description TEXT;\n"
            "ALTER TABLE tasks ADD COLUMN priority INT NOT NULL DEFAULT 0;\n"
            "CREATE INDEX idx_tasks_title ON tasks (title);\n")), [])

    def test_destructive_statement_already_released_passes(self):
        baseline = dict(BASE_TREE)
        baseline["liquibase/releases/v3.3.1/02__x.sql"] = "ALTER TABLE tasks DROP COLUMN old;\n"
        # The folder was renamed after the release: same statement, other path.
        self.assertEqual(check({"liquibase/releases/v3.4.0/02__x.sql":
                                "ALTER TABLE tasks DROP COLUMN old;\n"}, baseline), [])

    def test_rollback_files_are_ignored(self):
        self.assertEqual(check({"liquibase/releases/v3.5.0/01__change.rollback.sql":
                                "ALTER TABLE tasks DROP COLUMN description;\n"}), [])

    def test_commented_out_statement_is_ignored(self):
        self.assertEqual(check(new_release(
            "-- ALTER TABLE tasks DROP COLUMN assigned_to;\n"
            "/* ALTER TABLE tasks RENAME COLUMN title TO name; */\n")), [])


class DestructiveChangesFail(unittest.TestCase):
    def assertFlags(self, sql: str, kind: str):
        errors = check(new_release(sql))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f": {kind}: ", errors[0])

    def test_drop_column_fails(self):
        self.assertFlags("ALTER TABLE tasks DROP COLUMN assigned_to;\n", "drop column")

    def test_drop_released_table_fails(self):
        self.assertFlags("DROP TABLE IF EXISTS legacy_notes;\n", "drop")

    def test_rename_fails(self):
        self.assertFlags("ALTER TABLE tasks RENAME COLUMN title TO name;\n", "rename")

    def test_type_change_fails(self):
        self.assertFlags("ALTER TABLE tasks ALTER COLUMN assigned_to TYPE BIGINT;\n",
                         "type change")

    def test_set_not_null_fails(self):
        self.assertFlags("ALTER TABLE tasks ALTER COLUMN title SET NOT NULL;\n", "set not null")

    def test_not_null_column_without_default_fails(self):
        self.assertFlags("ALTER TABLE tasks ADD COLUMN owner_id INT NOT NULL;\n",
                         "not null column without default")

    def test_statement_in_dynamic_sql_fails(self):
        self.assertFlags("DO $$ BEGIN EXECUTE 'ALTER TABLE tasks DROP COLUMN assigned_to'; "
                         "END $$;\n", "drop column")

    def test_function_signature_change_fails(self):
        # Same drop line as the baseline, but the recreated function lost an argument: the
        # released 2-argument version is gone.
        errors = check({"liquibase/repeatable/users/create_user.sql": (
            "DROP FUNCTION IF EXISTS create_user(VARCHAR, INT);\n"
            "CREATE OR REPLACE FUNCTION create_user(p_email VARCHAR) RETURNS INT\n"
            "AS $$ SELECT 1 $$ LANGUAGE sql;\n")})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("CREATE_USER(VARCHAR, INT)", errors[0])

    def test_drop_of_released_function_fails(self):
        self.assertFlags("DROP FUNCTION create_user(VARCHAR, INT);\n", "drop")


class FunctionRecreation(unittest.TestCase):
    def test_drop_and_recreate_with_same_signature_passes(self):
        self.assertEqual(check(new_release(
            "DROP FUNCTION IF EXISTS create_user(VARCHAR, INTEGER);\n"
            "CREATE FUNCTION create_user(p_email CHARACTER VARYING(255), p_role INT DEFAULT 1)\n"
            "RETURNS INT AS $$ SELECT 2 $$ LANGUAGE sql;\n")), [])

    def test_drop_and_recreate_with_other_signature_fails(self):
        errors = check(new_release(
            "DROP FUNCTION IF EXISTS create_user(VARCHAR, INT);\n"
            "CREATE FUNCTION create_user(p_email VARCHAR) RETURNS INT\n"
            "AS $$ SELECT 2 $$ LANGUAGE sql;\n"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("CREATE_USER(VARCHAR, INT)", errors[0])

    def test_dynamic_drop_of_a_format_template_passes(self):
        self.assertEqual(check(new_release(
            "CREATE FUNCTION fn_purge() RETURNS void AS $$ BEGIN\n"
            "  EXECUTE format('DROP TABLE public.%I', 'access_logs_y2020m01');\n"
            "END $$ LANGUAGE plpgsql;\n")), [])

    def test_drop_of_never_released_object_passes(self):
        self.assertEqual(check(new_release(
            "DROP FUNCTION IF EXISTS fn_draft(INT);\nDROP TABLE IF EXISTS draft_table;\n")), [])


class Markers(unittest.TestCase):
    def test_contract_marker_on_released_expand_passes(self):
        self.assertEqual(check(new_release(
            "-- The APIs stopped reading it in v3.3.0.\n"
            "-- contract: v3.3.0\n"
            "ALTER TABLE tasks DROP COLUMN assigned_to;\n")), [])

    def test_contract_marker_on_the_same_line_passes(self):
        self.assertEqual(check(new_release(
            "ALTER TABLE tasks DROP COLUMN assigned_to; -- contract: v3.4.0\n")), [])

    def test_contract_marker_on_unknown_tag_fails(self):
        errors = check(new_release("-- contract: v9.9.9\nALTER TABLE tasks DROP COLUMN assigned_to;\n"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("is not a released tag", errors[0])

    def test_contract_marker_newer_than_prod_fails(self):
        errors = find_violations(
            {**BASE_TREE, **new_release("-- contract: v3.4.0\nALTER TABLE tasks DROP COLUMN assigned_to;\n")},
            BASE_TREE, "v3.3.0", RELEASED)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("newer than the release in prod", errors[0])

    def test_marker_separated_by_code_is_ignored(self):
        errors = check(new_release(
            "-- contract: v3.3.0\nCREATE TABLE x (id INT);\nALTER TABLE tasks DROP COLUMN assigned_to;\n"))
        self.assertEqual(len(errors), 1, errors)

    def test_expand_safe_marker_with_reason_passes(self):
        self.assertEqual(check(new_release(
            "-- expand-safe: a trigger fills it for the writers that omit it\n"
            "ALTER TABLE tasks ALTER COLUMN title SET NOT NULL;\n")), [])

    def test_expand_safe_marker_without_reason_fails(self):
        errors = check(new_release(
            "-- expand-safe:\nALTER TABLE tasks ALTER COLUMN title SET NOT NULL;\n"))
        self.assertEqual(len(errors), 1, errors)


class ReviewFindings(unittest.TestCase):
    """Cases the first version let through (review of the expand/contract check)."""

    def test_mair_648_not_null_after_a_type_with_a_comma_fails(self):
        errors = check(new_release("ALTER TABLE tasks ADD COLUMN amount NUMERIC(10,2) NOT NULL;\n"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(": not null column without default: ", errors[0])

    def test_mair_648_defaulted_column_with_a_comma_type_passes(self):
        self.assertEqual(check(new_release(
            "ALTER TABLE tasks ADD COLUMN amount NUMERIC(10,2) NOT NULL DEFAULT 0, "
            "ADD COLUMN note TEXT;\n")), [])

    def test_mair_648_released_table_dropped_and_recreated_fails(self):
        errors = check(new_release(
            "DROP TABLE legacy_notes;\nCREATE TABLE legacy_notes (id BIGINT PRIMARY KEY);\n"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("DROP TABLE LEGACY_NOTES", errors[0])

    def test_mair_648_released_view_dropped_and_recreated_passes(self):
        baseline = dict(BASE_TREE)
        baseline["liquibase/repeatable/v.sql"] = "CREATE VIEW v_tasks AS SELECT * FROM tasks;\n"
        self.assertEqual(check({"liquibase/repeatable/v.sql":
                                "DROP VIEW IF EXISTS v_tasks;\n"
                                "CREATE VIEW v_tasks AS SELECT id FROM tasks;\n"}, baseline), [])

    def test_mair_648_drop_of_a_released_function_without_arguments_fails(self):
        errors = check(new_release("DROP FUNCTION create_user;\n"))
        self.assertEqual(len(errors), 1, errors)

    def test_mair_648_drop_with_a_nested_parenthesis_type_fails(self):
        baseline = dict(BASE_TREE)
        baseline["liquibase/repeatable/f.sql"] = (
            "CREATE FUNCTION fn_round(p NUMERIC(10,2)) RETURNS INT AS $$ SELECT 1 $$ LANGUAGE sql;\n")
        errors = check({"liquibase/repeatable/f.sql": "DROP FUNCTION fn_round(NUMERIC(10,2));\n"},
                       baseline)
        self.assertEqual(len(errors), 1, errors)

    def test_mair_648_out_arguments_are_not_part_of_the_signature(self):
        baseline = dict(BASE_TREE)
        baseline["liquibase/repeatable/f.sql"] = (
            "CREATE FUNCTION fn_stats(p_id INT, OUT total INT) AS $$ SELECT 1 $$ LANGUAGE sql;\n")
        errors = check({"liquibase/repeatable/f.sql": "DROP FUNCTION fn_stats(INT);\n"}, baseline)
        self.assertEqual(len(errors), 1, errors)

    def test_mair_648_comma_inside_a_default_literal_is_not_an_argument(self):
        baseline = dict(BASE_TREE)
        baseline["liquibase/repeatable/f.sql"] = (
            "CREATE FUNCTION fn_tag(p TEXT DEFAULT 'a,b') RETURNS INT AS $$ SELECT 1 $$ "
            "LANGUAGE sql;\n")
        errors = check({"liquibase/repeatable/f.sql": "DROP FUNCTION fn_tag(TEXT);\n"}, baseline)
        self.assertEqual(len(errors), 1, errors)

    def test_mair_648_released_clause_on_another_table_fails(self):
        # A repeatable file that tightened tasks now tightens users: same clause, new table.
        baseline = dict(BASE_TREE)
        baseline["liquibase/repeatable/x.sql"] = "ALTER TABLE tasks ALTER COLUMN status SET NOT NULL;\n"
        errors = check({"liquibase/repeatable/x.sql":
                        "ALTER TABLE users ALTER COLUMN status SET NOT NULL;\n"}, baseline)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(": set not null: ", errors[0])


if __name__ == "__main__":
    unittest.main()
