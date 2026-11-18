-- =====================================================================
-- USUARIOS.sql : usuario de trabajo y roles (se ejecuta una sola vez, antes de DDL.sql). Ejecutar como SYSTEM (o SYS como SYSDBA).
--   sqlplus system/<clave>@localhost:1521/freepdb1 @USUARIOS.sql
-- El usuario se crea dentro de la base FREEPDB1 (Oracle 23ai/26ai Free). Si la conexión entra a la base
-- principal (CDB), la primera línea cambia a FREEPDB1; si ya está en FREEPDB1, no cambia nada.
-- En Oracle 18c XE la base se llama XEPDB1: cambie el nombre en la línea siguiente.
-- =====================================================================
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Usuario de trabajo (dueño del esquema)
CREATE USER itecci IDENTIFIED BY "Itecci2026#"
    DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON users;

GRANT CONNECT, RESOURCE TO itecci;
GRANT CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE SYNONYM TO itecci;

-- Roles de la aplicación (Coordinador General y Secretaria) y usuarios de ejemplo
CREATE ROLE rol_coordinador;
CREATE ROLE rol_secretaria;
GRANT CREATE SESSION TO rol_coordinador;
GRANT CREATE SESSION TO rol_secretaria;

CREATE USER itecci_coord IDENTIFIED BY "Coord2026#" DEFAULT TABLESPACE users QUOTA 0 ON users;
CREATE USER itecci_secre IDENTIFIED BY "Secre2026#" DEFAULT TABLESPACE users QUOTA 0 ON users;
GRANT rol_coordinador TO itecci_coord;
GRANT rol_secretaria  TO itecci_secre;

-- Verificación
SELECT username, account_status, default_tablespace FROM dba_users WHERE username LIKE 'ITECCI%';
