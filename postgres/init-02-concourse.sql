-- Concourse CI database (same Postgres instance as Gitea)
CREATE USER concourse WITH PASSWORD 'concourse';
CREATE DATABASE concourse OWNER concourse;
