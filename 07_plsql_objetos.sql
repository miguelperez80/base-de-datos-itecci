-- =====================================================================
-- ITECCI - Avance PL/SQL
-- 07_plsql_objetos.sql : objetos PL/SQL sobre el modelo físico (Oracle 11g / 18c)
-- Ejecutar como ITECCI DESPUÉS de 02_ddl.sql, 03_dml.sql, 04_plsql_vistas.sql y 05_roles_permisos.sql.
-- Cada bloque PL/SQL termina en "/".
--
--   Sección 1  (j)   Tabla AUDITORIA, secuencias e índices (con justificación)
--   Sección 2  (h)   Vista V_ASISTENCIA_MATRICULA
--   Sección 3  (k)   Paquete PKG_UTIL: formatos de moneda, fecha y nota + funciones de negocio
--   Sección 4  (g,k) Triggers de reglas de negocio (7)
--   Sección 5  (b)   Paquetes CRUD: PKG_ESTUDIANTE, PKG_DOCENTE, PKG_GRUPO, PKG_CALIFICACION
--                    + PKG_CERTIFICACION (emisión de diplomas)
--   Sección 6        Permisos de los roles sobre los objetos nuevos
--
--   Los reportes (a) están en 08_reportes.sql, las pruebas de excepciones/triggers en 09_pruebas.sql
--   y las consultas al diccionario de datos (i) en 10_diccionario.sql.
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =====================================================================
-- 1. (j) TABLA DE AUDITORÍA, SECUENCIAS E ÍNDICES
-- =====================================================================

-- Bitácora de cambios sobre los pagos (la llena el trigger TRG_AUDITORIA_PAGO)
CREATE TABLE auditoria (
  id           NUMBER(8)     NOT NULL,
  tabla        VARCHAR2(30)  NOT NULL,
  operacion    VARCHAR2(10)  NOT NULL,
  registro_id  NUMBER(10)    NOT NULL,
  detalle      VARCHAR2(400),
  usuario_bd   VARCHAR2(30)  DEFAULT USER    NOT NULL,
  fecha        DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_auditoria    PRIMARY KEY (id),
  CONSTRAINT ck_auditoria_op CHECK (operacion IN ('INSERT','UPDATE','DELETE'))
);

-- ---------------------------------------------------------------------
-- Secuencias
-- ---------------------------------------------------------------------
-- SEQ_AUDITORIA: llave primaria de AUDITORIA.
CREATE SEQUENCE seq_auditoria START WITH 1 INCREMENT BY 1;

-- SEQ_RECIBO: consecutivo del recibo de caja. Los datos de prueba llegan al 12149.
-- NOCACHE porque el talonario de recibos no debe tener saltos de numeración (control contable).
CREATE SEQUENCE seq_recibo START WITH 12150 INCREMENT BY 1 NOCACHE;

-- SEQ_FACTURA: consecutivo de la factura electrónica (FE-000000). Los datos llegan al FE-002115.
-- NOCACHE por la misma razón: la DIAN exige numeración consecutiva.
CREATE SEQUENCE seq_factura START WITH 2116 INCREMENT BY 1 NOCACHE;

-- ---------------------------------------------------------------------
-- Índices (justificación)
-- ---------------------------------------------------------------------
-- IX_CALIF_COMPETENCIA: CALIFICACION.competencia_id es llave foránea sin índice. Sin él, borrar o
-- actualizar una COMPETENCIA bloquea toda la tabla CALIFICACION, y las consultas por competencia
-- (promedios C3, B4, boletín, prerrequisitos de PKG_CALIFICACION) hacen recorrido completo de 1.094+ filas.
-- Se incluyen tipo y nota para que esas consultas se resuelvan solo con el índice (índice "cubriente").
CREATE INDEX ix_calif_competencia ON calificacion (competencia_id, tipo, nota);

-- IX_PAGO_FACTURA: la secretaria consulta a diario los recibos con factura 'Pendiente' para emitirlas.
-- La distribución es muy sesgada (≈97 % 'Emitida', ≈3 % 'Pendiente'), así que el índice sí filtra:
-- la búsqueda de pendientes lee unas decenas de filas en lugar de las 1.149. fecha_pago va segunda
-- para devolverlas ya ordenadas por antigüedad (reporte R7 / consulta A6).
CREATE INDEX ix_pago_factura ON pago (factura_estado, fecha_pago);

-- IX_EST_APELLIDO_UPPER: índice basado en función. La búsqueda de estudiantes por apellido
-- (PKG_ESTUDIANTE.buscar) no distingue mayúsculas: WHERE UPPER(apellidos) LIKE UPPER(:x)||'%'.
-- El índice existente IX_ESTUDIANTE_APELL no sirve cuando la columna va dentro de UPPER().
CREATE INDEX ix_est_apellido_upper ON estudiante (UPPER(apellidos));

-- IX_AUDITORIA_REG: la auditoría se consulta por tabla y registro ("¿quién cambió el recibo X?").
CREATE INDEX ix_auditoria_reg ON auditoria (tabla, registro_id);

-- =====================================================================
-- 2. (h) VISTA DE ASISTENCIA POR MATRÍCULA
--    Porcentaje de asistencia de cada matrícula y si cumple el 80 % (RN-23).
--    La usan el trigger de diplomas, PKG_ESTUDIANTE y el reporte R3.
-- =====================================================================
CREATE OR REPLACE VIEW v_asistencia_matricula AS
SELECT m.id                         AS matricula_id,
       m.estudiante_id,
       m.grupo_id,
       g.tecnico_id,
       m.estado                     AS estado_matricula,
       COUNT(a.sesion_id)           AS sesiones,
       NVL(SUM(a.presente), 0)      AS asistidas,
       COUNT(a.sesion_id) - NVL(SUM(a.presente), 0) AS fallas,
       CASE WHEN COUNT(a.sesion_id) = 0 THEN NULL
            ELSE ROUND(100 * SUM(a.presente) / COUNT(a.sesion_id), 1) END AS porcentaje,
       CASE WHEN COUNT(a.sesion_id) = 0 THEN 'Sin sesiones'
            WHEN 100 * SUM(a.presente) / COUNT(a.sesion_id) >= 80 THEN 'Cumple'
            ELSE 'No cumple' END    AS estado_asistencia
  FROM matricula m
  JOIN grupo g           ON g.id = m.grupo_id
  LEFT JOIN asistencia a ON a.matricula_id = m.id
 GROUP BY m.id, m.estudiante_id, m.grupo_id, g.tecnico_id, m.estado;

-- =====================================================================
-- 3. (k) PAQUETE DE UTILIDADES: FORMATO DE DATOS Y FUNCIONES DE NEGOCIO
--    Regla de formato: los valores en pesos se muestran como $1.234.567 (punto de miles, sin
--    decimales), las fechas como DD/MM/AAAA o "05 de octubre de 2026" y las notas con un decimal (3.0).
--    Se fija NLS en cada TO_CHAR para que el resultado no dependa de la configuración del cliente.
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_util AS
  c_nota_aprueba  CONSTANT NUMBER := 3.0;
  c_asist_minima  CONSTANT NUMBER := 80;

  FUNCTION fn_moneda (p_valor NUMBER) RETURN VARCHAR2;
  FUNCTION fn_fecha (p_fecha DATE) RETURN VARCHAR2;
  FUNCTION fn_fecha_larga (p_fecha DATE) RETURN VARCHAR2;
  FUNCTION fn_nota (p_nota NUMBER) RETURN VARCHAR2;
  FUNCTION fn_dia (p_dia NUMBER) RETURN VARCHAR2;
  FUNCTION fn_pct_asistencia (p_matricula NUMBER) RETURN NUMBER;
  FUNCTION fn_saldo (p_matricula NUMBER) RETURN NUMBER;
  FUNCTION fn_estado_credito (p_estudiante NUMBER) RETURN VARCHAR2;
  FUNCTION fn_siguiente_recibo RETURN VARCHAR2;
  FUNCTION fn_siguiente_factura RETURN VARCHAR2;
  PROCEDURE pl (p_texto VARCHAR2);
