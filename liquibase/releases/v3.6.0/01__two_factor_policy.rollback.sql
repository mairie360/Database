DROP TABLE IF EXISTS two_factor_policy_audit_log;
DROP TABLE IF EXISTS two_factor_policy;
DROP FUNCTION IF EXISTS fn_audit_two_factor_policy();
DROP FUNCTION IF EXISTS fn_protect_two_factor_policy();
DROP FUNCTION IF EXISTS fn_protect_two_factor_audit();
