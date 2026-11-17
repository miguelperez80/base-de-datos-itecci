-- =====================================================================
-- ITECCI - Avance PL/SQL
-- DICCIONARIO.sql : (i) revisión del diccionario de datos de Oracle (vistas USER_*)
-- Ejecutar como ITECCI. Se excluyen las tablas internas de la extensión de VS Code (DBTOOLS$...).
-- =====================================================================

-- ---------------------------------------------------------------------
-- DD1. TABLAS del esquema: columnas, filas, llaves y restricciones de cada una
-- ---------------------------------------------------------------------
SELECT t.table_name                                                     AS tabla,
       (SELECT COUNT(*) FROM user_tab_columns c WHERE c.table_name = t.table_name) AS columnas,
       (SELECT COUNT(*) FROM user_constraints k WHERE k.table_name = t.table_name AND k.constraint_type = 'R') AS llaves_foraneas,
       (SELECT COUNT(*) FROM user_constraints k WHERE k.table_name = t.table_name AND k.constraint_type = 'U') AS unicas,
       (SELECT COUNT(*) FROM user_constraints k WHERE k.table_name = t.table_name AND k.constraint_type = 'C'
                                                  AND k.constraint_name NOT LIKE 'SYS_%') AS checks,
       (SELECT COUNT(*) FROM user_triggers g    WHERE g.table_name = t.table_name) AS triggers,
       t.tablespace_name
  FROM user_tables t
 WHERE t.table_name NOT LIKE 'DBTOOLS%'
 ORDER BY t.table_name;

-- DD2. Columnas de una tabla (tipo, longitud, nulos y valor por defecto)
SELECT column_id, column_name, data_type,
       CASE WHEN data_type = 'NUMBER' AND data_precision IS NOT NULL
            THEN data_precision || ',' || data_scale
            WHEN data_type IN ('VARCHAR2', 'CHAR') THEN TO_CHAR(char_length) END AS longitud,
       nullable, data_default
  FROM user_tab_columns
 WHERE table_name = 'PAGO'
 ORDER BY column_id;

-- DD3. Restricciones de una tabla con sus columnas y su condición
SELECT k.constraint_name, k.constraint_type, cc.column_name, k.search_condition, k.r_constraint_name
  FROM user_constraints k
  LEFT JOIN user_cons_columns cc ON cc.constraint_name = k.constraint_name
 WHERE k.table_name = 'CALIFICACION' AND k.constraint_name NOT LIKE 'SYS_%'
 ORDER BY k.constraint_type, k.constraint_name;

-- ---------------------------------------------------------------------
-- DD4. PROCEDIMIENTOS, FUNCIONES Y PAQUETES: estado, fecha y líneas de código
-- ---------------------------------------------------------------------
SELECT o.object_type, o.object_name, o.status,
       TO_CHAR(o.last_ddl_time, 'DD/MM/YYYY HH24:MI') AS ultima_compilacion,
       (SELECT COUNT(*) FROM user_source s WHERE s.name = o.object_name AND s.type = o.object_type) AS lineas
  FROM user_objects o
 WHERE o.object_type IN ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY')
 ORDER BY o.object_type, o.object_name;

-- DD5. Subprogramas publicados por cada paquete
SELECT object_name AS paquete, procedure_name AS subprograma, subprogram_id
  FROM user_procedures
 WHERE object_type = 'PACKAGE' AND procedure_name IS NOT NULL
 ORDER BY object_name, subprogram_id;

-- DD6. Parámetros de un procedimiento (firma de PKG_ESTUDIANTE.INSERTAR)
SELECT position, argument_name, data_type, in_out, defaulted
  FROM user_arguments
 WHERE package_name = 'PKG_ESTUDIANTE' AND object_name = 'INSERTAR'
 ORDER BY position;

-- ---------------------------------------------------------------------
-- DD7. TRIGGERS: tabla, momento, evento y estado
-- ---------------------------------------------------------------------
SELECT trigger_name, table_name, trigger_type, triggering_event, status
  FROM user_triggers
 ORDER BY table_name, trigger_name;

-- DD8. ÍNDICES con sus columnas (incluye el índice basado en función)
SELECT i.table_name, i.index_name, i.index_type, i.uniqueness,
       ic.column_position, ic.column_name, ie.column_expression
  FROM user_indexes i
  JOIN user_ind_columns ic          ON ic.index_name = i.index_name
  LEFT JOIN user_ind_expressions ie ON ie.index_name = i.index_name AND ie.column_position = ic.column_position
 WHERE i.index_name LIKE 'IX\_%' ESCAPE '\'
 ORDER BY i.table_name, i.index_name, ic.column_position;

-- DD9. SECUENCIAS y su valor actual
SELECT sequence_name, min_value, increment_by, cache_size, last_number
  FROM user_sequences
 ORDER BY sequence_name;

-- DD10. VISTAS del esquema
SELECT view_name, text_length
  FROM user_views
 WHERE view_name LIKE 'V\_%' ESCAPE '\'
 ORDER BY view_name;

-- DD11. Errores de compilación (debe salir vacío)
SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, sequence;