END pkg_util;
/

CREATE OR REPLACE PACKAGE BODY pkg_util AS

  -- $1.234.567  (formato colombiano: punto de miles)
  FUNCTION fn_moneda (p_valor NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN '$' || TO_CHAR(NVL(p_valor, 0), 'FM999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.''');
  END fn_moneda;

  -- 05/10/2026
  FUNCTION fn_fecha (p_fecha DATE) RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(p_fecha, 'DD/MM/YYYY');
  END fn_fecha;

  -- 05 de octubre de 2026 (para diplomas y certificados)
  FUNCTION fn_fecha_larga (p_fecha DATE) RETURN VARCHAR2 IS
  BEGIN
    IF p_fecha IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN TO_CHAR(p_fecha, 'DD') || ' de '
        || TRIM(TO_CHAR(p_fecha, 'month', 'NLS_DATE_LANGUAGE=SPANISH')) || ' de '
        || TO_CHAR(p_fecha, 'YYYY');
  END fn_fecha_larga;

  -- 3.0 / 4.5
  FUNCTION fn_nota (p_nota NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(p_nota, 'FM0.0', 'NLS_NUMERIC_CHARACTERS=''.,''');
  END fn_nota;

  FUNCTION fn_dia (p_dia NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE p_dia WHEN 1 THEN 'Lunes'  WHEN 2 THEN 'Martes'  WHEN 3 THEN 'Miércoles'
                      WHEN 4 THEN 'Jueves' WHEN 5 THEN 'Viernes' WHEN 6 THEN 'Sábado'
                      ELSE 'Día inválido' END;
  END fn_dia;

  -- Porcentaje de asistencia de una matrícula; NULL si su grupo aún no tiene sesiones
  FUNCTION fn_pct_asistencia (p_matricula NUMBER) RETURN NUMBER IS
    v_total  NUMBER;
    v_asist  NUMBER;
  BEGIN
    SELECT COUNT(*), NVL(SUM(presente), 0) INTO v_total, v_asist
      FROM asistencia WHERE matricula_id = p_matricula;
    RETURN ROUND(v_asist * 100 / v_total, 1);
  EXCEPTION
    WHEN ZERO_DIVIDE THEN          -- sin sesiones registradas
      RETURN NULL;
  END fn_pct_asistencia;

  FUNCTION fn_saldo (p_matricula NUMBER) RETURN NUMBER IS
    v_saldo NUMBER;
  BEGIN
    SELECT saldo INTO v_saldo FROM v_estado_credito WHERE matricula_id = p_matricula;
    RETURN v_saldo;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN        -- matrícula sin plan de pagos
      RETURN 0;
  END fn_saldo;

  -- Estado consolidado de un estudiante (todas sus matrículas)
  FUNCTION fn_estado_credito (p_estudiante NUMBER) RETURN VARCHAR2 IS
    v_n     NUMBER;
    v_mora  NUMBER;
    v_saldo NUMBER;
  BEGIN
    SELECT COUNT(*), SUM(CASE WHEN estado = 'En mora' THEN 1 ELSE 0 END), SUM(saldo)
      INTO v_n, v_mora, v_saldo
      FROM v_estado_credito WHERE estudiante_id = p_estudiante;
    IF v_n = 0 THEN
      RETURN 'Sin matrículas';
    ELSIF v_mora > 0 THEN
      RETURN 'En mora';
    ELSIF v_saldo = 0 THEN
      RETURN 'Paz y salvo';
    ELSE
      RETURN 'Al día';
    END IF;
  END fn_estado_credito;

  FUNCTION fn_siguiente_recibo RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(seq_recibo.NEXTVAL);
  END fn_siguiente_recibo;

  -- FE-002116
  FUNCTION fn_siguiente_factura RETURN VARCHAR2 IS
  BEGIN
    RETURN 'FE-' || LPAD(seq_factura.NEXTVAL, 6, '0');
  END fn_siguiente_factura;

  PROCEDURE pl (p_texto VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_texto);
  END pl;

END pkg_util;
/

-- =====================================================================
-- 4. (g) TRIGGERS: REGLAS DE NEGOCIO SOBRE LOS DATOS DE LAS TABLAS
--    Códigos de error -20100 a -20199.
-- =====================================================================

-- ---------------------------------------------------------------------
-- T1 (k) ESTUDIANTE - formato de datos del Formulario de Matrícula
--   * cédula: solo dígitos, 6 a 10       * teléfono: celular colombiano, 10 dígitos que empiezan por 3
--   * email: formato usuario@dominio, se guarda en minúscula
--   * nombres y apellidos: sin espacios dobles y con mayúscula inicial
--   * CC exige mayoría de edad (18 años); TI es para menores
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_estudiante_formato
BEFORE INSERT OR UPDATE ON estudiante
FOR EACH ROW
DECLARE
  v_edad NUMBER;
BEGIN
  :NEW.cedula    := TRIM(:NEW.cedula);
  :NEW.telefono  := REGEXP_REPLACE(:NEW.telefono, '[^0-9]', '');
  :NEW.email     := LOWER(TRIM(:NEW.email));
  :NEW.nombres   := INITCAP(REGEXP_REPLACE(TRIM(:NEW.nombres),   ' +', ' '));
  :NEW.apellidos := INITCAP(REGEXP_REPLACE(TRIM(:NEW.apellidos), ' +', ' '));

  IF NOT REGEXP_LIKE(:NEW.cedula, '^[0-9]{6,10}$') THEN
    RAISE_APPLICATION_ERROR(-20101, 'Cédula inválida (' || :NEW.cedula || '): solo dígitos, entre 6 y 10');
  END IF;
  IF NOT REGEXP_LIKE(:NEW.telefono, '^3[0-9]{9}$') THEN
    RAISE_APPLICATION_ERROR(-20102, 'Teléfono inválido (' || :NEW.telefono || '): celular de 10 dígitos que inicia en 3');
  END IF;
  IF NOT REGEXP_LIKE(:NEW.email, '^[a-z0-9._-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$') THEN
    RAISE_APPLICATION_ERROR(-20103, 'Correo electrónico inválido: ' || :NEW.email);
  END IF;

  v_edad := TRUNC(MONTHS_BETWEEN(TRUNC(SYSDATE), :NEW.fecha_nacimiento) / 12);
  CASE
    WHEN :NEW.fecha_nacimiento > TRUNC(SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20104, 'La fecha de nacimiento no puede ser futura');
    WHEN :NEW.tipo_documento = 'CC' AND v_edad < 18 THEN
      RAISE_APPLICATION_ERROR(-20105, 'Con cédula de ciudadanía el estudiante debe ser mayor de edad (tiene ' || v_edad || ')');
    WHEN :NEW.tipo_documento = 'TI' AND v_edad >= 18 THEN
      RAISE_APPLICATION_ERROR(-20106, 'Un mayor de edad no puede registrarse con tarjeta de identidad');
    ELSE
      NULL;
  END CASE;

  -- RN-27: si autoriza centrales de información, la fecha se toma automáticamente
  IF :NEW.autoriza_centrales = 1 AND :NEW.fecha_autorizacion IS NULL THEN
    :NEW.fecha_autorizacion := TRUNC(SYSDATE);
  ELSIF :NEW.autoriza_centrales = 0 THEN
    :NEW.fecha_autorizacion := NULL;
  END IF;
END trg_estudiante_formato;
/

-- ---------------------------------------------------------------------
-- T2 HORARIO_GRUPO - RN-07 y RN-08 (trigger de sentencia, evita la tabla mutante)
--   * Un grupo tiene máximo 2 días de clase.
--   * Un aula no puede tener dos grupos el mismo día en el mismo periodo (única jornada nocturna).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_horario_reglas
AFTER INSERT OR UPDATE ON horario_grupo
BEGIN
  FOR r IN (SELECT g.codigo, COUNT(*) AS dias
              FROM horario_grupo h JOIN grupo g ON g.id = h.grupo_id
             GROUP BY g.codigo
            HAVING COUNT(*) > 2) LOOP
    RAISE_APPLICATION_ERROR(-20110, 'El grupo ' || r.codigo || ' quedaría con ' || r.dias || ' días de clase; máximo 2 (RN-07)');
  END LOOP;

  FOR r IN (SELECT a.nombre AS aula, p.codigo AS periodo, h.dia_semana
              FROM horario_grupo h
              JOIN grupo g   ON g.id = h.grupo_id
              JOIN aula a    ON a.id = g.aula_id
              JOIN periodo p ON p.id = g.periodo_id
             WHERE g.estado <> 'Cancelado'
             GROUP BY a.nombre, p.codigo, h.dia_semana
            HAVING COUNT(*) > 1) LOOP
    RAISE_APPLICATION_ERROR(-20111, r.aula || ' ya está ocupada el ' || pkg_util.fn_dia(r.dia_semana)
                                     || ' en el periodo ' || r.periodo || ' (RN-08)');
  END LOOP;
END trg_horario_reglas;
/

-- ---------------------------------------------------------------------
-- T3 CALIFICACION - coherencia de la nota con la matrícula (fila)
--   * La competencia pertenece al técnico y al semestre del grupo de la matrícula.
--   * No se califica una matrícula retirada ni con fecha futura.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_calificacion_valida
BEFORE INSERT OR UPDATE ON calificacion
FOR EACH ROW
DECLARE
  v_tec_grupo  grupo.tecnico_id%TYPE;
  v_sem_grupo  grupo.semestre%TYPE;
  v_estado     matricula.estado%TYPE;
  v_tec_comp   competencia.tecnico_id%TYPE;
  v_sem_comp   competencia.semestre%TYPE;
BEGIN
  SELECT g.tecnico_id, g.semestre, m.estado INTO v_tec_grupo, v_sem_grupo, v_estado
    FROM matricula m JOIN grupo g ON g.id = m.grupo_id
   WHERE m.id = :NEW.matricula_id;

  SELECT tecnico_id, semestre INTO v_tec_comp, v_sem_comp
    FROM competencia WHERE id = :NEW.competencia_id;

  IF v_tec_comp <> v_tec_grupo THEN
    RAISE_APPLICATION_ERROR(-20120, 'La competencia ' || :NEW.competencia_id || ' no pertenece al técnico del grupo');
  ELSIF v_sem_comp <> v_sem_grupo THEN
    RAISE_APPLICATION_ERROR(-20121, 'La competencia es del semestre ' || v_sem_comp || ' y el grupo es del semestre ' || v_sem_grupo);
  END IF;

  IF v_estado = 'Retirada' THEN
    RAISE_APPLICATION_ERROR(-20122, 'No se califica una matrícula retirada');
  END IF;

  :NEW.fecha := TRUNC(:NEW.fecha);
  IF :NEW.fecha > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20123, 'La fecha de la calificación no puede ser futura');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20124, 'Matrícula o competencia inexistente');
END trg_calificacion_valida;
/

-- ---------------------------------------------------------------------
-- T4 CALIFICACION - RN-22: solo hay supletorio si la nota ordinaria fue menor a 3.0
--   Trigger de sentencia: revisa la tabla completa después de insertar, actualizar o borrar
--   (por ejemplo, impide borrar la ordinaria perdida dejando un supletorio "huérfano").
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_calificacion_supletorio
AFTER INSERT OR UPDATE OR DELETE ON calificacion
DECLARE
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n
    FROM calificacion s
   WHERE s.tipo = 'Supletorio'
     AND NOT EXISTS (SELECT 1 FROM calificacion o
                      WHERE o.matricula_id   = s.matricula_id
                        AND o.competencia_id = s.competencia_id
                        AND o.tipo = 'Ordinaria'
                        AND o.nota < 3);
  IF v_n > 0 THEN
    RAISE_APPLICATION_ERROR(-20125, 'Supletorio no permitido: la competencia no tiene nota ordinaria perdida (RN-22)');
  END IF;
END trg_calificacion_supletorio;
/

-- ---------------------------------------------------------------------
-- T5 (k) PAGO - formato del recibo y de la factura, y reglas de la factura electrónica (RN-18)
--   * Recibo: solo dígitos (5 a 10).  Factura: FE-000000.
--   * Al pasar a 'Emitida' se asigna número consecutivo y fecha, que no puede ser anterior al pago.
--   * Un pago con factura emitida no cambia de valor, fecha ni matrícula, y no se anula sin anular antes la factura.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pago_factura
BEFORE INSERT OR UPDATE ON pago
FOR EACH ROW
BEGIN
  IF NOT REGEXP_LIKE(:NEW.numero_recibo, '^[0-9]{5,10}$') THEN
    RAISE_APPLICATION_ERROR(-20130, 'Número de recibo inválido (' || :NEW.numero_recibo || '): solo dígitos');
  END IF;

  IF :NEW.factura_estado = 'Emitida' THEN
    IF :NEW.factura_numero IS NULL THEN
      :NEW.factura_numero := pkg_util.fn_siguiente_factura;
    END IF;
    :NEW.factura_fecha := NVL(:NEW.factura_fecha, TRUNC(SYSDATE));
    IF :NEW.factura_fecha < :NEW.fecha_pago THEN
      RAISE_APPLICATION_ERROR(-20131, 'La factura (' || pkg_util.fn_fecha(:NEW.factura_fecha)
                                     || ') no puede ser anterior al pago (' || pkg_util.fn_fecha(:NEW.fecha_pago) || ')');
    END IF;
  END IF;

  IF :NEW.factura_numero IS NOT NULL AND NOT REGEXP_LIKE(:NEW.factura_numero, '^FE-[0-9]{6}$') THEN
    RAISE_APPLICATION_ERROR(-20132, 'Número de factura inválido (' || :NEW.factura_numero || '): formato FE-000000');
  END IF;

  IF UPDATING THEN
    IF :OLD.factura_estado = 'Emitida'
       AND (:NEW.valor <> :OLD.valor OR :NEW.matricula_id <> :OLD.matricula_id OR :NEW.fecha_pago <> :OLD.fecha_pago) THEN
      RAISE_APPLICATION_ERROR(-20133, 'El recibo ' || :OLD.numero_recibo || ' ya tiene factura emitida; no se puede modificar');
    END IF;
    IF :OLD.anulado = 0 AND :NEW.anulado = 1 AND :NEW.factura_estado = 'Emitida' THEN
      RAISE_APPLICATION_ERROR(-20134, 'Anule primero la factura ' || :NEW.factura_numero || ' antes de anular el recibo');
    END IF;
    IF :OLD.anulado = 1 AND :NEW.anulado = 0 THEN
      RAISE_APPLICATION_ERROR(-20135, 'Un recibo anulado no se puede reactivar');
    END IF;
  END IF;
END trg_pago_factura;
/

-- ---------------------------------------------------------------------
-- T6 DIPLOMA - RN-23, RN-24 y RN-25: requisitos para emitir el diploma
--   * 8 competencias del técnico aprobadas (ordinaria o supletorio >= 3.0)
--   * asistencia acumulada >= 80 % en las matrículas no retiradas de ese técnico
--   * ninguna matrícula de ese técnico en mora
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_diploma_requisitos
BEFORE INSERT ON diploma
FOR EACH ROW
DECLARE
  v_aprobadas NUMBER;
  v_sesiones  NUMBER;
  v_asistidas NUMBER;
  v_mora      NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_aprobadas
    FROM competencia c
   WHERE c.tecnico_id = :NEW.tecnico_id
     AND EXISTS (SELECT 1 FROM calificacion k JOIN matricula m ON m.id = k.matricula_id
                  WHERE m.estudiante_id = :NEW.estudiante_id
                    AND k.competencia_id = c.id
                    AND k.nota >= 3);
  IF v_aprobadas < 8 THEN
    RAISE_APPLICATION_ERROR(-20140, 'Tiene ' || v_aprobadas || ' de 8 competencias aprobadas (RN-24)');
  END IF;

  SELECT NVL(SUM(sesiones), 0), NVL(SUM(asistidas), 0) INTO v_sesiones, v_asistidas
    FROM v_asistencia_matricula
   WHERE estudiante_id = :NEW.estudiante_id AND tecnico_id = :NEW.tecnico_id
     AND estado_matricula <> 'Retirada';
  IF v_sesiones = 0 OR v_asistidas * 100 / v_sesiones < 80 THEN
    RAISE_APPLICATION_ERROR(-20141, 'Asistencia insuficiente: '
      || CASE WHEN v_sesiones = 0 THEN '0' ELSE TO_CHAR(ROUND(v_asistidas * 100 / v_sesiones, 1)) END
      || ' % (mínimo 80 %, RN-23)');
  END IF;

  SELECT COUNT(*) INTO v_mora
    FROM v_estado_credito ec JOIN grupo g ON g.id = ec.grupo_id
   WHERE ec.estudiante_id = :NEW.estudiante_id AND g.tecnico_id = :NEW.tecnico_id
     AND ec.estado = 'En mora';
  IF v_mora > 0 THEN
    RAISE_APPLICATION_ERROR(-20142, 'El estudiante está en mora; debe ponerse al día (RN-25)');
  END IF;

  :NEW.fecha_emision := NVL(:NEW.fecha_emision, TRUNC(SYSDATE));
END trg_diploma_requisitos;
/

-- ---------------------------------------------------------------------
-- T7 PAGO - auditoría de toda operación sobre los recibos de caja
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_auditoria_pago
AFTER INSERT OR UPDATE OR DELETE ON pago
FOR EACH ROW
DECLARE
  v_op      auditoria.operacion%TYPE;
  v_detalle auditoria.detalle%TYPE;
BEGIN
  IF INSERTING THEN
    v_op      := 'INSERT';
    v_detalle := 'Recibo ' || :NEW.numero_recibo || ' por ' || pkg_util.fn_moneda(:NEW.valor)
              || ' del ' || pkg_util.fn_fecha(:NEW.fecha_pago);
  ELSIF UPDATING THEN
    v_op      := 'UPDATE';
    v_detalle := 'Recibo ' || :NEW.numero_recibo
              || ' | factura: ' || :OLD.factura_estado || ' -> ' || :NEW.factura_estado
              || ' | anulado: ' || :OLD.anulado || ' -> ' || :NEW.anulado
              || ' | valor: ' || pkg_util.fn_moneda(:OLD.valor) || ' -> ' || pkg_util.fn_moneda(:NEW.valor);
  ELSE
    v_op      := 'DELETE';
    v_detalle := 'Recibo ' || :OLD.numero_recibo || ' por ' || pkg_util.fn_moneda(:OLD.valor);
  END IF;

  INSERT INTO auditoria (id, tabla, operacion, registro_id, detalle)
  VALUES (seq_auditoria.NEXTVAL, 'PAGO', v_op, NVL(:NEW.id, :OLD.id), v_detalle);
END trg_auditoria_pago;
/

-- =====================================================================
-- 5. (b) PAQUETES CRUD   (códigos de error -20200 a -20299)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 PKG_ESTUDIANTE: insertar, actualizar, consultar, buscar, eliminar
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_estudiante AS
  PROCEDURE insertar (
    p_cedula        IN  VARCHAR2,
    p_nombres       IN  VARCHAR2,
    p_apellidos     IN  VARCHAR2,
    p_fecha_nac     IN  DATE,
    p_telefono      IN  VARCHAR2,
    p_email         IN  VARCHAR2,
    p_direccion     IN  VARCHAR2,
    p_ocupacion     IN  VARCHAR2,
    p_regimen_salud IN  VARCHAR2,
    p_estrato       IN  NUMBER,
    p_estado_civil  IN  VARCHAR2,
    p_id            OUT NUMBER,
    p_nivel         IN  VARCHAR2 DEFAULT 'Bachiller',
    p_autoriza      IN  NUMBER   DEFAULT 0,
    p_tipo_doc      IN  VARCHAR2 DEFAULT 'CC',
    p_condicion     IN  VARCHAR2 DEFAULT NULL);

  PROCEDURE actualizar_contacto (p_id NUMBER, p_telefono VARCHAR2, p_email VARCHAR2, p_direccion VARCHAR2);
  PROCEDURE actualizar_autorizacion (p_id NUMBER, p_autoriza NUMBER);
  PROCEDURE registrar_documento (p_estudiante NUMBER, p_tipo VARCHAR2, p_url VARCHAR2 DEFAULT NULL);

  FUNCTION  consultar (p_cedula VARCHAR2) RETURN estudiante%ROWTYPE;
  FUNCTION  buscar (p_apellido VARCHAR2) RETURN SYS_REFCURSOR;
  PROCEDURE imprimir_ficha (p_cedula VARCHAR2);

  PROCEDURE eliminar (p_id NUMBER);
END pkg_estudiante;
/

CREATE OR REPLACE PACKAGE BODY pkg_estudiante AS
  e_check     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_check, -2290);   -- violación de CHECK
  e_hijos     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_hijos, -2292);   -- tiene registros hijos
  e_no_existe EXCEPTION;

  PROCEDURE insertar (
    p_cedula IN VARCHAR2, p_nombres IN VARCHAR2, p_apellidos IN VARCHAR2, p_fecha_nac IN DATE,
    p_telefono IN VARCHAR2, p_email IN VARCHAR2, p_direccion IN VARCHAR2, p_ocupacion IN VARCHAR2,
    p_regimen_salud IN VARCHAR2, p_estrato IN NUMBER, p_estado_civil IN VARCHAR2, p_id OUT NUMBER,
    p_nivel IN VARCHAR2 DEFAULT 'Bachiller', p_autoriza IN NUMBER DEFAULT 0,
    p_tipo_doc IN VARCHAR2 DEFAULT 'CC', p_condicion IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    SELECT seq_estudiante.NEXTVAL INTO p_id FROM dual;
    INSERT INTO estudiante (id, tipo_documento, cedula, nombres, apellidos, fecha_nacimiento, telefono, email,
                            direccion, ocupacion, regimen_salud, condicion_medica, estrato, estado_civil,
                            nivel_formacion, autoriza_centrales)
    VALUES (p_id, p_tipo_doc, p_cedula, p_nombres, p_apellidos, p_fecha_nac, p_telefono, p_email,
            p_direccion, p_ocupacion, p_regimen_salud, p_condicion, p_estrato, p_estado_civil,
            p_nivel, p_autoriza);
    pkg_util.pl('Estudiante ' || p_cedula || ' registrado con id ' || p_id);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20201, 'Ya existe un estudiante con la cédula ' || p_cedula);
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20202, 'Dato fuera del dominio del formulario: ' || SQLERRM);
  END insertar;

  PROCEDURE actualizar_contacto (p_id NUMBER, p_telefono VARCHAR2, p_email VARCHAR2, p_direccion VARCHAR2) IS
  BEGIN
    UPDATE estudiante
       SET telefono  = NVL(p_telefono, telefono),
           email     = NVL(p_email, email),
           direccion = NVL(p_direccion, direccion)
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20203, 'No existe el estudiante con id ' || p_id);
  END actualizar_contacto;

  PROCEDURE actualizar_autorizacion (p_id NUMBER, p_autoriza NUMBER) IS
  BEGIN
    UPDATE estudiante SET autoriza_centrales = p_autoriza, fecha_autorizacion = NULL WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20203, 'No existe el estudiante con id ' || p_id);
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20202, 'La autorización debe ser 0 o 1');
  END actualizar_autorizacion;

  PROCEDURE registrar_documento (p_estudiante NUMBER, p_tipo VARCHAR2, p_url VARCHAR2 DEFAULT NULL) IS
  BEGIN
    INSERT INTO documento_estudiante (id, estudiante_id, tipo, fecha_entrega, archivo_url)
    VALUES (seq_documento.NEXTVAL, p_estudiante, p_tipo, TRUNC(SYSDATE), p_url);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20205, 'El estudiante ya entregó el documento: ' || p_tipo);
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20206, 'Tipo de documento no válido: ' || p_tipo);
  END registrar_documento;

  FUNCTION consultar (p_cedula VARCHAR2) RETURN estudiante%ROWTYPE IS
    v_est estudiante%ROWTYPE;                                -- tipo compuesto %ROWTYPE
  BEGIN
    SELECT * INTO v_est FROM estudiante WHERE cedula = TRIM(p_cedula);
    RETURN v_est;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20204, 'No existe un estudiante con la cédula ' || p_cedula);
  END consultar;

  -- Búsqueda sin distinguir mayúsculas (usa el índice IX_EST_APELLIDO_UPPER)
  FUNCTION buscar (p_apellido VARCHAR2) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT id, cedula, apellidos, nombres, telefono, email
        FROM estudiante
       WHERE UPPER(apellidos) LIKE UPPER(TRIM(p_apellido)) || '%'
       ORDER BY apellidos, nombres;
    RETURN v_cur;
  END buscar;

  PROCEDURE imprimir_ficha (p_cedula VARCHAR2) IS
    v_est estudiante%ROWTYPE;
    CURSOR c_matriculas (p_estudiante NUMBER) IS             -- cursor con parámetro
      SELECT m.id, g.codigo, p.codigo AS periodo, m.estado
        FROM matricula m JOIN grupo g ON g.id = m.grupo_id JOIN periodo p ON p.id = g.periodo_id
       WHERE m.estudiante_id = p_estudiante
       ORDER BY p.fecha_inicio;
  BEGIN
    v_est := consultar(p_cedula);
    pkg_util.pl('FICHA DEL ESTUDIANTE');
    pkg_util.pl('  ' || v_est.tipo_documento || ' ' || v_est.cedula || ' - ' || v_est.apellidos || ' ' || v_est.nombres);
    pkg_util.pl('  Nacimiento: ' || pkg_util.fn_fecha(v_est.fecha_nacimiento) || '  Tel: ' || v_est.telefono || '  ' || v_est.email);
    pkg_util.pl('  Estado de crédito: ' || pkg_util.fn_estado_credito(v_est.id));
    FOR m IN c_matriculas(v_est.id) LOOP
      pkg_util.pl('  - ' || RPAD(m.codigo, 14) || RPAD(m.estado, 11)
               || ' saldo ' || LPAD(pkg_util.fn_moneda(pkg_util.fn_saldo(m.id)), 9)
               || '  asistencia ' || NVL(TO_CHAR(pkg_util.fn_pct_asistencia(m.id)), 's/d') || ' %');
    END LOOP;
  END imprimir_ficha;

  PROCEDURE eliminar (p_id NUMBER) IS
  BEGIN
    DELETE FROM estudiante WHERE id = p_id;      -- sus documentos se borran en cascada
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
    pkg_util.pl('Estudiante ' || p_id || ' eliminado');
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20203, 'No existe el estudiante con id ' || p_id);
    WHEN e_hijos THEN
      RAISE_APPLICATION_ERROR(-20207, 'El estudiante ' || p_id || ' tiene matrículas o diplomas; no se puede eliminar');
  END eliminar;
