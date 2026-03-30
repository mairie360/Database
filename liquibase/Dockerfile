FROM liquibase/liquibase:5.0

# On télécharge le driver JDBC Postgres (indispensable pour la version 5.0+)
# On le place dans /liquibase/lib/ pour qu'il soit chargé automatiquement
USER root
ADD https://jdbc.postgresql.org/download/postgresql-42.7.2.jar /liquibase/lib/postgresql.jar
RUN chmod 644 /liquibase/lib/postgresql.jar

# On s'assure que le répertoire de travail est le bon
WORKDIR /liquibase/changelog

# On copie tes fichiers
COPY changelog.xml .
COPY liquibase.properties .
COPY scripts/ ./scripts/

RUN chown -R liquibase:liquibase /liquibase/changelog
USER liquibase