FROM postgres:17.4-bookworm

RUN apk update && apk upgrade --no-cache

COPY init.sql /docker-entrypoint-initdb.d/
