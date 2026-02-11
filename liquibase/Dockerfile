FROM liquibase/liquibase:4.24

# On s'assure que le répertoire de travail est le bon
WORKDIR /liquibase/changelog

# On ne copie que ce qui est nécessaire pour les migrations
COPY changelog.xml .
COPY liquibase.properties .
COPY scripts/ ./scripts/

# Liquibase utilise l'UID 1001 par défaut, on s'assure que les fichiers lui appartiennent
# (Optionnel mais recommandé pour éviter les problèmes de droits en K8s)
USER root
RUN chown -R liquibase:liquibase /liquibase/changelog
USER liquibase