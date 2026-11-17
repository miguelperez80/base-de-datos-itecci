-- =====================================================================
-- instalar.sql : reconstruye TODO el esquema ITECCI con los dos scripts de entrega (borra y vuelve a crear).
-- Requisito: el usuario ITECCI y los roles ya existen (01_usuarios.sql, una sola vez como SYSTEM).
--
-- Desde la carpeta del proyecto, con la consola en UTF-8 para conservar tildes y eñes:
--   PowerShell:  $env:NLS_LANG = 'AMERICAN_AMERICA.AL32UTF8'
--   sqlplus itecci/"Itecci2026#"@localhost:1521/freepdb1 @instalar.sql
--
-- Equivale a ejecutar DDL.sql y luego DATOS.sql (también se pueden correr a mano en SQL Developer, con F5).
-- =====================================================================
PROMPT ===== 1/2  DDL.sql: tablas, restricciones, índices, secuencias, vistas, paquetes y triggers =====
@DDL.sql
PROMPT ===== 2/2  DATOS.sql: datos de prueba =====
@DATOS.sql
EXIT
