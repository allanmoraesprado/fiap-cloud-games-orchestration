-- ------------------------------------------------------------------
-- FIAP Cloud Games - PostgreSQL bootstrap
--
-- Runs automatically the FIRST time the Postgres data volume is
-- initialized (files in /docker-entrypoint-initdb.d/ are executed by
-- the official image only when the data directory is empty).
--
-- Creates one logical database per service, both owned by the
-- application user (POSTGRES_USER, default: fcg).
--
-- NOTE: to re-run this after editing it, reset the volume:
--   docker compose down -v && docker compose up -d
-- ------------------------------------------------------------------

CREATE DATABASE fcg_users;
CREATE DATABASE fcg_catalog;
