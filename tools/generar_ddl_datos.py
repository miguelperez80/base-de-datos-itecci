"""
Genera DDL.sql y DATOS.sql, los dos scripts con los que se reconstruye toda la base de datos ITECCI.

  DDL.sql   = limpieza + 02_ddl + 04_plsql_vistas + 07_plsql_objetos + 11_api_paquetes + permisos
  DATOS.sql = INSERT de 03_dml (con los triggers desactivados durante la carga)

Los scripts numerados siguen siendo la fuente (separados por avance). Si se cambia uno, ejecutar:
    python tools/generar_ddl_datos.py
"""
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
leer = lambda nombre: (RAIZ / nombre).read_text(encoding="utf-8")


def cuerpo(texto, desde=None, hasta=None):
    """Quita el encabezado de comentarios inicial y los SET; corta en las marcas indicadas."""
    if hasta:
        texto = texto[: texto.index(hasta)]
    if desde:
        texto = texto[texto.index(desde):]
    lineas = texto.splitlines()
    i = 0
    while not desde and i < len(lineas) and (lineas[i].startswith("--") or not lineas[i].strip() or lineas[i].startswith("SET ")):
        i += 1
    return "\n".join(l for l in lineas[i:] if not l.startswith("SET ")).strip() + "\n"


def seccion(titulo):
    return f"\n-- {'#' * 69}\n-- {titulo}\n-- {'#' * 69}\n"


TABLAS_CON_TRIGGERS = ["ESTUDIANTE", "DOCENTE", "GRUPO", "HORARIO_GRUPO", "MATRICULA", "PAGO", "CALIFICACION", "DIPLOMA"]

PERMISOS_FIJOS = [
    "GRANT SELECT ON v_estado_credito TO rol_coordinador", "GRANT SELECT ON v_estado_credito TO rol_secretaria",
    "GRANT SELECT ON v_boletin TO rol_coordinador", "GRANT SELECT ON v_boletin TO rol_secretaria",
    "GRANT INSERT, UPDATE ON estudiante TO rol_secretaria", "GRANT INSERT, UPDATE ON documento_estudiante TO rol_secretaria",
    "GRANT INSERT, UPDATE ON matricula TO rol_secretaria", "GRANT INSERT, UPDATE ON cuota TO rol_secretaria",
    "GRANT INSERT, UPDATE ON pago TO rol_secretaria", "GRANT INSERT ON aplicacion_pago TO rol_secretaria",
    "GRANT INSERT, UPDATE ON sesion_clase TO rol_secretaria", "GRANT INSERT, UPDATE ON asistencia TO rol_secretaria",
    "GRANT INSERT, UPDATE ON calificacion TO rol_secretaria",
    "GRANT EXECUTE ON sp_matricular TO rol_secretaria", "GRANT EXECUTE ON sp_registrar_pago TO rol_secretaria",
    "GRANT EXECUTE ON sp_matricular TO rol_coordinador", "GRANT EXECUTE ON sp_registrar_pago TO rol_coordinador",
    "REVOKE SELECT ON usuario FROM rol_secretaria",
    # 07_plsql_objetos.sql, sección 6
    "GRANT SELECT ON v_asistencia_matricula TO rol_coordinador", "GRANT SELECT ON v_asistencia_matricula TO rol_secretaria",
    "GRANT SELECT ON auditoria TO rol_coordinador",
    "GRANT EXECUTE ON pkg_util TO rol_coordinador", "GRANT EXECUTE ON pkg_estudiante TO rol_coordinador",
    "GRANT EXECUTE ON pkg_docente TO rol_coordinador", "GRANT EXECUTE ON pkg_grupo TO rol_coordinador",
    "GRANT EXECUTE ON pkg_calificacion TO rol_coordinador", "GRANT EXECUTE ON pkg_certificacion TO rol_coordinador",
    "GRANT EXECUTE ON pkg_util TO rol_secretaria", "GRANT EXECUTE ON pkg_estudiante TO rol_secretaria",
    "GRANT EXECUTE ON pkg_calificacion TO rol_secretaria",
]

BLOQUE_PERMISOS = """\
-- Permisos de los roles (05_roles_permisos.sql y sección 6 de 07_plsql_objetos.sql).
-- Los roles los crea 01_usuarios.sql (como SYSTEM). Si no existen, se avisa y el script continúa.
DECLARE
  TYPE t_lista IS TABLE OF VARCHAR2(200);
  v_fijos t_lista := t_lista(
{fijos});
  v_fallos PLS_INTEGER := 0;
  PROCEDURE ejecutar (p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
  EXCEPTION
    WHEN OTHERS THEN
      v_fallos := v_fallos + 1;
      IF v_fallos <= 3 THEN DBMS_OUTPUT.PUT_LINE('Permiso no aplicado (' || p_sql || '): ' || SQLERRM); END IF;
  END;
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN ({tablas})) LOOP
    ejecutar('GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO rol_coordinador');
    ejecutar('GRANT SELECT ON ' || t.table_name || ' TO rol_secretaria');
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ\\_%' ESCAPE '\\') LOOP
    ejecutar('GRANT SELECT ON ' || s.sequence_name || ' TO rol_coordinador');
    ejecutar('GRANT SELECT ON ' || s.sequence_name || ' TO rol_secretaria');
  END LOOP;
  FOR i IN 1 .. v_fijos.COUNT LOOP
    ejecutar(v_fijos(i));
  END LOOP;
  IF v_fallos = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Permisos de los roles aplicados.');
  ELSE
    DBMS_OUTPUT.PUT_LINE(v_fallos || ' permisos no se aplicaron: ejecute 01_usuarios.sql como SYSTEM y luego vuelva a correr DDL.sql.');
  END IF;
END;
/
"""

