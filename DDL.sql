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
--   (una sola vez, como SYSTEM)  USUARIOS.sql      crea el usuario ITECCI y los roles
--   (como ITECCI)                DDL.sql           este archivo
--   (como ITECCI)                DATOS.sql         datos de prueba
--
-- Compatible con Oracle 12.2 o superior (la paginación de los paquetes PKG_API_* usa OFFSET/FETCH).
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- #####################################################################
-- 1. LIMPIEZA (borra los objetos del proyecto si ya existen)
-- #####################################################################
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('TECNICO','COMPETENCIA','PERIODO','AULA','USUARIO','DOCENTE','DOCENTE_FORMACION',
                                  'CONTRATO_DOCENTE','GRUPO','HORARIO_GRUPO','ESTUDIANTE','DOCUMENTO_ESTUDIANTE',
                                  'MATRICULA','MEDIO_PAGO','CUOTA','PAGO','APLICACION_PAGO','SESION_CLASE',
                                  'ASISTENCIA','CALIFICACION','DIPLOMA','AUDITORIA')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';   -- PURGE: no deja copias en la papelera (BIN$...)
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar tabla ' || t.table_name || ': ' || SQLERRM);
    END;
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ\_%' ESCAPE '\') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP SEQUENCE "' || s.sequence_name || '"';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar secuencia ' || s.sequence_name || ': ' || SQLERRM);
    END;
  END LOOP;
  FOR v IN (SELECT view_name FROM user_views WHERE view_name IN ('V_ESTADO_CREDITO','V_BOLETIN','V_ASISTENCIA_MATRICULA')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP VIEW "' || v.view_name || '"';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar vista ' || v.view_name || ': ' || SQLERRM);
    END;
  END LOOP;
  FOR p IN (SELECT object_name, object_type FROM user_objects
             WHERE (object_type = 'PROCEDURE' AND object_name IN ('SP_GENERAR_PLAN_PAGOS','SP_MATRICULAR','SP_REGISTRAR_PAGO'))
                OR (object_type = 'PACKAGE' AND object_name LIKE 'PKG\_%' ESCAPE '\')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ' || p.object_type || ' "' || p.object_name || '"';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar procedimiento ' || p.object_name || ': ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Limpieza terminada.');
END;
/

-- #####################################################################
-- 2. TABLAS, RESTRICCIONES, ÍNDICES Y SECUENCIAS
-- #####################################################################
CREATE TABLE tecnico (
    id      NUMBER(4)     NOT NULL,
    codigo  VARCHAR2(10)  NOT NULL,
    nombre  VARCHAR2(80)  NOT NULL,
    activo  NUMBER(1)     DEFAULT 1 NOT NULL,
    CONSTRAINT pk_tecnico        PRIMARY KEY (id),
    CONSTRAINT uq_tecnico_codigo UNIQUE (codigo),
    CONSTRAINT uq_tecnico_nombre UNIQUE (nombre),
    CONSTRAINT ck_tecnico_activo CHECK (activo IN (0,1))
);

-- 8 competencias por técnico (1-4 = I semestre, 5-8 = II semestre); no se repiten entre técnicos
CREATE TABLE competencia (
    id         NUMBER(5)     NOT NULL,
    tecnico_id NUMBER(4)     NOT NULL,
    orden      NUMBER(1)     NOT NULL,
    semestre   NUMBER(1)     NOT NULL,
    nombre     VARCHAR2(150) NOT NULL,
    CONSTRAINT pk_competencia        PRIMARY KEY (id),
    CONSTRAINT fk_competencia_tecnico FOREIGN KEY (tecnico_id) REFERENCES tecnico (id),
    CONSTRAINT uq_competencia_orden  UNIQUE (tecnico_id, orden),
    CONSTRAINT uq_competencia_nombre UNIQUE (nombre),
    CONSTRAINT ck_competencia_orden  CHECK (orden BETWEEN 1 AND 8),
    CONSTRAINT ck_competencia_sem    CHECK (semestre = CEIL(orden / 4))
);

-- Calendario A = I semestre del año, calendario B = II semestre
CREATE TABLE periodo (
    id           NUMBER(4)    NOT NULL,
    anio         NUMBER(4)    NOT NULL,
    calendario   CHAR(1)      NOT NULL,
    codigo       VARCHAR2(7)  NOT NULL,
    fecha_inicio DATE         NOT NULL,
    fecha_fin    DATE         NOT NULL,
    CONSTRAINT pk_periodo       PRIMARY KEY (id),
    CONSTRAINT uq_periodo       UNIQUE (anio, calendario),
    CONSTRAINT uq_periodo_cod   UNIQUE (codigo),
    CONSTRAINT ck_periodo_cal   CHECK (calendario IN ('A','B')),
    CONSTRAINT ck_periodo_fechas CHECK (fecha_fin > fecha_inicio)
);

CREATE TABLE aula (
    id        NUMBER(3)    NOT NULL,
    nombre    VARCHAR2(40) NOT NULL,
    capacidad NUMBER(3)    NOT NULL,
    CONSTRAINT pk_aula        PRIMARY KEY (id),
    CONSTRAINT uq_aula_nombre UNIQUE (nombre),
    CONSTRAINT ck_aula_cap    CHECK (capacidad > 0)
);

-- ---------------------------------------------------------------------
-- 2. Usuarios del sistema (Coordinador General y Secretaria)
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
    id            NUMBER(3)    NOT NULL,
    username      VARCHAR2(40) NOT NULL,
    nombre        VARCHAR2(120) NOT NULL,
    rol           VARCHAR2(20) NOT NULL,
    password_hash VARCHAR2(128) NOT NULL,
    activo        NUMBER(1)    DEFAULT 1 NOT NULL,
    CONSTRAINT pk_usuario        PRIMARY KEY (id),
    CONSTRAINT uq_usuario_name   UNIQUE (username),
    CONSTRAINT ck_usuario_rol    CHECK (rol IN ('COORDINADOR','SECRETARIA')),
    CONSTRAINT ck_usuario_activo CHECK (activo IN (0,1))
);

-- ---------------------------------------------------------------------
-- 3. Docentes: hoja de vida, soportes de formación y contrato por hora cátedra
-- ---------------------------------------------------------------------
CREATE TABLE docente (
    id                         NUMBER(4)     NOT NULL,
    cedula                     VARCHAR2(15)  NOT NULL,
    nombres                    VARCHAR2(80)  NOT NULL,
    apellidos                  VARCHAR2(80)  NOT NULL,
    email                      VARCHAR2(120) NOT NULL,
    telefono                   VARCHAR2(20),
    nivel_formacion            VARCHAR2(20)  NOT NULL,
    anios_experiencia_docencia NUMBER(2)     NOT NULL,
    hoja_vida_url              VARCHAR2(300),
    activo                     NUMBER(1)     DEFAULT 1 NOT NULL,
    CONSTRAINT pk_docente        PRIMARY KEY (id),
    CONSTRAINT uq_docente_cedula UNIQUE (cedula),
    CONSTRAINT uq_docente_email  UNIQUE (email),
    CONSTRAINT ck_docente_nivel  CHECK (nivel_formacion IN ('Pregrado','Especialización','Maestría','Doctorado')),
    CONSTRAINT ck_docente_exp    CHECK (anios_experiencia_docencia >= 1),
    CONSTRAINT ck_docente_activo CHECK (activo IN (0,1))
);

CREATE TABLE docente_formacion (
    id          NUMBER(5)     NOT NULL,
    docente_id  NUMBER(4)     NOT NULL,
    nivel       VARCHAR2(20)  NOT NULL,
    titulo      VARCHAR2(150) NOT NULL,
    institucion VARCHAR2(150) NOT NULL,
    anio_grado  NUMBER(4)     NOT NULL,
    soporte_url VARCHAR2(300) NOT NULL,
    CONSTRAINT pk_docente_formacion PRIMARY KEY (id),
    CONSTRAINT fk_docform_docente   FOREIGN KEY (docente_id) REFERENCES docente (id) ON DELETE CASCADE,
    CONSTRAINT ck_docform_nivel     CHECK (nivel IN ('Pregrado','Especialización','Maestría','Doctorado'))
);

CREATE TABLE contrato_docente (
    id            NUMBER(5)    NOT NULL,
    docente_id    NUMBER(4)    NOT NULL,
    periodo_id    NUMBER(4)    NOT NULL,
    tipo          VARCHAR2(40) DEFAULT 'Prestación de servicios' NOT NULL,
    horas_catedra NUMBER(4)    NOT NULL,
    valor_hora    NUMBER(10,2) NOT NULL,
    CONSTRAINT pk_contrato_docente PRIMARY KEY (id),
    CONSTRAINT fk_contrato_docente FOREIGN KEY (docente_id) REFERENCES docente (id),
    CONSTRAINT fk_contrato_periodo FOREIGN KEY (periodo_id) REFERENCES periodo (id),
    CONSTRAINT uq_contrato         UNIQUE (docente_id, periodo_id),
    CONSTRAINT ck_contrato_tipo    CHECK (tipo = 'Prestación de servicios'),
    CONSTRAINT ck_contrato_horas   CHECK (horas_catedra > 0),
    CONSTRAINT ck_contrato_valor   CHECK (valor_hora > 0)
);

-- ---------------------------------------------------------------------
-- 4. Grupos y horarios (única jornada: noche 6:30 pm - 9:00 pm, dos días a la semana)
-- ---------------------------------------------------------------------
CREATE TABLE grupo (
    id         NUMBER(4)    NOT NULL,
    codigo     VARCHAR2(20) NOT NULL,
    tecnico_id NUMBER(4)    NOT NULL,
    periodo_id NUMBER(4)    NOT NULL,
    semestre   NUMBER(1)    NOT NULL,
    docente_id NUMBER(4)    NOT NULL,
    aula_id    NUMBER(3)    NOT NULL,
    cupo_min   NUMBER(2)    DEFAULT 15 NOT NULL,
    cupo_max   NUMBER(2)    DEFAULT 30 NOT NULL,
    estado     VARCHAR2(15) DEFAULT 'En formación' NOT NULL,
    CONSTRAINT pk_grupo         PRIMARY KEY (id),
    CONSTRAINT uq_grupo_codigo  UNIQUE (codigo),
    CONSTRAINT uq_grupo         UNIQUE (tecnico_id, periodo_id, semestre),
    CONSTRAINT fk_grupo_tecnico FOREIGN KEY (tecnico_id) REFERENCES tecnico (id),
    CONSTRAINT fk_grupo_periodo FOREIGN KEY (periodo_id) REFERENCES periodo (id),
    CONSTRAINT fk_grupo_docente FOREIGN KEY (docente_id) REFERENCES docente (id),
    CONSTRAINT fk_grupo_aula    FOREIGN KEY (aula_id)    REFERENCES aula (id),
    CONSTRAINT ck_grupo_sem     CHECK (semestre IN (1,2)),
    CONSTRAINT ck_grupo_cupomin CHECK (cupo_min >= 15),
    CONSTRAINT ck_grupo_cupomax CHECK (cupo_max <= 30),
    CONSTRAINT ck_grupo_cupos   CHECK (cupo_min <= cupo_max),
    CONSTRAINT ck_grupo_estado  CHECK (estado IN ('En formación','Activo','Cerrado','Cancelado'))
);

CREATE TABLE horario_grupo (
    id          NUMBER(5)   NOT NULL,
    grupo_id    NUMBER(4)   NOT NULL,
    dia_semana  NUMBER(1)   NOT NULL,                 -- 1 = lunes ... 6 = sábado
    hora_inicio VARCHAR2(5) DEFAULT '18:30' NOT NULL,
    hora_fin    VARCHAR2(5) DEFAULT '21:00' NOT NULL,
    CONSTRAINT pk_horario_grupo PRIMARY KEY (id),
    CONSTRAINT fk_horario_grupo FOREIGN KEY (grupo_id) REFERENCES grupo (id) ON DELETE CASCADE,
    CONSTRAINT uq_horario       UNIQUE (grupo_id, dia_semana),
    CONSTRAINT ck_horario_dia   CHECK (dia_semana BETWEEN 1 AND 6),
    CONSTRAINT ck_horario_ini   CHECK (hora_inicio = '18:30'),
    CONSTRAINT ck_horario_fin   CHECK (hora_fin = '21:00')
);

-- ---------------------------------------------------------------------
-- 5. Estudiantes (datos del Formulario de Matrícula) y documentos requisito
-- ---------------------------------------------------------------------
CREATE TABLE estudiante (
    id                 NUMBER(6)     NOT NULL,
    tipo_documento     VARCHAR2(3)   DEFAULT 'CC' NOT NULL,
    cedula             VARCHAR2(15)  NOT NULL,
    nombres            VARCHAR2(80)  NOT NULL,
    apellidos          VARCHAR2(80)  NOT NULL,
    fecha_nacimiento   DATE          NOT NULL,
    telefono           VARCHAR2(20)  NOT NULL,
    email              VARCHAR2(120) NOT NULL,
    direccion          VARCHAR2(150) NOT NULL,
    ocupacion          VARCHAR2(30)  NOT NULL,
    regimen_salud      VARCHAR2(20)  NOT NULL,
    condicion_medica   VARCHAR2(200),
    estrato            NUMBER(1)     NOT NULL,
    estado_civil       VARCHAR2(15)  NOT NULL,
    nivel_formacion    VARCHAR2(20)  NOT NULL,
    autoriza_centrales NUMBER(1)     DEFAULT 0 NOT NULL,
    fecha_autorizacion DATE,
    CONSTRAINT pk_estudiante        PRIMARY KEY (id),
    CONSTRAINT uq_estudiante_cedula UNIQUE (cedula),
    CONSTRAINT ck_est_tipodoc  CHECK (tipo_documento IN ('CC','TI','CE','PPT')),
    CONSTRAINT ck_est_ocup     CHECK (ocupacion IN ('Desempleado','Empleado','Independiente','Estudiante básica/media','Estudiante superior','Empresa')),
    CONSTRAINT ck_est_salud    CHECK (regimen_salud IN ('Contributivo','Subsidiado','Especial','Sin afiliación')),
    CONSTRAINT ck_est_estrato  CHECK (estrato BETWEEN 0 AND 6),
    CONSTRAINT ck_est_civil    CHECK (estado_civil IN ('Soltero','Casado','Unión libre','Separado','Viudo')),
    CONSTRAINT ck_est_nivel    CHECK (nivel_formacion IN ('Bachiller','Técnico','Tecnólogo','Profesional','Posgrado')),
    CONSTRAINT ck_est_autoriza CHECK (autoriza_centrales IN (0,1)),
    CONSTRAINT ck_est_autfecha CHECK (autoriza_centrales = 0 OR fecha_autorizacion IS NOT NULL)
);

CREATE TABLE documento_estudiante (
    id            NUMBER(6)     NOT NULL,
    estudiante_id NUMBER(6)     NOT NULL,
    tipo          VARCHAR2(25)  NOT NULL,
    fecha_entrega DATE          NOT NULL,
    archivo_url   VARCHAR2(300),
    CONSTRAINT pk_documento_estudiante PRIMARY KEY (id),
    CONSTRAINT fk_docest_estudiante FOREIGN KEY (estudiante_id) REFERENCES estudiante (id) ON DELETE CASCADE,
    CONSTRAINT uq_documento         UNIQUE (estudiante_id, tipo),
    CONSTRAINT ck_documento_tipo    CHECK (tipo IN ('Cédula','Diploma de bachiller','Fotografía 3x4'))
);

-- ---------------------------------------------------------------------
-- 6. Matrícula (relación N:M estudiante - grupo) y plan de pagos
-- ---------------------------------------------------------------------
CREATE TABLE matricula (
    id             NUMBER(6)    NOT NULL,
    estudiante_id  NUMBER(6)    NOT NULL,
    grupo_id       NUMBER(4)    NOT NULL,
    fecha_ingreso  DATE         NOT NULL,
    estado         VARCHAR2(12) DEFAULT 'Activa' NOT NULL,
    observaciones  VARCHAR2(300),
    registrado_por NUMBER(3),
    CONSTRAINT pk_matricula        PRIMARY KEY (id),
    CONSTRAINT fk_matricula_est    FOREIGN KEY (estudiante_id) REFERENCES estudiante (id),
    CONSTRAINT fk_matricula_grupo  FOREIGN KEY (grupo_id) REFERENCES grupo (id),
    CONSTRAINT fk_matricula_user   FOREIGN KEY (registrado_por) REFERENCES usuario (id),
    CONSTRAINT uq_matricula        UNIQUE (estudiante_id, grupo_id),
    CONSTRAINT ck_matricula_estado CHECK (estado IN ('Activa','Retirada','Finalizada'))
);

-- Cuota 0 = matrícula ($70.000); cuotas 1..4 = semestre financiado ($150.000 + 3 x $100.000)
CREATE TABLE cuota (
    id                NUMBER(7)    NOT NULL,
    matricula_id      NUMBER(6)    NOT NULL,
    numero            NUMBER(1)    NOT NULL,
    concepto          VARCHAR2(10) NOT NULL,
    valor             NUMBER(12,2) NOT NULL,
    fecha_vencimiento DATE         NOT NULL,
    CONSTRAINT pk_cuota          PRIMARY KEY (id),
    CONSTRAINT fk_cuota_matricula FOREIGN KEY (matricula_id) REFERENCES matricula (id) ON DELETE CASCADE,
    CONSTRAINT uq_cuota          UNIQUE (matricula_id, numero),
    CONSTRAINT ck_cuota_numero   CHECK (numero BETWEEN 0 AND 4),
    CONSTRAINT ck_cuota_valor    CHECK (valor > 0),
    CONSTRAINT ck_cuota_concepto CHECK ((numero = 0 AND concepto = 'MATRICULA') OR (numero > 0 AND concepto = 'CUOTA'))
);

CREATE TABLE medio_pago (
    id     NUMBER(2)    NOT NULL,
    nombre VARCHAR2(20) NOT NULL,
    CONSTRAINT pk_medio_pago        PRIMARY KEY (id),
    CONSTRAINT uq_medio_pago_nombre UNIQUE (nombre)
);

-- Recibo de caja; la factura electrónica se emite después del ingreso (queda 'Pendiente' hasta entonces)
CREATE TABLE pago (
    id             NUMBER(7)     NOT NULL,
    numero_recibo  VARCHAR2(20)  NOT NULL,
    matricula_id   NUMBER(6)     NOT NULL,
    fecha_pago     DATE          NOT NULL,
    valor          NUMBER(12,2)  NOT NULL,
    medio_pago_id  NUMBER(2)     NOT NULL,
    referencia     VARCHAR2(60),
    observacion    VARCHAR2(300),
    anulado        NUMBER(1)     DEFAULT 0 NOT NULL,
    registrado_por NUMBER(3),
    factura_numero VARCHAR2(20),
    factura_estado VARCHAR2(10)  DEFAULT 'Pendiente' NOT NULL,
    factura_fecha  DATE,
    CONSTRAINT pk_pago           PRIMARY KEY (id),
    CONSTRAINT uq_pago_recibo    UNIQUE (numero_recibo),
    CONSTRAINT uq_pago_factura   UNIQUE (factura_numero),
    CONSTRAINT fk_pago_matricula FOREIGN KEY (matricula_id)  REFERENCES matricula (id),
    CONSTRAINT fk_pago_medio     FOREIGN KEY (medio_pago_id) REFERENCES medio_pago (id),
    CONSTRAINT fk_pago_user      FOREIGN KEY (registrado_por) REFERENCES usuario (id),
    CONSTRAINT ck_pago_valor     CHECK (valor > 0),
    CONSTRAINT ck_pago_anulado   CHECK (anulado IN (0,1)),
    CONSTRAINT ck_pago_fact_est  CHECK (factura_estado IN ('Pendiente','Emitida','Anulada')),
    CONSTRAINT ck_pago_fact_emi  CHECK (factura_estado <> 'Emitida' OR (factura_numero IS NOT NULL AND factura_fecha IS NOT NULL))
);

-- Relación N:M pago - cuota: un pago puede cubrir varias cuotas y una cuota recibir varios abonos
CREATE TABLE aplicacion_pago (
    pago_id        NUMBER(7)    NOT NULL,
    cuota_id       NUMBER(7)    NOT NULL,
    valor_aplicado NUMBER(12,2) NOT NULL,
    CONSTRAINT pk_aplicacion_pago PRIMARY KEY (pago_id, cuota_id),
    CONSTRAINT fk_aplic_pago      FOREIGN KEY (pago_id)  REFERENCES pago (id) ON DELETE CASCADE,
    CONSTRAINT fk_aplic_cuota     FOREIGN KEY (cuota_id) REFERENCES cuota (id),
    CONSTRAINT ck_aplic_valor     CHECK (valor_aplicado > 0)
);

-- ---------------------------------------------------------------------
-- 7. Clases, asistencia (N:M sesión - matrícula) y calificaciones (N:M matrícula - competencia)
-- ---------------------------------------------------------------------
CREATE TABLE sesion_clase (
    id             NUMBER(6)     NOT NULL,
    grupo_id       NUMBER(4)     NOT NULL,
    competencia_id NUMBER(5)     NOT NULL,
    fecha          DATE          NOT NULL,
    hora_inicio    VARCHAR2(5)   DEFAULT '18:30' NOT NULL,
    hora_fin       VARCHAR2(5)   DEFAULT '21:00' NOT NULL,
    tema           VARCHAR2(150),
    CONSTRAINT pk_sesion_clase  PRIMARY KEY (id),
    CONSTRAINT fk_sesion_grupo  FOREIGN KEY (grupo_id) REFERENCES grupo (id),
    CONSTRAINT fk_sesion_comp   FOREIGN KEY (competencia_id) REFERENCES competencia (id),
    CONSTRAINT uq_sesion        UNIQUE (grupo_id, fecha)
);

CREATE TABLE asistencia (
    sesion_id    NUMBER(6) NOT NULL,
    matricula_id NUMBER(6) NOT NULL,
    presente     NUMBER(1) NOT NULL,
    CONSTRAINT pk_asistencia      PRIMARY KEY (sesion_id, matricula_id),
    CONSTRAINT fk_asist_sesion    FOREIGN KEY (sesion_id)    REFERENCES sesion_clase (id) ON DELETE CASCADE,
    CONSTRAINT fk_asist_matricula FOREIGN KEY (matricula_id) REFERENCES matricula (id),
    CONSTRAINT ck_asist_presente  CHECK (presente IN (0,1))
);

-- Escala 1.0 a 5.0; aprueba con 3.0 o más. Si pierde, UN supletorio por competencia.
CREATE TABLE calificacion (
    id             NUMBER(7)    NOT NULL,
    matricula_id   NUMBER(6)    NOT NULL,
    competencia_id NUMBER(5)    NOT NULL,
    tipo           VARCHAR2(10) DEFAULT 'Ordinaria' NOT NULL,
    nota           NUMBER(2,1)  NOT NULL,
    fecha          DATE         NOT NULL,
    registrado_por NUMBER(3),
    CONSTRAINT pk_calificacion   PRIMARY KEY (id),
    CONSTRAINT fk_calif_matricula FOREIGN KEY (matricula_id)   REFERENCES matricula (id),
    CONSTRAINT fk_calif_comp     FOREIGN KEY (competencia_id) REFERENCES competencia (id),
    CONSTRAINT fk_calif_user     FOREIGN KEY (registrado_por) REFERENCES usuario (id),
    CONSTRAINT uq_calificacion   UNIQUE (matricula_id, competencia_id, tipo),
    CONSTRAINT ck_calif_tipo     CHECK (tipo IN ('Ordinaria','Supletorio')),
    CONSTRAINT ck_calif_nota     CHECK (nota BETWEEN 1.0 AND 5.0)
);

-- ---------------------------------------------------------------------
-- 8. Diploma de Técnico Laboral por Competencias
-- ---------------------------------------------------------------------
CREATE TABLE diploma (
    id             NUMBER(6)    NOT NULL,
    estudiante_id  NUMBER(6)    NOT NULL,
    tecnico_id     NUMBER(4)    NOT NULL,
    numero_diploma VARCHAR2(20) NOT NULL,
    fecha_emision  DATE         NOT NULL,
    registrado_por NUMBER(3),
    CONSTRAINT pk_diploma         PRIMARY KEY (id),
    CONSTRAINT fk_diploma_est     FOREIGN KEY (estudiante_id) REFERENCES estudiante (id),
    CONSTRAINT fk_diploma_tecnico FOREIGN KEY (tecnico_id)    REFERENCES tecnico (id),
    CONSTRAINT fk_diploma_user    FOREIGN KEY (registrado_por) REFERENCES usuario (id),
    CONSTRAINT uq_diploma         UNIQUE (estudiante_id, tecnico_id),
    CONSTRAINT uq_diploma_numero  UNIQUE (numero_diploma)
);

-- ---------------------------------------------------------------------
-- 9. Índices sobre llaves foráneas de consulta frecuente
-- ---------------------------------------------------------------------
CREATE INDEX ix_matricula_grupo   ON matricula (grupo_id);
CREATE INDEX ix_matricula_est     ON matricula (estudiante_id);
CREATE INDEX ix_cuota_vence       ON cuota (fecha_vencimiento);
CREATE INDEX ix_pago_matricula    ON pago (matricula_id);
CREATE INDEX ix_pago_fecha        ON pago (fecha_pago);
CREATE INDEX ix_aplic_cuota       ON aplicacion_pago (cuota_id);
CREATE INDEX ix_calif_matricula   ON calificacion (matricula_id);
CREATE INDEX ix_asist_matricula   ON asistencia (matricula_id);
CREATE INDEX ix_sesion_grupo      ON sesion_clase (grupo_id);
CREATE INDEX ix_grupo_periodo     ON grupo (periodo_id);
CREATE INDEX ix_estudiante_apell  ON estudiante (apellidos, nombres);

-- ---------------------------------------------------------------------
-- 10. Secuencias para las llaves primarias (los datos de prueba usan ids menores a 10000)
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_tecnico            START WITH 100;
CREATE SEQUENCE seq_competencia        START WITH 1000;
CREATE SEQUENCE seq_periodo            START WITH 100;
CREATE SEQUENCE seq_aula               START WITH 100;
CREATE SEQUENCE seq_usuario            START WITH 100;
CREATE SEQUENCE seq_docente            START WITH 100;
CREATE SEQUENCE seq_docente_formacion  START WITH 1000;
CREATE SEQUENCE seq_contrato_docente   START WITH 1000;
CREATE SEQUENCE seq_grupo              START WITH 1000;
CREATE SEQUENCE seq_horario_grupo      START WITH 1000;
CREATE SEQUENCE seq_estudiante         START WITH 10000;
CREATE SEQUENCE seq_documento          START WITH 10000;
CREATE SEQUENCE seq_matricula          START WITH 10000;
CREATE SEQUENCE seq_cuota              START WITH 10000;
CREATE SEQUENCE seq_medio_pago         START WITH 100;
CREATE SEQUENCE seq_pago               START WITH 10000;
CREATE SEQUENCE seq_sesion             START WITH 10000;
CREATE SEQUENCE seq_calificacion       START WITH 10000;
CREATE SEQUENCE seq_diploma            START WITH 1000;

-- #####################################################################
-- 3. VISTAS Y PROCEDIMIENTOS ALMACENADOS
-- #####################################################################
CREATE OR REPLACE VIEW v_estado_credito AS
SELECT m.id AS matricula_id, m.estudiante_id, m.grupo_id,
       SUM(c.valor)                                   AS total_obligado,
       SUM(NVL(a.pagado, 0))                          AS total_pagado,
       SUM(c.valor - NVL(a.pagado, 0))                AS saldo,
       SUM(CASE WHEN NVL(a.pagado, 0) < c.valor AND c.fecha_vencimiento < TRUNC(SYSDATE) THEN 1 ELSE 0 END) AS cuotas_vencidas,
       NVL(TRUNC(SYSDATE) - MIN(CASE WHEN NVL(a.pagado, 0) < c.valor AND c.fecha_vencimiento < TRUNC(SYSDATE)
                                     THEN c.fecha_vencimiento END), 0)                                       AS dias_mora,
       CASE WHEN SUM(c.valor - NVL(a.pagado, 0)) = 0 THEN 'Paz y salvo'
            WHEN SUM(CASE WHEN NVL(a.pagado, 0) < c.valor AND c.fecha_vencimiento < TRUNC(SYSDATE) THEN 1 ELSE 0 END) > 0 THEN 'En mora'
            ELSE 'Al día' END                                                                                 AS estado
  FROM matricula m
  JOIN cuota c ON c.matricula_id = m.id
  LEFT JOIN (SELECT ap.cuota_id, SUM(ap.valor_aplicado) AS pagado
               FROM aplicacion_pago ap JOIN pago p ON p.id = ap.pago_id
              WHERE p.anulado = 0
              GROUP BY ap.cuota_id) a ON a.cuota_id = c.id
 GROUP BY m.id, m.estudiante_id, m.grupo_id;

-- Notas visibles: las de un estudiante en mora salen retenidas
CREATE OR REPLACE VIEW v_boletin AS
SELECT e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, g.codigo AS grupo, c.orden, c.nombre AS competencia,
       CASE WHEN ec.estado = 'En mora' THEN 'RETENIDA (en mora)' ELSE TO_CHAR(k.nota, 'FM0.0') END AS nota,
       k.tipo
  FROM calificacion k
  JOIN matricula m   ON m.id = k.matricula_id
  JOIN estudiante e  ON e.id = m.estudiante_id
  JOIN grupo g       ON g.id = m.grupo_id
  JOIN competencia c ON c.id = k.competencia_id
  JOIN v_estado_credito ec ON ec.matricula_id = m.id;

-- ---------------------------------------------------------------------
-- Genera las 5 cuotas de una matrícula: matrícula 70.000 + cuota 1 de 150.000 + 3 cuotas de 100.000
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_generar_plan_pagos (p_matricula IN NUMBER) IS
    v_ingreso DATE;
BEGIN
    SELECT fecha_ingreso INTO v_ingreso FROM matricula WHERE id = p_matricula;
    FOR i IN 0 .. 4 LOOP
        INSERT INTO cuota (id, matricula_id, numero, concepto, valor, fecha_vencimiento)
        VALUES (seq_cuota.NEXTVAL, p_matricula, i,
                CASE WHEN i = 0 THEN 'MATRICULA' ELSE 'CUOTA' END,
                CASE i WHEN 0 THEN 70000 WHEN 1 THEN 150000 ELSE 100000 END,
                v_ingreso + 30 * GREATEST(i - 1, 0));
    END LOOP;
END sp_generar_plan_pagos;
/

-- ---------------------------------------------------------------------
-- Matricula a un estudiante aplicando las reglas del negocio y genera su plan de pagos
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_matricular (
    p_estudiante IN NUMBER, p_grupo IN NUMBER, p_usuario IN NUMBER, p_fecha IN DATE DEFAULT TRUNC(SYSDATE)
) IS
    v_grupo   grupo%ROWTYPE;
    v_n       NUMBER;
    v_mat     NUMBER;
BEGIN
    SELECT * INTO v_grupo FROM grupo WHERE id = p_grupo;

    IF v_grupo.estado IN ('Cerrado', 'Cancelado') THEN
        RAISE_APPLICATION_ERROR(-20001, 'El grupo ' || v_grupo.codigo || ' no admite matrículas (' || v_grupo.estado || ')');
    END IF;

    -- Documentos requisito: cédula y diploma de bachiller
    SELECT COUNT(*) INTO v_n FROM documento_estudiante
     WHERE estudiante_id = p_estudiante AND tipo IN ('Cédula', 'Diploma de bachiller');
    IF v_n < 2 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Faltan documentos requisito (cédula y diploma de bachiller)');
    END IF;

    -- Cupo máximo
    SELECT COUNT(*) INTO v_n FROM matricula WHERE grupo_id = p_grupo AND estado <> 'Retirada';
    IF v_n >= v_grupo.cupo_max THEN
        RAISE_APPLICATION_ERROR(-20003, 'El grupo alcanzó el cupo máximo (' || v_grupo.cupo_max || ')');
    END IF;

    -- Puede cursar dos técnicos a la vez, pero no el mismo técnico dos veces en el periodo
    SELECT COUNT(*) INTO v_n FROM matricula m JOIN grupo g ON g.id = m.grupo_id
     WHERE m.estudiante_id = p_estudiante AND g.tecnico_id = v_grupo.tecnico_id
       AND g.periodo_id = v_grupo.periodo_id AND m.estado <> 'Retirada';
    IF v_n > 0 THEN
        RAISE_APPLICATION_ERROR(-20004, 'El estudiante ya está matriculado en este técnico en el mismo periodo');
    END IF;

    -- Prerrequisito: para el II semestre deben estar aprobadas las 4 competencias del I
    IF v_grupo.semestre = 2 THEN
        SELECT COUNT(*) INTO v_n FROM competencia c
         WHERE c.tecnico_id = v_grupo.tecnico_id AND c.semestre = 1
           AND EXISTS (SELECT 1 FROM calificacion k JOIN matricula m ON m.id = k.matricula_id
                        WHERE m.estudiante_id = p_estudiante AND k.competencia_id = c.id AND k.nota >= 3);
        IF v_n < 4 THEN
            RAISE_APPLICATION_ERROR(-20005, 'No ha aprobado las 4 competencias del I semestre');
        END IF;
    END IF;

    -- En mora no se continúa
    SELECT COUNT(*) INTO v_n FROM v_estado_credito WHERE estudiante_id = p_estudiante AND estado = 'En mora';
    IF v_n > 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'El estudiante está en mora; debe ponerse al día para matricularse');
    END IF;

    SELECT seq_matricula.NEXTVAL INTO v_mat FROM dual;
    INSERT INTO matricula (id, estudiante_id, grupo_id, fecha_ingreso, estado, registrado_por)
    VALUES (v_mat, p_estudiante, p_grupo, p_fecha, 'Activa', p_usuario);
    sp_generar_plan_pagos(v_mat);
