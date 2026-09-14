FROM postgres:18.3-bookworm

# On installe pgTAP (assertions) sur le serveur de base de données, et on compile
# plpgsql_check (profiler de coverage) depuis les sources : le paquet précompilé
# postgresql-18-plpgsql-check de l'apt PGDG n'est pas ABI-compatible avec cette
# image officielle postgres:18.3 (undefined symbol: palloc_mul au démarrage),
# donc on le construit contre les headers exacts de ce postgres.
RUN apt-get update && apt-get install -y \
    postgresql-18-pgtap \
    postgresql-server-dev-18 \
    build-essential \
    curl \
    ca-certificates \
    && curl -L https://github.com/okbob/plpgsql_check/archive/refs/tags/v2.10.9.tar.gz -o /tmp/plpgsql_check.tar.gz \
    && tar -xzf /tmp/plpgsql_check.tar.gz -C /tmp \
    && make -C /tmp/plpgsql_check-2.10.9 USE_PGXS=1 install \
    && rm -rf /tmp/plpgsql_check* \
    && apt-get purge -y --auto-remove build-essential postgresql-server-dev-18 curl \
    && rm -rf /var/lib/apt/lists/*