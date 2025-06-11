FROM postgres:17.4-bookworm

COPY init.sql /docker-entrypoint-initdb.d/
