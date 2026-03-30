FROM postgres:18.3-bookworm

# On installe pgTAP sur le serveur de base de données
RUN apt-get update && apt-get install -y \
    postgresql-18-pgtap \
    && rm -rf /var/lib/apt/lists/*