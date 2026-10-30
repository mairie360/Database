# Production migration image (published as liquibase-migrations): Liquibase,
# the PostgreSQL JDBC driver and the changelogs, nothing else. Test tooling
# (psql, pgTAP, pg_prove) lives in tests/test.Dockerfile.
FROM liquibase/liquibase:5.0.4@sha256:060f96efff4811ccf03957ff3160f21ea04139b89940640f8ad54a065cdc6906

# The Liquibase 5 image ships no database driver. The checksum is the one of
# the Maven Central artifact (its published SHA-1 matches too).
ADD --checksum=sha256:6e0e4cc2d8cae902084f8a2b18728b073a6fd9d1f87c9d8bff8f298c18185b93 \
    --chown=liquibase:liquibase \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.13/postgresql-42.7.13.jar \
    /liquibase/lib/postgresql-42.7.13.jar

# The base image lags behind Ubuntu security updates, and lpm (Liquibase Package
# Manager) is a Go binary only used by the entrypoint's optional INSTALL_MYSQL,
# which the migration job never sets: upgrade OpenSSL and drop lpm so the image
# passes the Trivy gate.
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --only-upgrade --no-install-recommends openssl libssl3t64; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /liquibase/bin/lpm
USER liquibase

WORKDIR /migrations
COPY --chown=liquibase:liquibase liquibase/ .

# MAIR-500: the personal data inventory of this schema version, read by the sealed backups
# (Devops/Deploiment backup.sealing copies it from this image, so the inventory always matches the
# deployed schema). Read-only data, no code.
COPY --chown=liquibase:liquibase gdpr/inventory.yaml /gdpr/inventory.yaml
