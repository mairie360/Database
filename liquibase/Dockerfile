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

WORKDIR /workspace

COPY . .

RUN chown -R liquibase:liquibase /workspace

USER liquibase