END sp_matricular;
/

-- ---------------------------------------------------------------------
-- Registra un recibo de caja y lo aplica a las cuotas más antiguas primero
-- La factura electrónica queda 'Pendiente' hasta que se emita (después del ingreso)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_pago (
    p_matricula IN NUMBER, p_recibo IN VARCHAR2, p_valor IN NUMBER,
    p_medio IN NUMBER, p_usuario IN NUMBER, p_fecha IN DATE DEFAULT TRUNC(SYSDATE)
) IS
    v_pendiente NUMBER;
    v_resto     NUMBER := p_valor;
    v_aplicar   NUMBER;
    v_pago      NUMBER;
BEGIN
    SELECT NVL(SUM(c.valor - NVL((SELECT SUM(ap.valor_aplicado) FROM aplicacion_pago ap JOIN pago p ON p.id = ap.pago_id
                                   WHERE ap.cuota_id = c.id AND p.anulado = 0), 0)), 0)
      INTO v_pendiente FROM cuota c WHERE c.matricula_id = p_matricula;

    IF p_valor > v_pendiente THEN
        RAISE_APPLICATION_ERROR(-20010, 'El pago (' || p_valor || ') supera el saldo pendiente (' || v_pendiente || ')');
    END IF;

    SELECT seq_pago.NEXTVAL INTO v_pago FROM dual;
    INSERT INTO pago (id, numero_recibo, matricula_id, fecha_pago, valor, medio_pago_id, anulado, registrado_por, factura_estado)
    VALUES (v_pago, p_recibo, p_matricula, p_fecha, p_valor, p_medio, 0, p_usuario, 'Pendiente');

    FOR r IN (SELECT c.id,
                     c.valor - NVL((SELECT SUM(ap.valor_aplicado) FROM aplicacion_pago ap JOIN pago p ON p.id = ap.pago_id
                                     WHERE ap.cuota_id = c.id AND p.anulado = 0 AND p.id <> v_pago), 0) AS falta
                FROM cuota c WHERE c.matricula_id = p_matricula ORDER BY c.numero) LOOP
        EXIT WHEN v_resto <= 0;
        IF r.falta > 0 THEN
            v_aplicar := LEAST(r.falta, v_resto);
            INSERT INTO aplicacion_pago (pago_id, cuota_id, valor_aplicado) VALUES (v_pago, r.id, v_aplicar);
            v_resto := v_resto - v_aplicar;
        END IF;
    END LOOP;
