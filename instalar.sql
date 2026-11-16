-- =====================================================================
-- instalar.sql : reconstruye TODO el esquema ITECCI en el orden correcto (borra y vuelve a crear).
-- Requisito: el usuario ITECCI y los roles ya existen (01_usuarios.sql, una sola vez como SYSTEM).
--
-- Desde la carpeta del proyecto, con la consola en UTF-8 para conservar tildes y eñes:
--   PowerShell:  $env:NLS_LANG = 'AMERICAN_AMERICA.AL32UTF8'
--   sqlplus itecci/"Itecci2026#"@localhost:1521/freepdb1 @instalar.sql
--
-- No ejecuta 06, 08, 09 ni 10: son consultas, reportes y pruebas de evidencia (no crean objetos).
-- =====================================================================
SET FEEDBACK OFF
PROMPT 1/7  Limpiando objetos anteriores...
@00_limpiar.sql
PROMPT 2/7  Creando tablas, índices y secuencias...
@02_ddl.sql
PROMPT 3/7  Cargando datos de prueba (tarda cerca de un minuto)...
@03_dml.sql
PROMPT 4/7  Vistas y procedimientos...
@04_plsql_vistas.sql
PROMPT 5/7  Permisos por rol...
@05_roles_permisos.sql
PROMPT 6/7  Avance PL/SQL: auditoría, paquetes y triggers...
@07_plsql_objetos.sql
PROMPT 7/7  Paquetes de la aplicación web...
@11_api_paquetes.sql
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER)
SET FEEDBACK ON PAGESIZE 100 LINESIZE 150
PROMPT
PROMPT Objetos del esquema (no debe haber ninguno INVALID):
SELECT object_type, COUNT(*) AS cantidad, SUM(DECODE(status, 'INVALID', 1, 0)) AS invalidos
  FROM user_objects WHERE object_name NOT LIKE 'BIN$%' GROUP BY object_type ORDER BY object_type;
SELECT name, type, line, SUBSTR(text, 1, 100) AS error FROM user_errors WHERE name NOT LIKE 'BIN$%' ORDER BY name, sequence;
EXIT