TABLAS_MODELO = ("'TECNICO','COMPETENCIA','PERIODO','AULA','USUARIO','DOCENTE','DOCENTE_FORMACION','CONTRATO_DOCENTE',"
                 "'GRUPO','HORARIO_GRUPO','ESTUDIANTE','DOCUMENTO_ESTUDIANTE','MATRICULA','MEDIO_PAGO','CUOTA','PAGO',"
                 "'APLICACION_PAGO','SESION_CLASE','ASISTENCIA','CALIFICACION','DIPLOMA'")


def generar_ddl():
    fijos = ",\n".join(f"    '{s}'" for s in PERMISOS_FIJOS)
    partes = [
        """\
-- =====================================================================
-- ITECCI - Técnicos Laborales por Competencias (Cámara de Comercio de Ipiales)
-- DDL.sql : definición COMPLETA de la base de datos. Reconstruye todo el esquema desde cero.
--
--   1. Limpieza de los objetos anteriores (si existen)
--   2. 22 tablas con sus restricciones (PK, FK, UNIQUE, CHECK), índices y secuencias
--   3. Vistas y procedimientos almacenados (matrícula, pagos, plan de pagos)
--   4. Avance PL/SQL: tabla AUDITORIA, índices y secuencias justificados, vista,
--      paquetes PKG_* y 7 triggers de reglas de negocio
--   5. Paquetes PKG_API_* de la aplicación web y 3 triggers complementarios
--   6. Permisos de los roles
--
-- Orden de reconstrucción:
--   (una sola vez, como SYSTEM)  01_usuarios.sql   crea el usuario ITECCI y los roles
--   (como ITECCI)                DDL.sql           este archivo
--   (como ITECCI)                DATOS.sql         datos de prueba
--
-- Generado con tools/generar_ddl_datos.py a partir de 02, 04, 05, 07 y 11 (que se conservan
-- separados como evidencia de cada avance). Compatible con Oracle 12.2 o superior.
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
""",
        seccion("1. LIMPIEZA (borra los objetos del proyecto si ya existen)"),
        cuerpo(leer("00_limpiar.sql")),
        seccion("2. TABLAS, RESTRICCIONES, ÍNDICES Y SECUENCIAS  (02_ddl.sql)"),
        cuerpo(leer("02_ddl.sql")).replace(
            "-- Limpieza opcional (descomentar para recrear): DROP TABLE ... CASCADE CONSTRAINTS;\n", ""),
        seccion("3. VISTAS Y PROCEDIMIENTOS ALMACENADOS  (04_plsql_vistas.sql)"),
        cuerpo(leer("04_plsql_vistas.sql")),
        seccion("4. AVANCE PL/SQL: AUDITORÍA, ÍNDICES, SECUENCIAS, VISTA, PAQUETES Y TRIGGERS  (07_plsql_objetos.sql)"),
        cuerpo(leer("07_plsql_objetos.sql"), desde="-- =====================================================================\n-- 1. (j)", hasta="-- =====================================================================\n-- 6. PERMISOS"),
        seccion("5. PAQUETES DE LA APLICACIÓN WEB Y TRIGGERS COMPLEMENTARIOS  (11_api_paquetes.sql)"),
        cuerpo(leer("11_api_paquetes.sql"), hasta="-- Verificación: no debe quedar ningún objeto inválido"),
        seccion("6. PERMISOS DE LOS ROLES"),
        BLOQUE_PERMISOS.format(fijos=fijos, tablas=TABLAS_MODELO + ",'AUDITORIA'"),
        seccion("VERIFICACIÓN"),
        """\
SET PAGESIZE 100 LINESIZE 150
PROMPT Objetos del esquema (la columna INVALIDOS debe quedar en 0):
SELECT object_type, COUNT(*) AS cantidad, SUM(DECODE(status, 'INVALID', 1, 0)) AS invalidos
  FROM user_objects
 WHERE object_name NOT LIKE 'BIN$%' AND object_name NOT LIKE 'DBTOOLS$%'
 GROUP BY object_type
 ORDER BY object_type;
SELECT name, type, line, SUBSTR(text, 1, 100) AS error FROM user_errors WHERE name NOT LIKE 'BIN$%' ORDER BY name, sequence;
""",
    ]
    return "".join(partes)