END sp_registrar_pago;
/

-- Prueba rápida (deshacer con ROLLBACK):
-- EXEC sp_registrar_pago(<matricula con saldo>, '99990', 50000, 1, 2);
-- SELECT * FROM aplicacion_pago WHERE pago_id = (SELECT MAX(id) FROM pago);
-- ROLLBACK;

-- #####################################################################
-- 4. AVANCE PL/SQL: AUDITORÍA, ÍNDICES, SECUENCIAS, VISTA, PAQUETES Y TRIGGERS
-- #####################################################################
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

-- #####################################################################
-- 5. PAQUETES DE LA APLICACIÓN WEB Y TRIGGERS COMPLEMENTARIOS
-- #####################################################################
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
    -- Son las mismas reglas de PKG_GRUPO.crear (sección 4).
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
        p_recibo := pkg_util.fn_siguiente_recibo;   -- consecutivo sin saltos (SEQ_RECIBO, sección 4)
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
-- Triggers complementarios (no repiten los 7 de la sección 4).  Códigos -20020 a -20027
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

-- #####################################################################
-- 6. PERMISOS DE LOS ROLES
-- #####################################################################
-- Permisos de los roles sobre tablas, vistas, secuencias, procedimientos y paquetes.
-- Los roles los crea USUARIOS.sql (como SYSTEM). Si no existen, se avisa y el script continúa.
DECLARE
  TYPE t_lista IS TABLE OF VARCHAR2(200);
  v_fijos t_lista := t_lista(
    'GRANT SELECT ON v_estado_credito TO rol_coordinador',
    'GRANT SELECT ON v_estado_credito TO rol_secretaria',
    'GRANT SELECT ON v_boletin TO rol_coordinador',
    'GRANT SELECT ON v_boletin TO rol_secretaria',
    'GRANT INSERT, UPDATE ON estudiante TO rol_secretaria',
    'GRANT INSERT, UPDATE ON documento_estudiante TO rol_secretaria',
    'GRANT INSERT, UPDATE ON matricula TO rol_secretaria',
    'GRANT INSERT, UPDATE ON cuota TO rol_secretaria',
    'GRANT INSERT, UPDATE ON pago TO rol_secretaria',
    'GRANT INSERT ON aplicacion_pago TO rol_secretaria',
    'GRANT INSERT, UPDATE ON sesion_clase TO rol_secretaria',
    'GRANT INSERT, UPDATE ON asistencia TO rol_secretaria',
    'GRANT INSERT, UPDATE ON calificacion TO rol_secretaria',
    'GRANT EXECUTE ON sp_matricular TO rol_secretaria',
    'GRANT EXECUTE ON sp_registrar_pago TO rol_secretaria',
    'GRANT EXECUTE ON sp_matricular TO rol_coordinador',
    'GRANT EXECUTE ON sp_registrar_pago TO rol_coordinador',
    'REVOKE SELECT ON usuario FROM rol_secretaria',
    'GRANT SELECT ON v_asistencia_matricula TO rol_coordinador',
    'GRANT SELECT ON v_asistencia_matricula TO rol_secretaria',
    'GRANT SELECT ON auditoria TO rol_coordinador',
    'GRANT EXECUTE ON pkg_util TO rol_coordinador',
    'GRANT EXECUTE ON pkg_estudiante TO rol_coordinador',
    'GRANT EXECUTE ON pkg_docente TO rol_coordinador',
    'GRANT EXECUTE ON pkg_grupo TO rol_coordinador',
    'GRANT EXECUTE ON pkg_calificacion TO rol_coordinador',
    'GRANT EXECUTE ON pkg_certificacion TO rol_coordinador',
    'GRANT EXECUTE ON pkg_util TO rol_secretaria',
    'GRANT EXECUTE ON pkg_estudiante TO rol_secretaria',
    'GRANT EXECUTE ON pkg_calificacion TO rol_secretaria');
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
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN ('TECNICO','COMPETENCIA','PERIODO','AULA','USUARIO','DOCENTE','DOCENTE_FORMACION','CONTRATO_DOCENTE','GRUPO','HORARIO_GRUPO','ESTUDIANTE','DOCUMENTO_ESTUDIANTE','MATRICULA','MEDIO_PAGO','CUOTA','PAGO','APLICACION_PAGO','SESION_CLASE','ASISTENCIA','CALIFICACION','DIPLOMA','AUDITORIA')) LOOP
    ejecutar('GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO rol_coordinador');
    ejecutar('GRANT SELECT ON ' || t.table_name || ' TO rol_secretaria');
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ\_%' ESCAPE '\') LOOP
    ejecutar('GRANT SELECT ON ' || s.sequence_name || ' TO rol_coordinador');
    ejecutar('GRANT SELECT ON ' || s.sequence_name || ' TO rol_secretaria');
  END LOOP;
  FOR i IN 1 .. v_fijos.COUNT LOOP
    ejecutar(v_fijos(i));
  END LOOP;
  IF v_fallos = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Permisos de los roles aplicados.');
  ELSE
    DBMS_OUTPUT.PUT_LINE(v_fallos || ' permisos no se aplicaron: ejecute USUARIOS.sql como SYSTEM y luego vuelva a correr DDL.sql.');
  END IF;
END;
/

-- #####################################################################
-- VERIFICACIÓN
-- #####################################################################
SET PAGESIZE 100 LINESIZE 150
PROMPT Objetos del esquema (la columna INVALIDOS debe quedar en 0):
SELECT object_type, COUNT(*) AS cantidad, SUM(DECODE(status, 'INVALID', 1, 0)) AS invalidos
  FROM user_objects
 WHERE object_name NOT LIKE 'BIN$%' AND object_name NOT LIKE 'DBTOOLS$%'
 GROUP BY object_type
 ORDER BY object_type;
SELECT name, type, line, SUBSTR(text, 1, 100) AS error FROM user_errors WHERE name NOT LIKE 'BIN$%' ORDER BY name, sequence;
