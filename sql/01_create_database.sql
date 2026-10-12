CREATE DATABASE commerceiq;

\connect commerceiq

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;

SHOW server_encoding;