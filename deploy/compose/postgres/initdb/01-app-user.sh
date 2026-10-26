#!/bin/bash
# Executado UMA vez, na criação do volume do PostgreSQL.
#
# A aplicação não usa o superusuário "postgres": ela conecta como
# "coursesphere", dono apenas do próprio banco (sem SUPERUSER, CREATEDB
# ou CREATEROLE). Se a API for comprometida, o atacante não ganha o
# servidor de banco inteiro.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  --set=app_pw="$APP_DB_PASSWORD" <<'EOSQL'
CREATE ROLE coursesphere LOGIN PASSWORD :'app_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE coursesphere_production OWNER coursesphere;
REVOKE ALL ON DATABASE coursesphere_production FROM PUBLIC;
EOSQL