END pkg_estudiante;
/

-- ---------------------------------------------------------------------
-- 5.2 PKG_DOCENTE: insertar, actualizar, consultar (con RECORD + TABLE + BULK COLLECT), eliminar
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_docente AS
  TYPE t_contrato IS RECORD (                                -- (f) RECORD
    periodo     VARCHAR2(7),             -- mismo tipo de periodo.codigo (con %TYPE el campo "periodo" oculta a la tabla: PLS-00320)
    horas       contrato_docente.horas_catedra%TYPE,
    valor_hora  contrato_docente.valor_hora%TYPE,
    total       NUMBER);
  TYPE t_tab_contratos IS TABLE OF t_contrato INDEX BY PLS_INTEGER;   -- (f) TABLE (asociativa)

  PROCEDURE insertar (p_cedula VARCHAR2, p_nombres VARCHAR2, p_apellidos VARCHAR2, p_email VARCHAR2,
                      p_telefono VARCHAR2, p_nivel VARCHAR2, p_exp NUMBER, p_hoja_vida VARCHAR2,
                      p_id OUT NUMBER);
  PROCEDURE actualizar (p_id NUMBER, p_email VARCHAR2, p_telefono VARCHAR2, p_nivel VARCHAR2, p_exp NUMBER);
  PROCEDURE agregar_formacion (p_docente NUMBER, p_nivel VARCHAR2, p_titulo VARCHAR2,
                               p_institucion VARCHAR2, p_anio NUMBER, p_soporte VARCHAR2);
  PROCEDURE registrar_contrato (p_docente NUMBER, p_periodo NUMBER, p_horas NUMBER, p_valor_hora NUMBER);
  FUNCTION  contratos (p_docente NUMBER) RETURN t_tab_contratos;
  PROCEDURE consultar (p_id NUMBER);
  PROCEDURE eliminar (p_id NUMBER);
