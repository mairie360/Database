FROM liquibase/liquibase:5.0

USER root

# Installation du driver JDBC + Outils PostgreSQL pour les tests
RUN apt-get update && apt-get install -y \
    wget \
    postgresql-client \
    perl \
    libtap-parser-sourcehandler-pgtap-perl \
    && wget https://jdbc.postgresql.org/download/postgresql-42.7.2.jar -P /liquibase/lib/ \
    && rm -rf /var/lib/apt/lists/*

# On utilise un dossier différent pour éviter les conflits de nom
WORKDIR /migrations

# On copie explicitement le contenu
COPY liquibase/ . 

RUN chown -R liquibase:liquibase /migrations

USER liquibase