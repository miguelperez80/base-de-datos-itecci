-- =====================================================================
-- 11_api_paquetes.sql : paquetes PL/SQL que consume la aplicación web (API REST)
-- Ejecutar como ITECCI después de 07_plsql_objetos.sql.   Cada bloque termina en "/".
--
-- Estos paquetes son la interfaz de la API: devuelven cursores paginados y reciben las fechas como
-- texto. Llevan el prefijo PKG_API_ para no confundirse con los paquetes del avance PL/SQL
-- (PKG_ESTUDIANTE, PKG_DOCENTE, PKG_GRUPO...), que se conservan tal cual y cuyas reglas se reutilizan:
-- los triggers de 07 validan todo lo que la aplicación escribe, el recibo sale de PKG_UTIL.fn_siguiente_recibo
-- y la matrícula y el pago pasan por SP_MATRICULAR y SP_REGISTRAR_PAGO.
--
--   pkg_api_util        formato de datos (fechas AAAA-MM-DD, moneda)
--   pkg_api_seguridad   usuarios de la aplicación (inicio de sesión)
--   pkg_api_catalogo    listas de apoyo (periodos, aulas, medios de pago, ...)
--   pkg_api_estudiante  CRUD de estudiantes y sus documentos requisito
--   pkg_api_docente     CRUD de docentes
--   pkg_api_tecnico     CRUD de programas técnicos
--   pkg_api_grupo       CRUD de grupos y su horario
--   pkg_api_matricula   matrícula, retiro y plan de pagos
--   pkg_api_pago        recibos de caja: registro y anulación
--   pkg_api_reportes    indicadores y cartera
--   pkg_api_diccionario consultas al diccionario de datos
--
-- Códigos de error propios:  -20404 no existe | -2003x reglas de los paquetes | -20040 formato
-- =====================================================================
SET DEFINE OFF

-- =====================================================================
-- pkg_api_util : reglas de formato de datos
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_util AS
    c_formato_fecha CONSTANT VARCHAR2(10) := 'YYYY-MM-DD';
    FUNCTION a_fecha (p_texto IN VARCHAR2) RETURN DATE;
    FUNCTION moneda  (p_valor IN NUMBER)   RETURN VARCHAR2;