END pkg_docente;
/

CREATE OR REPLACE PACKAGE BODY pkg_docente AS
  e_check     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_check, -2290);
  e_hijos     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_hijos, -2292);
  e_padre     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_padre, -2291);   -- llave foránea inexistente
  e_no_existe EXCEPTION;

  PROCEDURE insertar (p_cedula VARCHAR2, p_nombres VARCHAR2, p_apellidos VARCHAR2, p_email VARCHAR2,
                      p_telefono VARCHAR2, p_nivel VARCHAR2, p_exp NUMBER, p_hoja_vida VARCHAR2,
                      p_id OUT NUMBER) IS
  BEGIN
    SELECT seq_docente.NEXTVAL INTO p_id FROM dual;
    INSERT INTO docente (id, cedula, nombres, apellidos, email, telefono, nivel_formacion,
                         anios_experiencia_docencia, hoja_vida_url, activo)
    VALUES (p_id, TRIM(p_cedula), INITCAP(TRIM(p_nombres)), INITCAP(TRIM(p_apellidos)), LOWER(TRIM(p_email)),
            p_telefono, p_nivel, p_exp, p_hoja_vida, 1);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20210, 'Ya existe un docente con esa cédula o correo');
    WHEN e_check THEN      -- RN-11: mínimo pregrado y 1 año de experiencia docente
      RAISE_APPLICATION_ERROR(-20211, 'El docente no cumple el perfil (mínimo pregrado y experiencia docente)');
  END insertar;

  PROCEDURE actualizar (p_id NUMBER, p_email VARCHAR2, p_telefono VARCHAR2, p_nivel VARCHAR2, p_exp NUMBER) IS
  BEGIN
    UPDATE docente
       SET email = NVL(LOWER(p_email), email), telefono = NVL(p_telefono, telefono),
           nivel_formacion = NVL(p_nivel, nivel_formacion),
           anios_experiencia_docencia = NVL(p_exp, anios_experiencia_docencia)
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20212, 'No existe el docente ' || p_id);
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20211, 'El docente no cumple el perfil (mínimo pregrado y experiencia docente)');
  END actualizar;

  PROCEDURE agregar_formacion (p_docente NUMBER, p_nivel VARCHAR2, p_titulo VARCHAR2,
                               p_institucion VARCHAR2, p_anio NUMBER, p_soporte VARCHAR2) IS
  BEGIN
    IF p_anio > EXTRACT(YEAR FROM SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20215, 'El año de grado no puede ser futuro');
    END IF;
    INSERT INTO docente_formacion (id, docente_id, nivel, titulo, institucion, anio_grado, soporte_url)
    VALUES (seq_docente_formacion.NEXTVAL, p_docente, p_nivel, p_titulo, p_institucion, p_anio, p_soporte);
  EXCEPTION
    WHEN e_padre THEN
      RAISE_APPLICATION_ERROR(-20212, 'No existe el docente ' || p_docente);
  END agregar_formacion;

  PROCEDURE registrar_contrato (p_docente NUMBER, p_periodo NUMBER, p_horas NUMBER, p_valor_hora NUMBER) IS
  BEGIN
    INSERT INTO contrato_docente (id, docente_id, periodo_id, tipo, horas_catedra, valor_hora)
    VALUES (seq_contrato_docente.NEXTVAL, p_docente, p_periodo, 'Prestación de servicios', p_horas, p_valor_hora);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20214, 'El docente ya tiene contrato en ese periodo');
    WHEN e_padre THEN
      RAISE_APPLICATION_ERROR(-20212, 'Docente o periodo inexistente');
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20216, 'Horas y valor por hora deben ser mayores que cero');
  END registrar_contrato;

  -- (f) BULK COLLECT: carga todos los contratos del docente de una sola vez
  FUNCTION contratos (p_docente NUMBER) RETURN t_tab_contratos IS
    v_tab t_tab_contratos;
  BEGIN
    SELECT p.codigo, c.horas_catedra, c.valor_hora, c.horas_catedra * c.valor_hora
      BULK COLLECT INTO v_tab
      FROM contrato_docente c JOIN periodo p ON p.id = c.periodo_id
     WHERE c.docente_id = p_docente
     ORDER BY p.fecha_inicio;
    RETURN v_tab;
  END contratos;

  PROCEDURE consultar (p_id NUMBER) IS
    v_doc    docente%ROWTYPE;
    v_tab    t_tab_contratos;
    v_total  NUMBER := 0;
  BEGIN
    SELECT * INTO v_doc FROM docente WHERE id = p_id;
    pkg_util.pl('DOCENTE: ' || v_doc.apellidos || ' ' || v_doc.nombres || ' (CC ' || v_doc.cedula || ')');
    pkg_util.pl('  ' || v_doc.nivel_formacion || ', ' || v_doc.anios_experiencia_docencia || ' años de experiencia - '
                || CASE v_doc.activo WHEN 1 THEN 'Activo' ELSE 'Inactivo' END);
    pkg_util.pl('  Soportes de formación:');
    FOR f IN (SELECT nivel, titulo, institucion, anio_grado FROM docente_formacion
               WHERE docente_id = p_id ORDER BY anio_grado) LOOP
      pkg_util.pl('    ' || f.anio_grado || ' ' || f.nivel || ': ' || f.titulo || ' - ' || f.institucion);
    END LOOP;

    v_tab := contratos(p_id);
    pkg_util.pl('  Contratos (' || v_tab.COUNT || '):');
    FOR i IN 1 .. v_tab.COUNT LOOP
      pkg_util.pl('    ' || v_tab(i).periodo || '  ' || LPAD(v_tab(i).horas, 4) || ' h x '
                  || LPAD(pkg_util.fn_moneda(v_tab(i).valor_hora), 8) || ' = ' || pkg_util.fn_moneda(v_tab(i).total));
      v_total := v_total + v_tab(i).total;
    END LOOP;
    pkg_util.pl('  Total contratado: ' || pkg_util.fn_moneda(v_total));
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20212, 'No existe el docente ' || p_id);
  END consultar;

  -- Si el docente ya dictó grupos no se borra: se inactiva (se conserva la historia)
  PROCEDURE eliminar (p_id NUMBER) IS
  BEGIN
    DELETE FROM docente WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
    pkg_util.pl('Docente ' || p_id || ' eliminado');
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20212, 'No existe el docente ' || p_id);
    WHEN e_hijos THEN
      UPDATE docente SET activo = 0 WHERE id = p_id;
      pkg_util.pl('El docente ' || p_id || ' tiene grupos o contratos: se marcó como inactivo');
  END eliminar;
