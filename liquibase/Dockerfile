# Production migration image (published as liquibase-migrations): Liquibase,
# the PostgreSQL JDBC driver and the changelogs, nothing else. Test tooling
# (psql, pgTAP, pg_prove) lives in tests/test.Dockerfile.
FROM liquibase/liquibase:5.0.4@sha256:060f96efff4811ccf03957ff3160f21ea04139b89940640f8ad54a065cdc6906

# The Liquibase 5 image ships no database driver. The checksum is the one of
# the Maven Central artifact (its published SHA-1 matches too).
ADD --checksum=sha256:0c244ac7d02cf89d8e29852eace6595d75bc4d78581b85b2768460081646a57b \
    --chown=liquibase:liquibase \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.2/postgresql-42.7.2.jar \
    /liquibase/lib/postgresql-42.7.2.jar

WORKDIR /migrations
COPY --chown=liquibase:liquibase liquibase/ .
