-- Name of the passkey manager that holds a passkey (MAIR-810): Core reads the AAGUID of the authenticator
-- when the passkey is registered and keeps the name of the matching manager (iCloud Keychain, Google
-- Password Manager, Bitwarden, ...). The front offers it as the name of the passkey. NULL when the
-- authenticator is unknown or gave no AAGUID, and for the passkeys registered before this column.
ALTER TABLE user_passkeys
    ADD COLUMN provider VARCHAR(100) CHECK (provider IS NULL OR btrim(provider) <> '');