END pkg_docente;
/

-- ---------------------------------------------------------------------
-- 5.3 PKG_GRUPO: crear (grupo + horario), cambiar estado, consultar, eliminar
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_grupo AS
  TYPE t_dias IS VARRAY(2) OF NUMBER(1);                     -- colección de tamaño fijo: 2 días

  PROCEDURE crear (p_tecnico NUMBER, p_periodo NUMBER, p_semestre NUMBER, p_docente NUMBER,
                   p_aula NUMBER, p_dia1 NUMBER, p_dia2 NUMBER, p_id OUT NUMBER);
  PROCEDURE cambiar_estado (p_id NUMBER, p_estado VARCHAR2);
  PROCEDURE consultar (p_id NUMBER);
  PROCEDURE eliminar (p_id NUMBER);
END pkg_grupo;
/

CREATE OR REPLACE PACKAGE BODY pkg_grupo AS
  e_hijos EXCEPTION;  PRAGMA EXCEPTION_INIT(e_hijos, -2292);

  PROCEDURE crear (p_tecnico NUMBER, p_periodo NUMBER, p_semestre NUMBER, p_docente NUMBER,
                   p_aula NUMBER, p_dia1 NUMBER, p_dia2 NUMBER, p_id OUT NUMBER) IS
    v_dias    t_dias := t_dias(p_dia1, p_dia2);
    v_tec     tecnico.codigo%TYPE;
    v_per     periodo.codigo%TYPE;
    v_n       NUMBER;
    e_aula_ocupada    EXCEPTION;
    e_docente_ocupado EXCEPTION;
  BEGIN
    IF p_dia1 = p_dia2 THEN
      RAISE_APPLICATION_ERROR(-20220, 'Los dos días de clase deben ser distintos');
    END IF;

    SELECT codigo INTO v_tec FROM tecnico WHERE id = p_tecnico;
    SELECT codigo INTO v_per FROM periodo WHERE id = p_periodo;

    -- RN-12: el docente debe tener contrato por hora cátedra en el periodo
    SELECT COUNT(*) INTO v_n FROM contrato_docente WHERE docente_id = p_docente AND periodo_id = p_periodo;
    IF v_n = 0 THEN
      RAISE_APPLICATION_ERROR(-20222, 'El docente ' || p_docente || ' no tiene contrato en el periodo ' || v_per);
    END IF;

    -- RN-08: aula libre esos días; el docente tampoco puede dictar otro grupo esos días (única jornada)
    SELECT COUNT(*) INTO v_n
      FROM horario_grupo h JOIN grupo g ON g.id = h.grupo_id
     WHERE g.aula_id = p_aula AND g.periodo_id = p_periodo AND g.estado <> 'Cancelado'
       AND h.dia_semana IN (p_dia1, p_dia2);
    IF v_n > 0 THEN
      RAISE e_aula_ocupada;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM horario_grupo h JOIN grupo g ON g.id = h.grupo_id
     WHERE g.docente_id = p_docente AND g.periodo_id = p_periodo AND g.estado <> 'Cancelado'
       AND h.dia_semana IN (p_dia1, p_dia2);
    IF v_n > 0 THEN
      RAISE e_docente_ocupado;
    END IF;

    SELECT seq_grupo.NEXTVAL INTO p_id FROM dual;
    INSERT INTO grupo (id, codigo, tecnico_id, periodo_id, semestre, docente_id, aula_id, estado)
    VALUES (p_id, v_tec || '-' || REPLACE(v_per, '-') || '-S' || p_semestre,
            p_tecnico, p_periodo, p_semestre, p_docente, p_aula, 'En formación');

    FOR i IN 1 .. v_dias.COUNT LOOP
      INSERT INTO horario_grupo (id, grupo_id, dia_semana)
      VALUES (seq_horario_grupo.NEXTVAL, p_id, v_dias(i));
    END LOOP;

    pkg_util.pl('Grupo ' || v_tec || '-' || REPLACE(v_per, '-') || '-S' || p_semestre || ' creado (id ' || p_id || '): '
                || pkg_util.fn_dia(p_dia1) || ' y ' || pkg_util.fn_dia(p_dia2) || ', 6:30 p. m. - 9:00 p. m.');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20221, 'Técnico o periodo inexistente');
    WHEN e_aula_ocupada THEN
      RAISE_APPLICATION_ERROR(-20223, 'El aula ' || p_aula || ' ya está ocupada uno de esos días en el periodo');
    WHEN e_docente_ocupado THEN
      RAISE_APPLICATION_ERROR(-20224, 'El docente ya dicta otro grupo uno de esos días');
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20225, 'Ya existe un grupo de ese técnico, periodo y semestre (RN-06)');
  END crear;

  -- Transiciones: En formación -> Activo -> Cerrado ; En formación/Activo -> Cancelado
  PROCEDURE cambiar_estado (p_id NUMBER, p_estado VARCHAR2) IS
    v_grupo   grupo%ROWTYPE;
    v_activas NUMBER;
  BEGIN
    SELECT * INTO v_grupo FROM grupo WHERE id = p_id;
    SELECT COUNT(*) INTO v_activas FROM matricula WHERE grupo_id = p_id AND estado = 'Activa';

    CASE p_estado
      WHEN 'Activo' THEN
        IF v_grupo.estado <> 'En formación' THEN
          RAISE_APPLICATION_ERROR(-20226, 'Solo se activa un grupo en formación');
        ELSIF v_activas < v_grupo.cupo_min THEN
          RAISE_APPLICATION_ERROR(-20227, 'El grupo tiene ' || v_activas || ' matriculados; el mínimo es ' || v_grupo.cupo_min || ' (RN-09)');
        END IF;
      WHEN 'Cerrado' THEN
        IF v_grupo.estado <> 'Activo' THEN
          RAISE_APPLICATION_ERROR(-20226, 'Solo se cierra un grupo activo');
        END IF;
        UPDATE matricula SET estado = 'Finalizada' WHERE grupo_id = p_id AND estado = 'Activa';
        pkg_util.pl(SQL%ROWCOUNT || ' matrículas pasaron a Finalizada');
      WHEN 'Cancelado' THEN
        IF v_activas > 0 THEN
          RAISE_APPLICATION_ERROR(-20228, 'No se cancela un grupo con ' || v_activas || ' matrículas activas');
        END IF;
      ELSE
        RAISE_APPLICATION_ERROR(-20229, 'Estado no válido: ' || p_estado);
    END CASE;

    UPDATE grupo SET estado = p_estado WHERE id = p_id;
    pkg_util.pl('Grupo ' || v_grupo.codigo || ': ' || v_grupo.estado || ' -> ' || p_estado);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20221, 'No existe el grupo ' || p_id);
  END cambiar_estado;

  PROCEDURE consultar (p_id NUMBER) IS
    CURSOR c_grupo IS
      SELECT g.codigo, g.estado, g.semestre, g.cupo_min, g.cupo_max, t.nombre AS tecnico,
             d.apellidos || ' ' || d.nombres AS docente, a.nombre AS aula,
             (SELECT COUNT(*) FROM matricula m WHERE m.grupo_id = g.id AND m.estado <> 'Retirada') AS inscritos
        FROM grupo g JOIN tecnico t ON t.id = g.tecnico_id
        JOIN docente d ON d.id = g.docente_id JOIN aula a ON a.id = g.aula_id
       WHERE g.id = p_id;
    CURSOR c_horario (p_grupo NUMBER) IS
      SELECT dia_semana, hora_inicio, hora_fin FROM horario_grupo WHERE grupo_id = p_grupo ORDER BY dia_semana;
    r c_grupo%ROWTYPE;
  BEGIN
    OPEN c_grupo;
    FETCH c_grupo INTO r;
    IF c_grupo%NOTFOUND THEN
      CLOSE c_grupo;
      RAISE_APPLICATION_ERROR(-20221, 'No existe el grupo ' || p_id);
    END IF;
    CLOSE c_grupo;

    pkg_util.pl(r.codigo || ' - ' || r.tecnico || ' (semestre ' || r.semestre || ') - ' || r.estado);
    pkg_util.pl('  Docente: ' || r.docente || '   ' || r.aula);
    pkg_util.pl('  Cupo: ' || r.inscritos || ' / ' || r.cupo_max || ' (mínimo ' || r.cupo_min || ')');
    FOR h IN c_horario(p_id) LOOP
      pkg_util.pl('  ' || RPAD(pkg_util.fn_dia(h.dia_semana), 10) || h.hora_inicio || ' - ' || h.hora_fin);
    END LOOP;
  END consultar;

  PROCEDURE eliminar (p_id NUMBER) IS
    v_estado grupo.estado%TYPE;
  BEGIN
    SELECT estado INTO v_estado FROM grupo WHERE id = p_id;
    IF v_estado <> 'En formación' THEN
      RAISE_APPLICATION_ERROR(-20230, 'Solo se elimina un grupo en formación; use cambiar_estado(''Cancelado'')');
    END IF;
    DELETE FROM grupo WHERE id = p_id;           -- el horario se borra en cascada
    pkg_util.pl('Grupo ' || p_id || ' eliminado');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20221, 'No existe el grupo ' || p_id);
    WHEN e_hijos THEN
      RAISE_APPLICATION_ERROR(-20231, 'El grupo tiene matrículas o sesiones; no se puede eliminar');
  END eliminar;