END pkg_api_util;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_util AS
    -- Convierte texto AAAA-MM-DD a DATE; cualquier otro formato se rechaza
    FUNCTION a_fecha (p_texto IN VARCHAR2) RETURN DATE IS
    BEGIN
        IF p_texto IS NULL THEN
            RETURN NULL;
        END IF;
        IF NOT REGEXP_LIKE(p_texto, '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') THEN
            RAISE_APPLICATION_ERROR(-20040, 'Fecha inválida (' || p_texto || '); el formato es AAAA-MM-DD');
        END IF;
        RETURN TO_DATE(p_texto, c_formato_fecha);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20040 THEN
                RAISE;
            END IF;
            RAISE_APPLICATION_ERROR(-20040, 'Fecha inválida (' || p_texto || '); el formato es AAAA-MM-DD');
    END a_fecha;

    -- Pesos colombianos: $1.250.000
    FUNCTION moneda (p_valor IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN '$' || TRIM(TO_CHAR(NVL(p_valor, 0), '999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.'''));
    END moneda;
END pkg_api_util;
/

-- =====================================================================
-- pkg_api_seguridad
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_seguridad AS
    FUNCTION  obtener_usuario (p_username IN VARCHAR2) RETURN SYS_REFCURSOR;
    PROCEDURE cambiar_clave   (p_username IN VARCHAR2, p_hash IN VARCHAR2);
END pkg_api_seguridad;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_seguridad AS
    FUNCTION obtener_usuario (p_username IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT id, username, nombre, rol, password_hash, activo
              FROM usuario WHERE username = LOWER(TRIM(p_username));
        RETURN v_cur;
    END obtener_usuario;

    PROCEDURE cambiar_clave (p_username IN VARCHAR2, p_hash IN VARCHAR2) IS
    BEGIN
        UPDATE usuario SET password_hash = p_hash WHERE username = LOWER(TRIM(p_username));
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El usuario no existe');
        END IF;
    END cambiar_clave;
END pkg_api_seguridad;
/

-- =====================================================================
-- pkg_api_catalogo
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_catalogo AS
    FUNCTION listar (p_nombre IN VARCHAR2) RETURN SYS_REFCURSOR;
END pkg_api_catalogo;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_catalogo AS
    FUNCTION listar (p_nombre IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        CASE p_nombre
            WHEN 'periodos' THEN
                OPEN v_cur FOR SELECT id, codigo AS nombre FROM periodo ORDER BY anio DESC, calendario DESC;
            WHEN 'aulas' THEN
                OPEN v_cur FOR SELECT id, nombre || ' (' || capacidad || ' puestos)' AS nombre FROM aula ORDER BY nombre;
            WHEN 'medios_pago' THEN
                OPEN v_cur FOR SELECT id, nombre FROM medio_pago ORDER BY id;
            WHEN 'tecnicos' THEN
                OPEN v_cur FOR SELECT id, nombre FROM tecnico WHERE activo = 1 ORDER BY nombre;
            WHEN 'docentes' THEN
                OPEN v_cur FOR SELECT id, apellidos || ' ' || nombres AS nombre FROM docente WHERE activo = 1 ORDER BY apellidos, nombres;
            WHEN 'grupos_abiertos' THEN
                OPEN v_cur FOR
                    SELECT g.id, g.codigo || ' · ' || t.nombre || ' (semestre ' || g.semestre || ')' AS nombre
                      FROM grupo g JOIN tecnico t ON t.id = g.tecnico_id
                     WHERE g.estado IN ('En formación', 'Activo')
                     ORDER BY g.codigo;
            ELSE
                RAISE_APPLICATION_ERROR(-20404, 'Catálogo desconocido: ' || p_nombre);
        END CASE;
        RETURN v_cur;
    END listar;
END pkg_api_catalogo;
/

-- =====================================================================
-- pkg_api_estudiante
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_estudiante AS
    PROCEDURE insertar (
        p_tipo_documento IN VARCHAR2, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
        p_fecha_nacimiento IN VARCHAR2, p_telefono IN VARCHAR2, p_email IN VARCHAR2, p_direccion IN VARCHAR2,
        p_ocupacion IN VARCHAR2, p_regimen_salud IN VARCHAR2, p_condicion_medica IN VARCHAR2, p_estrato IN NUMBER,
        p_estado_civil IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_autoriza_centrales IN NUMBER,
        p_doc_cedula IN NUMBER, p_doc_diploma IN NUMBER, p_doc_foto IN NUMBER, p_id OUT NUMBER);
    PROCEDURE actualizar (
        p_id IN NUMBER,
        p_tipo_documento IN VARCHAR2, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
        p_fecha_nacimiento IN VARCHAR2, p_telefono IN VARCHAR2, p_email IN VARCHAR2, p_direccion IN VARCHAR2,
        p_ocupacion IN VARCHAR2, p_regimen_salud IN VARCHAR2, p_condicion_medica IN VARCHAR2, p_estrato IN NUMBER,
        p_estado_civil IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_autoriza_centrales IN NUMBER,
        p_doc_cedula IN NUMBER, p_doc_diploma IN NUMBER, p_doc_foto IN NUMBER);
    PROCEDURE eliminar (p_id IN NUMBER);
    FUNCTION  obtener  (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    PROCEDURE listar   (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                        p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_estudiante;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_estudiante AS

    -- Deja registrado (o quita) un documento requisito según la casilla marcada en el formulario
    PROCEDURE guardar_documento (p_id IN NUMBER, p_tipo IN VARCHAR2, p_entregado IN NUMBER) IS
    BEGIN
        IF NVL(p_entregado, 0) = 1 THEN
            MERGE INTO documento_estudiante d
            USING (SELECT p_id AS estudiante_id, p_tipo AS tipo FROM dual) s
               ON (d.estudiante_id = s.estudiante_id AND d.tipo = s.tipo)
             WHEN NOT MATCHED THEN
                INSERT (id, estudiante_id, tipo, fecha_entrega)
                VALUES (seq_documento.NEXTVAL, s.estudiante_id, s.tipo, TRUNC(SYSDATE));
        ELSE
            DELETE FROM documento_estudiante WHERE estudiante_id = p_id AND tipo = p_tipo;
        END IF;
    END guardar_documento;

    PROCEDURE insertar (
        p_tipo_documento IN VARCHAR2, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
        p_fecha_nacimiento IN VARCHAR2, p_telefono IN VARCHAR2, p_email IN VARCHAR2, p_direccion IN VARCHAR2,
        p_ocupacion IN VARCHAR2, p_regimen_salud IN VARCHAR2, p_condicion_medica IN VARCHAR2, p_estrato IN NUMBER,
        p_estado_civil IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_autoriza_centrales IN NUMBER,
        p_doc_cedula IN NUMBER, p_doc_diploma IN NUMBER, p_doc_foto IN NUMBER, p_id OUT NUMBER) IS
    BEGIN
        SELECT seq_estudiante.NEXTVAL INTO p_id FROM dual;
        INSERT INTO estudiante (id, tipo_documento, cedula, nombres, apellidos, fecha_nacimiento, telefono, email,
                                direccion, ocupacion, regimen_salud, condicion_medica, estrato, estado_civil,
                                nivel_formacion, autoriza_centrales, fecha_autorizacion)
        VALUES (p_id, p_tipo_documento, p_cedula, p_nombres, p_apellidos, pkg_api_util.a_fecha(p_fecha_nacimiento),
                p_telefono, p_email, p_direccion, p_ocupacion, p_regimen_salud, p_condicion_medica, p_estrato,
                p_estado_civil, p_nivel_formacion, NVL(p_autoriza_centrales, 0),
                CASE WHEN NVL(p_autoriza_centrales, 0) = 1 THEN TRUNC(SYSDATE) END);
        guardar_documento(p_id, 'Cédula', p_doc_cedula);
        guardar_documento(p_id, 'Diploma de bachiller', p_doc_diploma);
        guardar_documento(p_id, 'Fotografía 3x4', p_doc_foto);
    END insertar;

    PROCEDURE actualizar (
        p_id IN NUMBER,
        p_tipo_documento IN VARCHAR2, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
        p_fecha_nacimiento IN VARCHAR2, p_telefono IN VARCHAR2, p_email IN VARCHAR2, p_direccion IN VARCHAR2,
        p_ocupacion IN VARCHAR2, p_regimen_salud IN VARCHAR2, p_condicion_medica IN VARCHAR2, p_estrato IN NUMBER,
        p_estado_civil IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_autoriza_centrales IN NUMBER,
        p_doc_cedula IN NUMBER, p_doc_diploma IN NUMBER, p_doc_foto IN NUMBER) IS
    BEGIN
        UPDATE estudiante
           SET tipo_documento = p_tipo_documento, cedula = p_cedula, nombres = p_nombres, apellidos = p_apellidos,
               fecha_nacimiento = pkg_api_util.a_fecha(p_fecha_nacimiento), telefono = p_telefono, email = p_email,
               direccion = p_direccion, ocupacion = p_ocupacion, regimen_salud = p_regimen_salud,
               condicion_medica = p_condicion_medica, estrato = p_estrato, estado_civil = p_estado_civil,
               nivel_formacion = p_nivel_formacion, autoriza_centrales = NVL(p_autoriza_centrales, 0),
               fecha_autorizacion = CASE WHEN NVL(p_autoriza_centrales, 0) = 1
                                         THEN NVL(fecha_autorizacion, TRUNC(SYSDATE)) END
         WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El estudiante no existe');
        END IF;
        guardar_documento(p_id, 'Cédula', p_doc_cedula);
        guardar_documento(p_id, 'Diploma de bachiller', p_doc_diploma);
        guardar_documento(p_id, 'Fotografía 3x4', p_doc_foto);
    END actualizar;

    PROCEDURE eliminar (p_id IN NUMBER) IS
        v_n NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_n FROM matricula WHERE estudiante_id = p_id;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(-20030, 'No se puede eliminar: el estudiante tiene ' || v_n || ' matrícula(s) registrada(s)');
        END IF;
        DELETE FROM estudiante WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El estudiante no existe');
        END IF;
    END eliminar;

    FUNCTION obtener (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT e.id, e.tipo_documento, e.cedula, e.nombres, e.apellidos,
                   TO_CHAR(e.fecha_nacimiento, pkg_api_util.c_formato_fecha) AS fecha_nacimiento,
                   e.telefono, e.email, e.direccion, e.ocupacion, e.regimen_salud, e.condicion_medica, e.estrato,
                   e.estado_civil, e.nivel_formacion, e.autoriza_centrales,
                   (SELECT COUNT(*) FROM documento_estudiante d WHERE d.estudiante_id = e.id AND d.tipo = 'Cédula') AS doc_cedula,
                   (SELECT COUNT(*) FROM documento_estudiante d WHERE d.estudiante_id = e.id AND d.tipo = 'Diploma de bachiller') AS doc_diploma,
                   (SELECT COUNT(*) FROM documento_estudiante d WHERE d.estudiante_id = e.id AND d.tipo = 'Fotografía 3x4') AS doc_foto
              FROM estudiante e WHERE e.id = p_id;
        RETURN v_cur;
    END obtener;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total FROM estudiante e
         WHERE v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
            OR UPPER(e.nombres || ' ' || e.apellidos) LIKE '%' || v_b || '%' OR e.cedula LIKE v_b || '%';
        OPEN p_cursor FOR
            SELECT e.id, e.tipo_documento, e.cedula, e.nombres, e.apellidos, e.telefono, e.email, e.ocupacion, e.estrato,
                   (SELECT COUNT(*) FROM documento_estudiante d WHERE d.estudiante_id = e.id) AS documentos,
                   (SELECT COUNT(*) FROM matricula m WHERE m.estudiante_id = e.id) AS matriculas
              FROM estudiante e
             WHERE v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
                OR UPPER(e.nombres || ' ' || e.apellidos) LIKE '%' || v_b || '%' OR e.cedula LIKE v_b || '%'
             ORDER BY e.apellidos, e.nombres
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_estudiante;
/

-- =====================================================================
-- pkg_api_docente
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_docente AS
    PROCEDURE insertar (p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2, p_email IN VARCHAR2,
                        p_telefono IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_anios_experiencia IN NUMBER,
                        p_activo IN NUMBER, p_id OUT NUMBER);
    PROCEDURE actualizar (p_id IN NUMBER, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
                        p_email IN VARCHAR2, p_telefono IN VARCHAR2, p_nivel_formacion IN VARCHAR2,
                        p_anios_experiencia IN NUMBER, p_activo IN NUMBER);
    PROCEDURE eliminar (p_id IN NUMBER);
    FUNCTION  obtener  (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    PROCEDURE listar   (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                        p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_docente;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_docente AS
    PROCEDURE insertar (p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2, p_email IN VARCHAR2,
                        p_telefono IN VARCHAR2, p_nivel_formacion IN VARCHAR2, p_anios_experiencia IN NUMBER,
                        p_activo IN NUMBER, p_id OUT NUMBER) IS
    BEGIN
        SELECT seq_docente.NEXTVAL INTO p_id FROM dual;
        INSERT INTO docente (id, cedula, nombres, apellidos, email, telefono, nivel_formacion, anios_experiencia_docencia, activo)
        VALUES (p_id, p_cedula, p_nombres, p_apellidos, p_email, p_telefono, p_nivel_formacion, p_anios_experiencia, NVL(p_activo, 1));
    END insertar;

    PROCEDURE actualizar (p_id IN NUMBER, p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2,
                        p_email IN VARCHAR2, p_telefono IN VARCHAR2, p_nivel_formacion IN VARCHAR2,
                        p_anios_experiencia IN NUMBER, p_activo IN NUMBER) IS
    BEGIN
        UPDATE docente
           SET cedula = p_cedula, nombres = p_nombres, apellidos = p_apellidos, email = p_email, telefono = p_telefono,
               nivel_formacion = p_nivel_formacion, anios_experiencia_docencia = p_anios_experiencia, activo = NVL(p_activo, 1)
         WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El docente no existe');
        END IF;
    END actualizar;

    PROCEDURE eliminar (p_id IN NUMBER) IS
        v_grupos    NUMBER;
        v_contratos NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_grupos    FROM grupo            WHERE docente_id = p_id;
        SELECT COUNT(*) INTO v_contratos FROM contrato_docente WHERE docente_id = p_id;
        IF v_grupos + v_contratos > 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'No se puede eliminar: el docente tiene ' || v_grupos || ' grupo(s) y '
                || v_contratos || ' contrato(s). Márquelo como inactivo.');
        END IF;
        DELETE FROM docente WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El docente no existe');
        END IF;
    END eliminar;

    FUNCTION obtener (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT id, cedula, nombres, apellidos, email, telefono, nivel_formacion,
                   anios_experiencia_docencia AS anios_experiencia, activo
              FROM docente WHERE id = p_id;
        RETURN v_cur;
    END obtener;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total FROM docente d
         WHERE v_b IS NULL OR UPPER(d.apellidos || ' ' || d.nombres) LIKE '%' || v_b || '%' OR d.cedula LIKE v_b || '%';
        OPEN p_cursor FOR
            SELECT d.id, d.cedula, d.nombres, d.apellidos, d.email, d.telefono, d.nivel_formacion,
                   d.anios_experiencia_docencia AS anios_experiencia, d.activo,
                   (SELECT COUNT(*) FROM grupo g WHERE g.docente_id = d.id) AS grupos
              FROM docente d
             WHERE v_b IS NULL OR UPPER(d.apellidos || ' ' || d.nombres) LIKE '%' || v_b || '%' OR d.cedula LIKE v_b || '%'
             ORDER BY d.apellidos, d.nombres
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_docente;
/

-- =====================================================================
-- pkg_api_tecnico
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_tecnico AS
    PROCEDURE insertar   (p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_activo IN NUMBER, p_id OUT NUMBER);
    PROCEDURE actualizar (p_id IN NUMBER, p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_activo IN NUMBER);
    PROCEDURE eliminar   (p_id IN NUMBER);
    FUNCTION  obtener    (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    PROCEDURE listar     (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                          p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_tecnico;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_tecnico AS
    PROCEDURE insertar (p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_activo IN NUMBER, p_id OUT NUMBER) IS
    BEGIN
        SELECT seq_tecnico.NEXTVAL INTO p_id FROM dual;
        INSERT INTO tecnico (id, codigo, nombre, activo) VALUES (p_id, UPPER(TRIM(p_codigo)), TRIM(p_nombre), NVL(p_activo, 1));
    END insertar;

    PROCEDURE actualizar (p_id IN NUMBER, p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_activo IN NUMBER) IS
    BEGIN
        UPDATE tecnico SET codigo = UPPER(TRIM(p_codigo)), nombre = TRIM(p_nombre), activo = NVL(p_activo, 1) WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El programa técnico no existe');
        END IF;
    END actualizar;

    PROCEDURE eliminar (p_id IN NUMBER) IS
        v_n NUMBER;
    BEGIN
        SELECT (SELECT COUNT(*) FROM grupo WHERE tecnico_id = p_id) + (SELECT COUNT(*) FROM competencia WHERE tecnico_id = p_id)
          INTO v_n FROM dual;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(-20032, 'No se puede eliminar: el programa tiene competencias o grupos. Márquelo como inactivo.');
        END IF;
        DELETE FROM tecnico WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El programa técnico no existe');
        END IF;
    END eliminar;

    FUNCTION obtener (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR SELECT id, codigo, nombre, activo FROM tecnico WHERE id = p_id;
        RETURN v_cur;
    END obtener;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total FROM tecnico t
         WHERE v_b IS NULL OR UPPER(t.nombre) LIKE '%' || v_b || '%' OR t.codigo LIKE v_b || '%';
        OPEN p_cursor FOR
            SELECT t.id, t.codigo, t.nombre, t.activo,
                   (SELECT COUNT(*) FROM competencia c WHERE c.tecnico_id = t.id) AS competencias,
                   (SELECT COUNT(*) FROM grupo g WHERE g.tecnico_id = t.id) AS grupos
              FROM tecnico t
             WHERE v_b IS NULL OR UPPER(t.nombre) LIKE '%' || v_b || '%' OR t.codigo LIKE v_b || '%'
             ORDER BY t.nombre
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_tecnico;
/

-- =====================================================================
-- pkg_api_grupo : el código se arma solo (SIS-2026B-S1) y el horario son dos días a la semana
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_grupo AS
    PROCEDURE insertar (p_tecnico_id IN NUMBER, p_periodo_id IN NUMBER, p_semestre IN NUMBER, p_docente_id IN NUMBER,
                        p_aula_id IN NUMBER, p_cupo_min IN NUMBER, p_cupo_max IN NUMBER, p_estado IN VARCHAR2,
                        p_dia1 IN NUMBER, p_dia2 IN NUMBER, p_id OUT NUMBER);
    PROCEDURE actualizar (p_id IN NUMBER, p_docente_id IN NUMBER, p_aula_id IN NUMBER, p_cupo_min IN NUMBER,
                        p_cupo_max IN NUMBER, p_estado IN VARCHAR2, p_dia1 IN NUMBER, p_dia2 IN NUMBER);
    PROCEDURE eliminar (p_id IN NUMBER);
    FUNCTION  obtener  (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    PROCEDURE listar   (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                        p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_grupo;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_grupo AS

    -- Un aula no puede tener dos grupos el mismo día en el mismo periodo (la jornada es única)
    -- El docente necesita contrato en el periodo (RN-12) y no puede dictar dos grupos el mismo día.
    -- Son las mismas reglas de PKG_GRUPO.crear (07_plsql_objetos.sql).
    PROCEDURE validar_horario (p_id IN NUMBER, p_periodo_id IN NUMBER, p_aula_id IN NUMBER, p_docente_id IN NUMBER,
                               p_dia1 IN NUMBER, p_dia2 IN NUMBER) IS
        v_otro grupo.codigo%TYPE;
        v_n    NUMBER;
    BEGIN
        IF p_dia1 = p_dia2 THEN
            RAISE_APPLICATION_ERROR(-20033, 'El grupo debe tener clase dos días distintos de la semana');
        END IF;
        SELECT COUNT(*) INTO v_n FROM contrato_docente WHERE docente_id = p_docente_id AND periodo_id = p_periodo_id;
        IF v_n = 0 THEN
            RAISE_APPLICATION_ERROR(-20042, 'El docente no tiene contrato por hora cátedra en ese periodo');
        END IF;
        SELECT MIN(g.codigo) INTO v_otro
          FROM grupo g JOIN horario_grupo h ON h.grupo_id = g.id
         WHERE g.periodo_id = p_periodo_id AND g.docente_id = p_docente_id AND g.estado <> 'Cancelado'
           AND h.dia_semana IN (p_dia1, p_dia2) AND g.id <> NVL(p_id, -1);
        IF v_otro IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(-20043, 'El docente ya dicta ese día el grupo ' || v_otro);
        END IF;
        SELECT MIN(g.codigo) INTO v_otro
          FROM grupo g JOIN horario_grupo h ON h.grupo_id = g.id
         WHERE g.periodo_id = p_periodo_id AND g.aula_id = p_aula_id AND g.estado <> 'Cancelado'
           AND h.dia_semana IN (p_dia1, p_dia2) AND g.id <> NVL(p_id, -1);
        IF v_otro IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(-20034, 'El aula ya está ocupada ese día por el grupo ' || v_otro);
        END IF;
    END validar_horario;

    PROCEDURE guardar_horario (p_id IN NUMBER, p_dia1 IN NUMBER, p_dia2 IN NUMBER) IS
    BEGIN
        DELETE FROM horario_grupo WHERE grupo_id = p_id;
        INSERT INTO horario_grupo (id, grupo_id, dia_semana) VALUES (seq_horario_grupo.NEXTVAL, p_id, p_dia1);
        INSERT INTO horario_grupo (id, grupo_id, dia_semana) VALUES (seq_horario_grupo.NEXTVAL, p_id, p_dia2);
    END guardar_horario;

    PROCEDURE insertar (p_tecnico_id IN NUMBER, p_periodo_id IN NUMBER, p_semestre IN NUMBER, p_docente_id IN NUMBER,
                        p_aula_id IN NUMBER, p_cupo_min IN NUMBER, p_cupo_max IN NUMBER, p_estado IN VARCHAR2,
                        p_dia1 IN NUMBER, p_dia2 IN NUMBER, p_id OUT NUMBER) IS
        v_codigo grupo.codigo%TYPE;
    BEGIN
        BEGIN
            SELECT t.codigo || '-' || p.anio || p.calendario || '-S' || p_semestre INTO v_codigo
              FROM tecnico t CROSS JOIN periodo p WHERE t.id = p_tecnico_id AND p.id = p_periodo_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20404, 'El programa técnico o el periodo no existen');
        END;
        validar_horario(NULL, p_periodo_id, p_aula_id, p_docente_id, p_dia1, p_dia2);
        SELECT seq_grupo.NEXTVAL INTO p_id FROM dual;
        INSERT INTO grupo (id, codigo, tecnico_id, periodo_id, semestre, docente_id, aula_id, cupo_min, cupo_max, estado)
        VALUES (p_id, v_codigo, p_tecnico_id, p_periodo_id, p_semestre, p_docente_id, p_aula_id,
                NVL(p_cupo_min, 15), NVL(p_cupo_max, 30), NVL(p_estado, 'En formación'));
        guardar_horario(p_id, p_dia1, p_dia2);
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20035, 'Ya existe el grupo ' || v_codigo || ' (mismo programa, periodo y semestre)');
    END insertar;

    PROCEDURE actualizar (p_id IN NUMBER, p_docente_id IN NUMBER, p_aula_id IN NUMBER, p_cupo_min IN NUMBER,
                        p_cupo_max IN NUMBER, p_estado IN VARCHAR2, p_dia1 IN NUMBER, p_dia2 IN NUMBER) IS
        v_periodo grupo.periodo_id%TYPE;
        v_n       NUMBER;
    BEGIN
        BEGIN
            SELECT periodo_id INTO v_periodo FROM grupo WHERE id = p_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20404, 'El grupo no existe');
        END;
        SELECT COUNT(*) INTO v_n FROM matricula WHERE grupo_id = p_id AND estado <> 'Retirada';
        IF v_n > p_cupo_max THEN
            RAISE_APPLICATION_ERROR(-20036, 'El cupo máximo no puede ser menor que los ' || v_n || ' matriculados');
        END IF;
        validar_horario(p_id, v_periodo, p_aula_id, p_docente_id, p_dia1, p_dia2);
        UPDATE grupo
           SET docente_id = p_docente_id, aula_id = p_aula_id, cupo_min = p_cupo_min, cupo_max = p_cupo_max, estado = p_estado
         WHERE id = p_id;
        guardar_horario(p_id, p_dia1, p_dia2);
    END actualizar;

    PROCEDURE eliminar (p_id IN NUMBER) IS
        v_n NUMBER;
    BEGIN
        SELECT (SELECT COUNT(*) FROM matricula WHERE grupo_id = p_id) + (SELECT COUNT(*) FROM sesion_clase WHERE grupo_id = p_id)
          INTO v_n FROM dual;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(-20037, 'No se puede eliminar: el grupo tiene matrículas o clases registradas. Cámbielo a Cancelado.');
        END IF;
        DELETE FROM grupo WHERE id = p_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El grupo no existe');
        END IF;
    END eliminar;

    FUNCTION obtener (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT g.id, g.codigo, g.tecnico_id, g.periodo_id, g.semestre, g.docente_id, g.aula_id, g.cupo_min, g.cupo_max, g.estado,
                   (SELECT MIN(h.dia_semana) FROM horario_grupo h WHERE h.grupo_id = g.id) AS dia1,
                   (SELECT MAX(h.dia_semana) FROM horario_grupo h WHERE h.grupo_id = g.id) AS dia2
              FROM grupo g WHERE g.id = p_id;
        RETURN v_cur;
    END obtener;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total
          FROM grupo g JOIN tecnico t ON t.id = g.tecnico_id JOIN docente d ON d.id = g.docente_id
         WHERE v_b IS NULL OR UPPER(g.codigo) LIKE '%' || v_b || '%' OR UPPER(t.nombre) LIKE '%' || v_b || '%'
            OR UPPER(d.apellidos || ' ' || d.nombres) LIKE '%' || v_b || '%';
        OPEN p_cursor FOR
            SELECT g.id, g.codigo, t.nombre AS tecnico, p.codigo AS periodo, g.semestre,
                   d.apellidos || ' ' || d.nombres AS docente, a.nombre AS aula, g.cupo_max, g.estado,
                   (SELECT COUNT(*) FROM matricula m WHERE m.grupo_id = g.id AND m.estado <> 'Retirada') AS matriculados,
                   (SELECT LISTAGG(DECODE(h.dia_semana, 1, 'Lun', 2, 'Mar', 3, 'Mié', 4, 'Jue', 5, 'Vie', 6, 'Sáb'), ' y ')
                           WITHIN GROUP (ORDER BY h.dia_semana)
                      FROM horario_grupo h WHERE h.grupo_id = g.id) AS dias
              FROM grupo g
              JOIN tecnico t ON t.id = g.tecnico_id
              JOIN periodo p ON p.id = g.periodo_id
              JOIN docente d ON d.id = g.docente_id
              JOIN aula a    ON a.id = g.aula_id
             WHERE v_b IS NULL OR UPPER(g.codigo) LIKE '%' || v_b || '%' OR UPPER(t.nombre) LIKE '%' || v_b || '%'
                OR UPPER(d.apellidos || ' ' || d.nombres) LIKE '%' || v_b || '%'
             ORDER BY p.anio DESC, p.calendario DESC, g.codigo
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_grupo;
/

-- =====================================================================
-- pkg_api_matricula : usa sp_matricular (reglas del negocio) y expone el plan de pagos
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_matricula AS
    PROCEDURE matricular (p_estudiante_id IN NUMBER, p_grupo_id IN NUMBER, p_usuario_id IN NUMBER, p_id OUT NUMBER);
    PROCEDURE retirar    (p_id IN NUMBER, p_observacion IN VARCHAR2);
    FUNCTION  obtener    (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION  cuotas     (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION  pagos      (p_id IN NUMBER) RETURN SYS_REFCURSOR;
    PROCEDURE listar     (p_busqueda IN VARCHAR2, p_estado IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                          p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_matricula;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_matricula AS
    PROCEDURE matricular (p_estudiante_id IN NUMBER, p_grupo_id IN NUMBER, p_usuario_id IN NUMBER, p_id OUT NUMBER) IS
        v_n NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_n FROM estudiante WHERE id = p_estudiante_id;
        IF v_n = 0 THEN
            RAISE_APPLICATION_ERROR(-20404, 'El estudiante no existe');
        END IF;
        SELECT COUNT(*) INTO v_n FROM matricula WHERE estudiante_id = p_estudiante_id AND grupo_id = p_grupo_id;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(-20038, 'El estudiante ya tiene una matrícula registrada en este grupo');
        END IF;
        sp_matricular(p_estudiante_id, p_grupo_id, p_usuario_id);
        SELECT id INTO p_id FROM matricula WHERE estudiante_id = p_estudiante_id AND grupo_id = p_grupo_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20404, 'El grupo no existe');
    END matricular;

    PROCEDURE retirar (p_id IN NUMBER, p_observacion IN VARCHAR2) IS
        v_estado matricula.estado%TYPE;
    BEGIN
        SELECT estado INTO v_estado FROM matricula WHERE id = p_id FOR UPDATE;
        IF v_estado <> 'Activa' THEN
            RAISE_APPLICATION_ERROR(-20039, 'Solo se puede retirar una matrícula activa (estado actual: ' || v_estado || ')');
        END IF;
        UPDATE matricula SET estado = 'Retirada', observaciones = SUBSTR(p_observacion, 1, 300) WHERE id = p_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20404, 'La matrícula no existe');
    END retirar;

    FUNCTION obtener (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT m.id, m.estado, TO_CHAR(m.fecha_ingreso, pkg_api_util.c_formato_fecha) AS fecha_ingreso, m.observaciones,
                   e.id AS estudiante_id, e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, e.telefono,
                   g.codigo AS grupo, t.nombre AS tecnico, g.semestre,
                   NVL(ec.total_obligado, 0) AS total_obligado, NVL(ec.total_pagado, 0) AS total_pagado,
                   NVL(ec.saldo, 0) AS saldo, NVL(ec.estado, 'Paz y salvo') AS estado_credito, NVL(ec.dias_mora, 0) AS dias_mora
              FROM matricula m
              JOIN estudiante e ON e.id = m.estudiante_id
              JOIN grupo g      ON g.id = m.grupo_id
              JOIN tecnico t    ON t.id = g.tecnico_id
              LEFT JOIN v_estado_credito ec ON ec.matricula_id = m.id
             WHERE m.id = p_id;
        RETURN v_cur;
    END obtener;

    FUNCTION cuotas (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT c.numero, c.concepto, c.valor, TO_CHAR(c.fecha_vencimiento, pkg_api_util.c_formato_fecha) AS fecha_vencimiento,
                   NVL(a.pagado, 0) AS pagado, c.valor - NVL(a.pagado, 0) AS saldo,
                   CASE WHEN NVL(a.pagado, 0) >= c.valor THEN 'Pagada'
                        WHEN c.fecha_vencimiento < TRUNC(SYSDATE) THEN 'Vencida'
                        ELSE 'Pendiente' END AS estado
              FROM cuota c
              LEFT JOIN (SELECT ap.cuota_id, SUM(ap.valor_aplicado) AS pagado
                           FROM aplicacion_pago ap JOIN pago p ON p.id = ap.pago_id
                          WHERE p.anulado = 0 GROUP BY ap.cuota_id) a ON a.cuota_id = c.id
             WHERE c.matricula_id = p_id
             ORDER BY c.numero;
        RETURN v_cur;
    END cuotas;

    FUNCTION pagos (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT p.id, p.numero_recibo, TO_CHAR(p.fecha_pago, pkg_api_util.c_formato_fecha) AS fecha_pago, p.valor,
                   mp.nombre AS medio_pago, p.referencia, p.anulado, p.factura_estado
              FROM pago p JOIN medio_pago mp ON mp.id = p.medio_pago_id
             WHERE p.matricula_id = p_id
             ORDER BY p.fecha_pago DESC, p.id DESC;
        RETURN v_cur;
    END pagos;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_estado IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total
          FROM matricula m JOIN estudiante e ON e.id = m.estudiante_id JOIN grupo g ON g.id = m.grupo_id
         WHERE (p_estado IS NULL OR m.estado = p_estado)
           AND (v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
                OR e.cedula LIKE v_b || '%' OR UPPER(g.codigo) LIKE '%' || v_b || '%');
        OPEN p_cursor FOR
            SELECT m.id, e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, g.codigo AS grupo,
                   TO_CHAR(m.fecha_ingreso, pkg_api_util.c_formato_fecha) AS fecha_ingreso, m.estado,
                   NVL(ec.saldo, 0) AS saldo, NVL(ec.estado, 'Paz y salvo') AS estado_credito
              FROM matricula m
              JOIN estudiante e ON e.id = m.estudiante_id
              JOIN grupo g      ON g.id = m.grupo_id
              LEFT JOIN v_estado_credito ec ON ec.matricula_id = m.id
             WHERE (p_estado IS NULL OR m.estado = p_estado)
               AND (v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
                    OR e.cedula LIKE v_b || '%' OR UPPER(g.codigo) LIKE '%' || v_b || '%')
             ORDER BY m.fecha_ingreso DESC, m.id DESC
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_matricula;
/

-- =====================================================================
-- pkg_api_pago : usa sp_registrar_pago (aplica el recibo a las cuotas más antiguas)
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_pago AS
    PROCEDURE registrar (p_matricula_id IN NUMBER, p_valor IN NUMBER, p_medio_pago_id IN NUMBER, p_referencia IN VARCHAR2,
                         p_usuario_id IN NUMBER, p_id OUT NUMBER, p_recibo OUT VARCHAR2);
    PROCEDURE anular    (p_id IN NUMBER, p_motivo IN VARCHAR2);
    PROCEDURE listar    (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                         p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_pago;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_pago AS
    PROCEDURE registrar (p_matricula_id IN NUMBER, p_valor IN NUMBER, p_medio_pago_id IN NUMBER, p_referencia IN VARCHAR2,
                         p_usuario_id IN NUMBER, p_id OUT NUMBER, p_recibo OUT VARCHAR2) IS
        v_estado matricula.estado%TYPE;
    BEGIN
        BEGIN
            SELECT estado INTO v_estado FROM matricula WHERE id = p_matricula_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20404, 'La matrícula no existe');
        END;
        p_recibo := pkg_util.fn_siguiente_recibo;   -- consecutivo sin saltos (SEQ_RECIBO, 07_plsql_objetos.sql)
        sp_registrar_pago(p_matricula_id, p_recibo, p_valor, p_medio_pago_id, p_usuario_id);
        SELECT id INTO p_id FROM pago WHERE numero_recibo = p_recibo;
        IF p_referencia IS NOT NULL THEN
            UPDATE pago SET referencia = SUBSTR(p_referencia, 1, 60) WHERE id = p_id;
        END IF;
    END registrar;

    PROCEDURE anular (p_id IN NUMBER, p_motivo IN VARCHAR2) IS
        v_anulado pago.anulado%TYPE;
    BEGIN
        SELECT anulado INTO v_anulado FROM pago WHERE id = p_id FOR UPDATE;
        IF v_anulado = 1 THEN
            RAISE_APPLICATION_ERROR(-20041, 'El recibo ya estaba anulado');
        END IF;
        UPDATE pago SET anulado = 1, factura_estado = 'Anulada', observacion = SUBSTR(p_motivo, 1, 300) WHERE id = p_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20404, 'El recibo no existe');
    END anular;

    PROCEDURE listar (p_busqueda IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                      p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total
          FROM pago p JOIN matricula m ON m.id = p.matricula_id JOIN estudiante e ON e.id = m.estudiante_id
         WHERE v_b IS NULL OR p.numero_recibo LIKE v_b || '%' OR e.cedula LIKE v_b || '%'
            OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%';
        OPEN p_cursor FOR
            SELECT p.id, p.numero_recibo, TO_CHAR(p.fecha_pago, pkg_api_util.c_formato_fecha) AS fecha_pago, p.valor,
                   mp.nombre AS medio_pago, p.referencia, p.anulado, p.factura_estado, p.matricula_id,
                   e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, g.codigo AS grupo
              FROM pago p
              JOIN medio_pago mp ON mp.id = p.medio_pago_id
              JOIN matricula m   ON m.id = p.matricula_id
              JOIN estudiante e  ON e.id = m.estudiante_id
              JOIN grupo g       ON g.id = m.grupo_id
             WHERE v_b IS NULL OR p.numero_recibo LIKE v_b || '%' OR e.cedula LIKE v_b || '%'
                OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
             ORDER BY p.fecha_pago DESC, p.id DESC
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END listar;
END pkg_api_pago;
/

-- =====================================================================
-- pkg_api_reportes
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_reportes AS
    FUNCTION  indicadores           RETURN SYS_REFCURSOR;
    FUNCTION  cartera_resumen       RETURN SYS_REFCURSOR;
    FUNCTION  recaudo_mensual       RETURN SYS_REFCURSOR;
    FUNCTION  matriculas_por_tecnico RETURN SYS_REFCURSOR;
    PROCEDURE cartera (p_busqueda IN VARCHAR2, p_estado IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                       p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR);
END pkg_api_reportes;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_reportes AS
    FUNCTION indicadores RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT (SELECT COUNT(*) FROM estudiante)                                        AS estudiantes,
                   (SELECT COUNT(*) FROM matricula WHERE estado = 'Activa')                 AS matriculas_activas,
                   (SELECT COUNT(*) FROM grupo WHERE estado IN ('En formación', 'Activo'))  AS grupos_abiertos,
                   (SELECT COUNT(*) FROM docente WHERE activo = 1)                          AS docentes_activos,
                   (SELECT NVL(SUM(valor), 0) FROM pago
                     WHERE anulado = 0 AND fecha_pago >= TRUNC(SYSDATE, 'MM'))              AS recaudo_mes,
                   (SELECT NVL(SUM(saldo), 0) FROM v_estado_credito)                        AS cartera_pendiente,
                   (SELECT COUNT(*) FROM v_estado_credito WHERE estado = 'En mora')         AS matriculas_en_mora
              FROM dual;
        RETURN v_cur;
    END indicadores;

    FUNCTION cartera_resumen RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT estado, COUNT(*) AS matriculas, SUM(saldo) AS saldo
              FROM v_estado_credito GROUP BY estado ORDER BY estado;
        RETURN v_cur;
    END cartera_resumen;

    -- Últimos 6 meses con recaudo
    FUNCTION recaudo_mensual RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT mes, recaudado, recibos
              FROM (SELECT TO_CHAR(fecha_pago, 'YYYY-MM') AS mes, SUM(valor) AS recaudado, COUNT(*) AS recibos
                      FROM pago WHERE anulado = 0
                     GROUP BY TO_CHAR(fecha_pago, 'YYYY-MM')
                     ORDER BY mes DESC
                     FETCH FIRST 6 ROWS ONLY)
             ORDER BY mes;
        RETURN v_cur;
    END recaudo_mensual;

    FUNCTION matriculas_por_tecnico RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT t.codigo, t.nombre AS tecnico, COUNT(m.id) AS matriculas
              FROM tecnico t
              LEFT JOIN grupo g     ON g.tecnico_id = t.id
              LEFT JOIN matricula m ON m.grupo_id = g.id AND m.estado <> 'Retirada'
             GROUP BY t.codigo, t.nombre
             ORDER BY COUNT(m.id) DESC, t.nombre;
        RETURN v_cur;
    END matriculas_por_tecnico;

    PROCEDURE cartera (p_busqueda IN VARCHAR2, p_estado IN VARCHAR2, p_offset IN NUMBER, p_limit IN NUMBER,
                       p_total OUT NUMBER, p_cursor OUT SYS_REFCURSOR) IS
        v_b VARCHAR2(200) := UPPER(TRIM(p_busqueda));
    BEGIN
        SELECT COUNT(*) INTO p_total
          FROM v_estado_credito ec JOIN estudiante e ON e.id = ec.estudiante_id JOIN grupo g ON g.id = ec.grupo_id
         WHERE (p_estado IS NULL OR ec.estado = p_estado)
           AND (v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
                OR e.cedula LIKE v_b || '%' OR UPPER(g.codigo) LIKE '%' || v_b || '%');
        OPEN p_cursor FOR
            SELECT ec.matricula_id AS id, e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, e.telefono,
                   g.codigo AS grupo, ec.total_obligado, ec.total_pagado, ec.saldo, ec.cuotas_vencidas, ec.dias_mora, ec.estado
              FROM v_estado_credito ec
              JOIN estudiante e ON e.id = ec.estudiante_id
              JOIN grupo g      ON g.id = ec.grupo_id
             WHERE (p_estado IS NULL OR ec.estado = p_estado)
               AND (v_b IS NULL OR UPPER(e.apellidos || ' ' || e.nombres) LIKE '%' || v_b || '%'
                    OR e.cedula LIKE v_b || '%' OR UPPER(g.codigo) LIKE '%' || v_b || '%')
             ORDER BY ec.dias_mora DESC, ec.saldo DESC, e.apellidos
            OFFSET NVL(p_offset, 0) ROWS FETCH NEXT NVL(p_limit, 20) ROWS ONLY;
    END cartera;
END pkg_api_reportes;
/

-- =====================================================================
-- pkg_api_diccionario : lo que la aplicación muestra del diccionario de datos de Oracle
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_api_diccionario AS
    FUNCTION contar_filas (p_tabla IN VARCHAR2) RETURN NUMBER;
    FUNCTION tablas   RETURN SYS_REFCURSOR;
    FUNCTION columnas (p_tabla IN VARCHAR2) RETURN SYS_REFCURSOR;
    FUNCTION objetos  RETURN SYS_REFCURSOR;
    FUNCTION subprogramas RETURN SYS_REFCURSOR;
END pkg_api_diccionario;
/
CREATE OR REPLACE PACKAGE BODY pkg_api_diccionario AS
    -- SQL dinámico seguro: el nombre se valida contra user_tables y con DBMS_ASSERT antes de concatenarlo
    FUNCTION contar_filas (p_tabla IN VARCHAR2) RETURN NUMBER IS
        v_nombre user_tables.table_name%TYPE;
        v_n      NUMBER;
    BEGIN
        SELECT table_name INTO v_nombre FROM user_tables WHERE table_name = UPPER(p_tabla);
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || DBMS_ASSERT.ENQUOTE_NAME(v_nombre, FALSE) INTO v_n;
        RETURN v_n;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20404, 'La tabla no existe en el esquema');
    END contar_filas;

    FUNCTION tablas RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT t.table_name AS tabla,
                   pkg_api_diccionario.contar_filas(t.table_name) AS filas,
                   (SELECT COUNT(*) FROM user_tab_columns c WHERE c.table_name = t.table_name) AS columnas,
                   (SELECT COUNT(*) FROM user_constraints k WHERE k.table_name = t.table_name) AS restricciones,
                   (SELECT COUNT(*) FROM user_indexes i WHERE i.table_name = t.table_name) AS indices,
                   (SELECT COUNT(*) FROM user_triggers g WHERE g.table_name = t.table_name) AS triggers
              FROM user_tables t
             WHERE t.table_name NOT LIKE 'DBTOOLS$%' AND t.table_name NOT LIKE 'BIN$%'
             ORDER BY t.table_name;
        RETURN v_cur;
    END tablas;

    FUNCTION columnas (p_tabla IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT c.column_id AS orden, c.column_name AS columna,
                   c.data_type || CASE WHEN c.data_type IN ('VARCHAR2', 'CHAR') THEN '(' || c.char_length || ')'
                                       WHEN c.data_type = 'NUMBER' AND c.data_precision IS NOT NULL
                                       THEN '(' || c.data_precision || CASE WHEN c.data_scale > 0 THEN ',' || c.data_scale END || ')'
                                  END AS tipo,
                   DECODE(c.nullable, 'N', 'No', 'Sí') AS admite_nulos,
                   (SELECT LISTAGG(DECODE(k.constraint_type, 'P', 'PK', 'R', 'FK', 'U', 'UNIQUE'), ', ')
                           WITHIN GROUP (ORDER BY k.constraint_type)
                      FROM user_cons_columns cc JOIN user_constraints k ON k.constraint_name = cc.constraint_name
                     WHERE cc.table_name = c.table_name AND cc.column_name = c.column_name
                       AND k.constraint_type IN ('P', 'R', 'U')) AS llaves
              FROM user_tab_columns c
             WHERE c.table_name = UPPER(p_tabla)
             ORDER BY c.column_id;
        RETURN v_cur;
    END columnas;

    FUNCTION objetos RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT object_name AS objeto, object_type AS tipo, status AS estado,
                   TO_CHAR(created, 'YYYY-MM-DD HH24:MI') AS creado, TO_CHAR(last_ddl_time, 'YYYY-MM-DD HH24:MI') AS modificado
              FROM user_objects
             WHERE object_type IN ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'TRIGGER', 'VIEW', 'SEQUENCE', 'INDEX')
               AND object_name NOT LIKE 'DBTOOLS$%' AND object_name NOT LIKE 'BIN$%' AND object_name NOT LIKE 'SYS\_%' ESCAPE '\'
             ORDER BY object_type, object_name;
        RETURN v_cur;
    END objetos;

    FUNCTION subprogramas RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT p.object_name AS objeto, p.object_type AS tipo, p.procedure_name AS subprograma,
                   (SELECT COUNT(*) FROM user_arguments a
                     WHERE a.object_id = p.object_id AND a.subprogram_id = p.subprogram_id AND a.argument_name IS NOT NULL) AS parametros
              FROM user_procedures p
             WHERE p.object_type IN ('PROCEDURE', 'FUNCTION') OR (p.object_type = 'PACKAGE' AND p.procedure_name IS NOT NULL)
             ORDER BY p.object_type, p.object_name, p.subprogram_id;
        RETURN v_cur;
    END subprogramas;
END pkg_api_diccionario;
/

-- =====================================================================
-- Triggers complementarios (no repiten los 7 de 07_plsql_objetos.sql).  Códigos -20020 a -20027
-- =====================================================================

-- Formato de datos del docente (el del estudiante lo cubre TRG_ESTUDIANTE_FORMATO)
CREATE OR REPLACE TRIGGER trg_docente_formato
BEFORE INSERT OR UPDATE ON docente
FOR EACH ROW
BEGIN
    :NEW.cedula    := TRIM(:NEW.cedula);
    :NEW.nombres   := INITCAP(REGEXP_REPLACE(TRIM(:NEW.nombres),   ' +', ' '));
    :NEW.apellidos := INITCAP(REGEXP_REPLACE(TRIM(:NEW.apellidos), ' +', ' '));
    :NEW.email     := LOWER(TRIM(:NEW.email));

    IF NOT REGEXP_LIKE(:NEW.cedula, '^[0-9]{6,10}$') THEN
        RAISE_APPLICATION_ERROR(-20020, 'Cédula inválida: solo dígitos, entre 6 y 10');
    END IF;
    IF NOT REGEXP_LIKE(:NEW.email, '^[a-z0-9._-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$') THEN
        RAISE_APPLICATION_ERROR(-20021, 'Correo electrónico inválido: ' || :NEW.email);
    END IF;
END trg_docente_formato;
/

-- El aula debe tener capacidad para el cupo y no se asigna un docente inactivo
CREATE OR REPLACE TRIGGER trg_grupo_asignacion
BEFORE INSERT OR UPDATE OF docente_id, aula_id, cupo_max ON grupo
FOR EACH ROW
DECLARE
    v_capacidad aula.capacidad%TYPE;
    v_activo    docente.activo%TYPE;
BEGIN
    SELECT capacidad INTO v_capacidad FROM aula WHERE id = :NEW.aula_id;
    IF :NEW.cupo_max > v_capacidad THEN
        RAISE_APPLICATION_ERROR(-20024, 'El cupo máximo (' || :NEW.cupo_max || ') supera la capacidad del aula (' || v_capacidad || ')');
    END IF;

    IF INSERTING OR :NEW.docente_id <> :OLD.docente_id THEN
        SELECT activo INTO v_activo FROM docente WHERE id = :NEW.docente_id;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(-20025, 'No se puede asignar un docente inactivo al grupo');
        END IF;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20026, 'El aula o el docente indicados no existen');
END trg_grupo_asignacion;
/

-- Una matrícula no cambia de estudiante ni de grupo, y una retirada no se reactiva
CREATE OR REPLACE TRIGGER trg_matricula_estado
BEFORE UPDATE ON matricula
FOR EACH ROW
BEGIN
    IF :NEW.estudiante_id <> :OLD.estudiante_id OR :NEW.grupo_id <> :OLD.grupo_id THEN
        RAISE_APPLICATION_ERROR(-20027, 'Una matrícula no se puede pasar a otro estudiante ni a otro grupo');
    END IF;
    IF :OLD.estado = 'Retirada' AND :NEW.estado <> 'Retirada' THEN
        RAISE_APPLICATION_ERROR(-20027, 'Una matrícula retirada no se puede reactivar; registre una nueva');
    END IF;
END trg_matricula_estado;
/

-- Verificación: no debe quedar ningún objeto inválido
SELECT object_name, object_type, status FROM user_objects WHERE status = 'INVALID';