def generar_datos():
    dml = leer("03_dml.sql")
    inserts = dml[dml.index("-- TECNICO"):]
    inserts = inserts[: inserts.rindex("COMMIT;")].rstrip() + "\n"
    desactivar = "\n".join(f"ALTER TABLE {t.lower()} DISABLE ALL TRIGGERS;" for t in TABLAS_CON_TRIGGERS)
    activar = "\n".join(f"ALTER TABLE {t.lower()} ENABLE ALL TRIGGERS;" for t in TABLAS_CON_TRIGGERS)
    return f"""\
-- =====================================================================
-- ITECCI - Técnicos Laborales por Competencias (Cámara de Comercio de Ipiales)
-- DATOS.sql : datos de prueba (sintéticos) para llenar toda la base de datos. Ejecutar DESPUÉS de DDL.sql.
--
--   21 tablas · ≈10.500 registros · 4 periodos (2025-A a 2026-B), 6 programas, 214 estudiantes,
--   350 matrículas con su plan de pagos, 1.149 recibos, asistencia, calificaciones y 14 diplomas.
--
-- Por qué se desactivan los triggers durante la carga:
--   son datos HISTÓRICOS ya consistentes, y los triggers validan operaciones NUEVAS. Varios dependen de
--   la fecha actual o del estado final de la matrícula (por ejemplo, hay 12 notas de estudiantes que
--   se calificaron y DESPUÉS se retiraron, y los diplomas exigen "sin mora" a la fecha de hoy). Además,
--   TRG_AUDITORIA_PAGO llenaría AUDITORIA con la carga inicial. Al final se vuelven a activar.
--   Las restricciones del DDL (PK, FK, UNIQUE, CHECK) sí se aplican a cada INSERT.
--
-- Usuarios de la aplicación (contraseña con hash bcrypt):
--   coordinador / Coord2026#    secretaria / Secre2026#
--
-- Generado con tools/generar_ddl_datos.py a partir de 03_dml.sql.
-- =====================================================================
SET DEFINE OFF
SET FEEDBACK OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

PROMPT Desactivando triggers durante la carga...
{desactivar}

PROMPT Cargando datos (tarda cerca de un minuto)...
{inserts}
COMMIT;

PROMPT Activando de nuevo los triggers...
{activar}

EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER)
SET FEEDBACK ON PAGESIZE 100 LINESIZE 150

PROMPT Registros cargados por tabla:
SELECT 'TECNICO' AS tabla, COUNT(*) AS filas FROM tecnico UNION ALL
SELECT 'COMPETENCIA', COUNT(*) FROM competencia UNION ALL
SELECT 'PERIODO', COUNT(*) FROM periodo UNION ALL
SELECT 'AULA', COUNT(*) FROM aula UNION ALL
SELECT 'USUARIO', COUNT(*) FROM usuario UNION ALL
SELECT 'MEDIO_PAGO', COUNT(*) FROM medio_pago UNION ALL
SELECT 'DOCENTE', COUNT(*) FROM docente UNION ALL
SELECT 'DOCENTE_FORMACION', COUNT(*) FROM docente_formacion UNION ALL
SELECT 'CONTRATO_DOCENTE', COUNT(*) FROM contrato_docente UNION ALL
SELECT 'GRUPO', COUNT(*) FROM grupo UNION ALL
SELECT 'HORARIO_GRUPO', COUNT(*) FROM horario_grupo UNION ALL
SELECT 'ESTUDIANTE', COUNT(*) FROM estudiante UNION ALL
SELECT 'DOCUMENTO_ESTUDIANTE', COUNT(*) FROM documento_estudiante UNION ALL
SELECT 'MATRICULA', COUNT(*) FROM matricula UNION ALL
SELECT 'CUOTA', COUNT(*) FROM cuota UNION ALL
SELECT 'PAGO', COUNT(*) FROM pago UNION ALL
SELECT 'APLICACION_PAGO', COUNT(*) FROM aplicacion_pago UNION ALL
SELECT 'SESION_CLASE', COUNT(*) FROM sesion_clase UNION ALL
SELECT 'ASISTENCIA', COUNT(*) FROM asistencia UNION ALL
SELECT 'CALIFICACION', COUNT(*) FROM calificacion UNION ALL
SELECT 'DIPLOMA', COUNT(*) FROM diploma;

PROMPT Triggers (todos deben quedar ENABLED):
SELECT trigger_name, table_name, status FROM user_triggers ORDER BY table_name, trigger_name;
"""


if __name__ == "__main__":
    (RAIZ / "DDL.sql").write_text(generar_ddl(), encoding="utf-8", newline="\n")
    (RAIZ / "DATOS.sql").write_text(generar_datos(), encoding="utf-8", newline="\n")
    print("DDL.sql y DATOS.sql generados.")