END pkg_grupo;
/

-- ---------------------------------------------------------------------
-- 5.4 PKG_CALIFICACION: registrar, actualizar, consultar (nota definitiva y boletín), eliminar
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_calificacion AS
  PROCEDURE registrar (p_matricula NUMBER, p_competencia NUMBER, p_nota NUMBER, p_id OUT NUMBER,
                       p_tipo VARCHAR2 DEFAULT 'Ordinaria', p_usuario NUMBER DEFAULT NULL,
                       p_fecha DATE DEFAULT TRUNC(SYSDATE));
  PROCEDURE actualizar (p_id NUMBER, p_nota NUMBER);
  FUNCTION  nota_definitiva (p_matricula NUMBER, p_competencia NUMBER) RETURN NUMBER;
  PROCEDURE boletin (p_matricula NUMBER);
  PROCEDURE eliminar (p_id NUMBER);
END pkg_calificacion;
/

CREATE OR REPLACE PACKAGE BODY pkg_calificacion AS
  e_check         EXCEPTION;  PRAGMA EXCEPTION_INIT(e_check, -2290);
  e_nota_invalida EXCEPTION;
  e_prerrequisito EXCEPTION;
  e_no_existe     EXCEPTION;

  PROCEDURE registrar (p_matricula NUMBER, p_competencia NUMBER, p_nota NUMBER, p_id OUT NUMBER,
                       p_tipo VARCHAR2 DEFAULT 'Ordinaria', p_usuario NUMBER DEFAULT NULL,
                       p_fecha DATE DEFAULT TRUNC(SYSDATE)) IS
    v_orden   competencia.orden%TYPE;
    v_tecnico competencia.tecnico_id%TYPE;
    v_estud   matricula.estudiante_id%TYPE;
    v_n       NUMBER;
  BEGIN
    IF p_nota IS NULL OR p_nota < 1 OR p_nota > 5 THEN
      RAISE e_nota_invalida;
    END IF;

    SELECT orden, tecnico_id INTO v_orden, v_tecnico FROM competencia WHERE id = p_competencia;
    SELECT estudiante_id INTO v_estud FROM matricula WHERE id = p_matricula;

    -- RN-04: dentro del semestre, para calificar la competencia n se debe haber aprobado la n-1
    -- (las competencias 1 y 5 abren semestre; la 5 ya la controla sp_matricular)
    IF p_tipo = 'Ordinaria' AND MOD(v_orden - 1, 4) <> 0 THEN
      SELECT COUNT(*) INTO v_n
        FROM calificacion k JOIN matricula m ON m.id = k.matricula_id
        JOIN competencia c ON c.id = k.competencia_id
       WHERE m.estudiante_id = v_estud AND c.tecnico_id = v_tecnico
         AND c.orden = v_orden - 1 AND k.nota >= pkg_util.c_nota_aprueba;
      IF v_n = 0 THEN
        RAISE e_prerrequisito;
      END IF;
    END IF;

    SELECT seq_calificacion.NEXTVAL INTO p_id FROM dual;
    INSERT INTO calificacion (id, matricula_id, competencia_id, tipo, nota, fecha, registrado_por)
    VALUES (p_id, p_matricula, p_competencia, p_tipo, p_nota, p_fecha, p_usuario);

    pkg_util.pl('Nota ' || p_tipo || ' ' || pkg_util.fn_nota(p_nota) || ' registrada (competencia ' || v_orden || ') - '
                || CASE WHEN p_nota >= pkg_util.c_nota_aprueba THEN 'APROBADA'
                        WHEN p_tipo = 'Ordinaria' THEN 'PERDIDA: tiene derecho a supletorio'
                        ELSE 'PERDIDA: debe repetir la competencia' END);
  EXCEPTION
    WHEN e_nota_invalida THEN
      RAISE_APPLICATION_ERROR(-20240, 'La nota debe estar entre 1.0 y 5.0 (RN-20)');
    WHEN e_prerrequisito THEN
      RAISE_APPLICATION_ERROR(-20241, 'No ha aprobado la competencia ' || (v_orden - 1) || ', prerrequisito de la ' || v_orden || ' (RN-04)');
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20242, 'Matrícula o competencia inexistente');
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20243, 'Ya existe una nota ' || p_tipo || ' para esa competencia; use actualizar (RN-21/RN-22)');
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20244, 'Tipo de nota no válido: ' || p_tipo);
  END registrar;

  PROCEDURE actualizar (p_id NUMBER, p_nota NUMBER) IS
  BEGIN
    UPDATE calificacion SET nota = p_nota, fecha = TRUNC(SYSDATE) WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20245, 'No existe la calificación ' || p_id);
    WHEN e_check THEN
      RAISE_APPLICATION_ERROR(-20240, 'La nota debe estar entre 1.0 y 5.0 (RN-20)');
  END actualizar;

  -- El supletorio reemplaza a la ordinaria; NULL si no hay notas
  FUNCTION nota_definitiva (p_matricula NUMBER, p_competencia NUMBER) RETURN NUMBER IS
    v_ord NUMBER;
    v_sup NUMBER;
  BEGIN
    SELECT MAX(CASE tipo WHEN 'Ordinaria'  THEN nota END),
           MAX(CASE tipo WHEN 'Supletorio' THEN nota END)
      INTO v_ord, v_sup
      FROM calificacion WHERE matricula_id = p_matricula AND competencia_id = p_competencia;
    RETURN NVL(v_sup, v_ord);
  END nota_definitiva;

  -- Boletín de una matrícula; si está en mora las notas se retienen (RN-25)
  PROCEDURE boletin (p_matricula NUMBER) IS
    v_codigo grupo.codigo%TYPE;
    v_tec    grupo.tecnico_id%TYPE;
    v_sem    grupo.semestre%TYPE;
    v_mora   BOOLEAN;
    v_estado v_estado_credito.estado%TYPE;
    v_nota   NUMBER;
  BEGIN
    SELECT g.codigo, g.tecnico_id, g.semestre INTO v_codigo, v_tec, v_sem
      FROM matricula m JOIN grupo g ON g.id = m.grupo_id WHERE m.id = p_matricula;
    BEGIN
      SELECT estado INTO v_estado FROM v_estado_credito WHERE matricula_id = p_matricula;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN v_estado := 'Sin plan de pagos';
    END;
    v_mora := (v_estado = 'En mora');

    pkg_util.pl('BOLETÍN - matrícula ' || p_matricula || ' (' || v_codigo || ') - crédito: ' || v_estado);
    FOR c IN (SELECT id, orden, nombre FROM competencia
               WHERE tecnico_id = v_tec AND semestre = v_sem ORDER BY orden) LOOP
      v_nota := nota_definitiva(p_matricula, c.id);
      pkg_util.pl('  ' || c.orden || '. ' || RPAD(SUBSTR(c.nombre, 1, 45), 46)
        || CASE WHEN v_mora THEN 'RETENIDA (en mora)'
                WHEN v_nota IS NULL THEN 'Sin nota'
                ELSE pkg_util.fn_nota(v_nota) || CASE WHEN v_nota >= 3 THEN '  Aprobada' ELSE '  Perdida' END
           END);
    END LOOP;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20246, 'No existe la matrícula ' || p_matricula);
  END boletin;

  PROCEDURE eliminar (p_id NUMBER) IS
  BEGIN
    DELETE FROM calificacion WHERE id = p_id;    -- TRG_CALIFICACION_SUPLETORIO impide dejar supletorios huérfanos
    IF SQL%ROWCOUNT = 0 THEN
      RAISE e_no_existe;
    END IF;
  EXCEPTION
    WHEN e_no_existe THEN
      RAISE_APPLICATION_ERROR(-20245, 'No existe la calificación ' || p_id);
  END eliminar;
