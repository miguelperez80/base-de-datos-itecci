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
