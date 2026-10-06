-- =====================================================================
-- 04_plsql_vistas.sql : vista de estado de crédito y procedimientos almacenados (Oracle 11g/18c)
-- Ejecutar como ITECCI después de 02_ddl.sql y 03_dml.sql.   Cada bloque termina en "/".
-- =====================================================================
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- Estado de crédito por matrícula (el reporte más difícil para ITECCI)
--   Paz y salvo: saldo = 0 | En mora: hay cuota vencida sin pagar | Al día: debe pero nada vencido
-- ---------------------------------------------------------------------
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
