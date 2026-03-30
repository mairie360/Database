FROM postgres:16-bookworm

# Installation des outils de test
RUN apt-get update && apt-get install -y \
    postgresql-16-pgtap \
    perl \
    libtap-parser-sourcehandler-pgtap-perl \
    openjdk-17-jre-headless \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Installation de Liquibase
RUN curl -L https://github.com/liquibase/liquibase/releases/download/v4.25.1/liquibase-4.25.1.tar.gz | tar -xz -C /usr/local/bin

# Téléchargement du driver JDBC (pour que Liquibase puisse parler à la DB)
RUN curl -L https://jdbc.postgresql.org/download/postgresql-42.7.2.jar -o /usr/local/bin/internal/lib/postgresql.jar

WORKDIR /workspace
COPY liquibase/ ./liquibase/
COPY tests/ ./tests/