END pkg_calificacion;
/

-- ---------------------------------------------------------------------
-- 5.5 PKG_CERTIFICACION: emisión del diploma (los requisitos los valida TRG_DIPLOMA_REQUISITOS)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_certificacion AS
  PROCEDURE emitir_diploma (p_estudiante NUMBER, p_tecnico NUMBER, p_usuario NUMBER, p_numero OUT VARCHAR2);
END pkg_certificacion;
/

CREATE OR REPLACE PACKAGE BODY pkg_certificacion AS
  PROCEDURE emitir_diploma (p_estudiante NUMBER, p_tecnico NUMBER, p_usuario NUMBER, p_numero OUT VARCHAR2) IS
    v_cod tecnico.codigo%TYPE;
    v_n   NUMBER;
  BEGIN
    SELECT codigo INTO v_cod FROM tecnico WHERE id = p_tecnico;
    SELECT COUNT(*) + 1 INTO v_n FROM diploma WHERE tecnico_id = p_tecnico;
    p_numero := 'DIP-' || v_cod || '-' || LPAD(v_n, 4, '0');

    INSERT INTO diploma (id, estudiante_id, tecnico_id, numero_diploma, fecha_emision, registrado_por)
    VALUES (seq_diploma.NEXTVAL, p_estudiante, p_tecnico, p_numero, TRUNC(SYSDATE), p_usuario);
    pkg_util.pl('Diploma ' || p_numero || ' emitido el ' || pkg_util.fn_fecha_larga(TRUNC(SYSDATE)));
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20250, 'Técnico inexistente');
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20251, 'El estudiante ya tiene diploma de este técnico (o el número ya existe)');
  END emitir_diploma;
