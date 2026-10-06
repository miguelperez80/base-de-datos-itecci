-- =====================================================================
-- ITECCI - Técnicos Laborales por Competencias (Cámara de Comercio de Ipiales)
-- 02_ddl.sql : creación de tablas, restricciones, relaciones, índices y secuencias
-- Compatible con Oracle 11g / 18c.  Ejecutar conectado como el usuario ITECCI.
-- =====================================================================
SET DEFINE OFF

-- Limpieza opcional (descomentar para recrear): DROP TABLE ... CASCADE CONSTRAINTS;

-- ---------------------------------------------------------------------
-- 1. Catálogos de la oferta académica
-- ---------------------------------------------------------------------
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