END pkg_certificacion;
/

-- =====================================================================
-- 6. PERMISOS SOBRE LOS OBJETOS NUEVOS
-- =====================================================================
GRANT SELECT ON v_asistencia_matricula TO rol_coordinador;
GRANT SELECT ON v_asistencia_matricula TO rol_secretaria;
GRANT SELECT ON auditoria              TO rol_coordinador;
GRANT EXECUTE ON pkg_util          TO rol_coordinador;
GRANT EXECUTE ON pkg_estudiante    TO rol_coordinador;
GRANT EXECUTE ON pkg_docente       TO rol_coordinador;
GRANT EXECUTE ON pkg_grupo         TO rol_coordinador;
GRANT EXECUTE ON pkg_calificacion  TO rol_coordinador;
GRANT EXECUTE ON pkg_certificacion TO rol_coordinador;
-- La secretaria no administra docentes, grupos ni diplomas (Tabla 4)
GRANT EXECUTE ON pkg_util          TO rol_secretaria;
GRANT EXECUTE ON pkg_estudiante    TO rol_secretaria;
GRANT EXECUTE ON pkg_calificacion  TO rol_secretaria;

-- Verificación: todos los objetos deben quedar VALID
SELECT object_type, object_name, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW')
 ORDER BY object_type, object_name;
