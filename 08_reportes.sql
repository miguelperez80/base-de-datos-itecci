-- =====================================================================
-- ITECCI - Avance PL/SQL
-- 08_reportes.sql : (a) bloques anónimos que funcionan como reportes del negocio
-- Ejecutar como ITECCI después de 07_plsql_objetos.sql. Cada bloque termina en "/".
--
--   R1  Cartera en mora por grupo de un periodo     cursores con parámetros anidados, IF, CASE, excepción propia
--   R2  Boletín de notas de un estudiante           SELECT INTO + NO_DATA_FOUND/TOO_MANY_ROWS, cursor FOR, CASE
--   R3  Control de asistencia de un grupo           RECORD + TABLE OF + BULK COLLECT, WHILE con FIRST/NEXT
--   R4  Recaudo mensual por medio de pago           LOOP con EXIT WHEN, tabla indexada por VARCHAR2
--   R5  Candidatos a diploma                        cursor explícito OPEN/FETCH/CLOSE, %NOTFOUND, %ROWCOUNT
--   R6  Liquidación de honorarios docentes          FOR numérico, CASE, ZERO_DIVIDE
--   R7  Facturas electrónicas pendientes            cursor FOR, CASE por antigüedad (usa IX_PAGO_FACTURA)
--
--   Los valores en pesos y las fechas se muestran con el formato de PKG_UTIL (regla k).
--   Las fechas de corte dependen de SYSDATE; cambie las variables v_* al inicio de cada bloque.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- R1. CARTERA EN MORA POR GRUPO (periodo parametrizable)
-- ---------------------------------------------------------------------
DECLARE
  v_periodo    periodo.codigo%TYPE := '2026-B';

  CURSOR c_grupos (p_periodo VARCHAR2) IS
    SELECT g.id, g.codigo, t.nombre AS tecnico
      FROM grupo g
      JOIN periodo p ON p.id = g.periodo_id
      JOIN tecnico t ON t.id = g.tecnico_id
     WHERE p.codigo = p_periodo
     ORDER BY g.codigo;

  CURSOR c_morosos (p_grupo NUMBER) IS
    SELECT e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, e.telefono,
           ec.saldo, ec.cuotas_vencidas, ec.dias_mora
      FROM v_estado_credito ec
      JOIN estudiante e ON e.id = ec.estudiante_id
     WHERE ec.grupo_id = p_grupo AND ec.estado = 'En mora'
     ORDER BY ec.dias_mora DESC, ec.saldo DESC;

  v_grupos      PLS_INTEGER := 0;
  v_n_grupo     PLS_INTEGER;
  v_sal_grupo   NUMBER;
  v_n_total     PLS_INTEGER := 0;
  v_sal_total   NUMBER := 0;
  v_nivel       VARCHAR2(10);
  e_sin_grupos  EXCEPTION;
BEGIN
  pkg_util.pl('==================================================================');
  pkg_util.pl(' R1. CARTERA EN MORA - PERIODO ' || v_periodo || '  (corte ' || pkg_util.fn_fecha(SYSDATE) || ')');
  pkg_util.pl('==================================================================');

  FOR g IN c_grupos(v_periodo) LOOP
    v_grupos    := v_grupos + 1;
    v_n_grupo   := 0;
    v_sal_grupo := 0;
    pkg_util.pl(CHR(10) || g.codigo || ' - ' || g.tecnico);

    FOR m IN c_morosos(g.id) LOOP
      v_n_grupo   := v_n_grupo + 1;
      v_sal_grupo := v_sal_grupo + m.saldo;
      v_nivel := CASE
                   WHEN m.dias_mora > 60 THEN 'CRÍTICA'
                   WHEN m.dias_mora > 30 THEN 'ALTA'
                   ELSE 'MEDIA'
                 END;
      pkg_util.pl('  ' || RPAD(m.cedula, 11) || RPAD(SUBSTR(m.estudiante, 1, 30), 31) || RPAD(m.telefono, 11)
                  || LPAD(pkg_util.fn_moneda(m.saldo), 10) || LPAD(m.cuotas_vencidas, 3) || ' cuotas '
                  || LPAD(m.dias_mora, 4) || ' días  ' || v_nivel);
    END LOOP;

    IF v_n_grupo = 0 THEN
      pkg_util.pl('  Sin estudiantes en mora');
    ELSE
      pkg_util.pl('  Subtotal: ' || v_n_grupo || ' estudiantes, ' || pkg_util.fn_moneda(v_sal_grupo));
    END IF;
    v_n_total   := v_n_total + v_n_grupo;
    v_sal_total := v_sal_total + v_sal_grupo;
  END LOOP;

  IF v_grupos = 0 THEN
    RAISE e_sin_grupos;
  END IF;
  pkg_util.pl(CHR(10) || 'TOTAL: ' || v_n_total || ' matrículas en mora en ' || v_grupos || ' grupos por '
              || pkg_util.fn_moneda(v_sal_total));
EXCEPTION
  WHEN e_sin_grupos THEN
    pkg_util.pl('No hay grupos en el periodo ' || v_periodo);
END;
/

-- ---------------------------------------------------------------------
-- R2. BOLETÍN DE NOTAS DE UN ESTUDIANTE (todas sus matrículas)
--     Si una matrícula está en mora sus notas salen retenidas (RN-25).
-- ---------------------------------------------------------------------
DECLARE
  v_cedula   estudiante.cedula%TYPE := '1017821631';
  v_est      estudiante%ROWTYPE;
  v_estado   VARCHAR2(20);
  v_suma     NUMBER;
  v_cuenta   PLS_INTEGER;
  v_resultado VARCHAR2(40);
BEGIN
  SELECT * INTO v_est FROM estudiante WHERE cedula = v_cedula;

  pkg_util.pl('==================================================================');
  pkg_util.pl(' R2. BOLETÍN - ' || v_est.apellidos || ' ' || v_est.nombres || ' (CC ' || v_est.cedula || ')');
  pkg_util.pl('==================================================================');

  FOR m IN (SELECT m.id, g.codigo, g.tecnico_id, g.semestre, m.estado, ec.estado AS credito
              FROM matricula m
              JOIN grupo g ON g.id = m.grupo_id
              JOIN periodo p ON p.id = g.periodo_id
              LEFT JOIN v_estado_credito ec ON ec.matricula_id = m.id
             WHERE m.estudiante_id = v_est.id
             ORDER BY p.fecha_inicio) LOOP
    pkg_util.pl(CHR(10) || m.codigo || '  matrícula ' || m.estado || '  crédito: ' || NVL(m.credito, 's/d'));
    v_suma := 0;
    v_cuenta := 0;

    FOR c IN (SELECT c.orden, c.nombre,
                     MAX(CASE k.tipo WHEN 'Ordinaria'  THEN k.nota END) AS ordinaria,
                     MAX(CASE k.tipo WHEN 'Supletorio' THEN k.nota END) AS supletorio
                FROM competencia c
                LEFT JOIN calificacion k ON k.competencia_id = c.id AND k.matricula_id = m.id
               WHERE c.tecnico_id = m.tecnico_id AND c.semestre = m.semestre
               GROUP BY c.orden, c.nombre
               ORDER BY c.orden) LOOP

      IF m.credito = 'En mora' THEN
        v_resultado := 'RETENIDA (en mora)';
      ELSE
        v_resultado := CASE
                         WHEN c.ordinaria IS NULL                      THEN 'Sin calificar'
                         WHEN c.ordinaria >= 3                         THEN pkg_util.fn_nota(c.ordinaria) || '  Aprobó'
                         WHEN c.supletorio IS NULL                     THEN pkg_util.fn_nota(c.ordinaria) || '  Perdió - pendiente supletorio'
                         WHEN c.supletorio >= 3                        THEN pkg_util.fn_nota(c.supletorio) || '  Aprobó en supletorio'
                         ELSE pkg_util.fn_nota(c.supletorio) || '  Reprobó (repite competencia)'
                       END;
        IF NVL(c.supletorio, c.ordinaria) IS NOT NULL THEN
          v_suma   := v_suma + NVL(c.supletorio, c.ordinaria);
          v_cuenta := v_cuenta + 1;
        END IF;
      END IF;
      pkg_util.pl('  ' || c.orden || '. ' || RPAD(SUBSTR(c.nombre, 1, 45), 46) || v_resultado);
    END LOOP;

    IF v_cuenta > 0 THEN
      pkg_util.pl('  Promedio del semestre: ' || pkg_util.fn_nota(ROUND(v_suma / v_cuenta, 1)));
    END IF;
  END LOOP;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    pkg_util.pl('No existe un estudiante con la cédula ' || v_cedula);
  WHEN TOO_MANY_ROWS THEN
    pkg_util.pl('La cédula ' || v_cedula || ' está duplicada; revise los datos');
END;
/

-- ---------------------------------------------------------------------
-- R3. CONTROL DE ASISTENCIA DE UN GRUPO (alerta de quienes están por debajo del 80 %)
-- ---------------------------------------------------------------------
DECLARE
  v_grupo  grupo.codigo%TYPE := 'SIS-2026B-S2';

  TYPE t_asistencia IS RECORD (                                       -- RECORD
    cedula      VARCHAR2(15),            -- mismo tipo de estudiante.cedula (con %TYPE el campo "estudiante" oculta a la tabla: PLS-00320)
    estudiante  VARCHAR2(170),
    sesiones    NUMBER,
    asistidas   NUMBER,
    porcentaje  NUMBER);
  TYPE t_tab_asistencia IS TABLE OF t_asistencia INDEX BY PLS_INTEGER;   -- TABLE
  v_lista    t_tab_asistencia;

  i          PLS_INTEGER;
  v_alertas  PLS_INTEGER := 0;
  v_suma_pct NUMBER := 0;
  v_marca    VARCHAR2(30);
BEGIN
  SELECT e.cedula, e.apellidos || ' ' || e.nombres, v.sesiones, v.asistidas, v.porcentaje
    BULK COLLECT INTO v_lista                                         -- BULK COLLECT
    FROM v_asistencia_matricula v
    JOIN estudiante e ON e.id = v.estudiante_id
    JOIN grupo g      ON g.id = v.grupo_id
   WHERE g.codigo = v_grupo AND v.estado_matricula <> 'Retirada'
   ORDER BY v.porcentaje, e.apellidos;

  pkg_util.pl('==================================================================');
  pkg_util.pl(' R3. ASISTENCIA - GRUPO ' || v_grupo || ' (' || v_lista.COUNT || ' estudiantes)');
  pkg_util.pl('==================================================================');

  IF v_lista.COUNT = 0 THEN
    pkg_util.pl('El grupo no existe o no tiene matriculados');
    RETURN;
  END IF;

  i := v_lista.FIRST;
  WHILE i IS NOT NULL LOOP                                            -- WHILE
    IF v_lista(i).porcentaje IS NULL THEN
      v_marca := 'sin sesiones';
    ELSIF v_lista(i).porcentaje < pkg_util.c_asist_minima THEN
      v_marca := '<< NO CUMPLE 80 %';
      v_alertas := v_alertas + 1;
    ELSIF v_lista(i).porcentaje < 85 THEN
      v_marca := 'en riesgo';
    ELSE
      v_marca := 'ok';
    END IF;
    v_suma_pct := v_suma_pct + NVL(v_lista(i).porcentaje, 0);

    pkg_util.pl('  ' || RPAD(v_lista(i).cedula, 11) || RPAD(SUBSTR(v_lista(i).estudiante, 1, 32), 33)
                || LPAD(v_lista(i).asistidas, 3) || '/' || RPAD(v_lista(i).sesiones, 3)
                || LPAD(NVL(TO_CHAR(v_lista(i).porcentaje, 'FM990.0'), '-'), 6) || ' %  ' || v_marca);
    i := v_lista.NEXT(i);
  END LOOP;

  pkg_util.pl(CHR(10) || 'Promedio del grupo: ' || TO_CHAR(ROUND(v_suma_pct / v_lista.COUNT, 1), 'FM990.0') || ' %');
  pkg_util.pl('Estudiantes que hoy no podrían certificarse por asistencia: ' || v_alertas);
END;
/

-- ---------------------------------------------------------------------
-- R4. RECAUDO MENSUAL POR MEDIO DE PAGO DE UN AÑO
-- ---------------------------------------------------------------------
DECLARE
  v_anio     NUMBER := 2026;
  v_mes      PLS_INTEGER := 1;
  v_ultimo   PLS_INTEGER;

  TYPE t_mes IS RECORD (efectivo NUMBER, datafono NUMBER, transferencia NUMBER, recibos NUMBER);
  v_m        t_mes;

  TYPE t_totales IS TABLE OF NUMBER INDEX BY VARCHAR2(20);           -- tabla indexada por texto
  v_tot      t_totales;
  v_medio    VARCHAR2(20);
  v_gran     NUMBER := 0;
BEGIN
  v_ultimo := CASE WHEN v_anio < EXTRACT(YEAR FROM SYSDATE) THEN 12 ELSE EXTRACT(MONTH FROM SYSDATE) END;
  v_tot('Efectivo') := 0;  v_tot('Datáfono') := 0;  v_tot('Transferencia') := 0;

  pkg_util.pl('==================================================================');
  pkg_util.pl(' R4. RECAUDO ' || v_anio || ' POR MES Y MEDIO DE PAGO (recibos no anulados)');
  pkg_util.pl('==================================================================');
  pkg_util.pl(RPAD('Mes', 12) || LPAD('Efectivo', 13) || LPAD('Datáfono', 13) || LPAD('Transferencia', 15)
              || LPAD('Recibos', 9) || LPAD('Total', 14));

  LOOP                                                                -- LOOP básico
    EXIT WHEN v_mes > v_ultimo;

    SELECT NVL(SUM(CASE mp.nombre WHEN 'Efectivo'      THEN p.valor END), 0),
           NVL(SUM(CASE mp.nombre WHEN 'Datáfono'      THEN p.valor END), 0),
           NVL(SUM(CASE mp.nombre WHEN 'Transferencia' THEN p.valor END), 0),
           COUNT(p.id)
      INTO v_m
      FROM pago p JOIN medio_pago mp ON mp.id = p.medio_pago_id
     WHERE p.anulado = 0
       AND p.fecha_pago >= ADD_MONTHS(TO_DATE(v_anio || '-01-01', 'YYYY-MM-DD'), v_mes - 1)
       AND p.fecha_pago <  ADD_MONTHS(TO_DATE(v_anio || '-01-01', 'YYYY-MM-DD'), v_mes);

    IF v_m.recibos > 0 THEN
      pkg_util.pl(RPAD(INITCAP(TO_CHAR(TO_DATE(v_mes, 'MM'), 'fmMonth', 'NLS_DATE_LANGUAGE=SPANISH')), 12)
                  || LPAD(pkg_util.fn_moneda(v_m.efectivo), 13) || LPAD(pkg_util.fn_moneda(v_m.datafono), 13)
                  || LPAD(pkg_util.fn_moneda(v_m.transferencia), 15) || LPAD(v_m.recibos, 9)
                  || LPAD(pkg_util.fn_moneda(v_m.efectivo + v_m.datafono + v_m.transferencia), 14));
    END IF;
    v_tot('Efectivo')      := v_tot('Efectivo')      + v_m.efectivo;
    v_tot('Datáfono')      := v_tot('Datáfono')      + v_m.datafono;
    v_tot('Transferencia') := v_tot('Transferencia') + v_m.transferencia;
    v_mes := v_mes + 1;
  END LOOP;

  pkg_util.pl(CHR(10) || 'Participación por medio de pago:');
  v_medio := v_tot.FIRST;
  WHILE v_medio IS NOT NULL LOOP
    v_gran  := v_gran + v_tot(v_medio);
    v_medio := v_tot.NEXT(v_medio);
  END LOOP;
  v_medio := v_tot.FIRST;
  WHILE v_medio IS NOT NULL LOOP
    pkg_util.pl('  ' || RPAD(v_medio, 15) || LPAD(pkg_util.fn_moneda(v_tot(v_medio)), 14)
                || LPAD(TO_CHAR(ROUND(100 * v_tot(v_medio) / NULLIF(v_gran, 0), 1), 'FM990.0'), 7) || ' %');
    v_medio := v_tot.NEXT(v_medio);
  END LOOP;
  pkg_util.pl('  ' || RPAD('TOTAL', 15) || LPAD(pkg_util.fn_moneda(v_gran), 14));
END;
/

-- ---------------------------------------------------------------------
-- R5. CANDIDATOS A DIPLOMA: estudiantes de II semestre sin diploma y qué les falta
-- ---------------------------------------------------------------------
DECLARE
  CURSOR c_candidatos IS
    SELECT DISTINCT m.estudiante_id, g.tecnico_id, t.codigo AS tecnico,
           e.cedula, e.apellidos || ' ' || e.nombres AS estudiante
      FROM matricula m
      JOIN grupo g      ON g.id = m.grupo_id
      JOIN tecnico t    ON t.id = g.tecnico_id
      JOIN estudiante e ON e.id = m.estudiante_id
     WHERE g.semestre = 2 AND m.estado <> 'Retirada'
       AND NOT EXISTS (SELECT 1 FROM diploma d
                        WHERE d.estudiante_id = m.estudiante_id AND d.tecnico_id = g.tecnico_id)
     ORDER BY t.codigo, estudiante;
  r          c_candidatos%ROWTYPE;
  v_aprob    NUMBER;
  v_pct      NUMBER;
  v_mora     NUMBER;
  v_aptos    PLS_INTEGER := 0;
  v_faltas   VARCHAR2(200);
BEGIN
  pkg_util.pl('==================================================================');
  pkg_util.pl(' R5. CANDIDATOS A DIPLOMA (8 competencias, 80 % asistencia, sin mora)');
  pkg_util.pl('==================================================================');

  OPEN c_candidatos;
  LOOP
    FETCH c_candidatos INTO r;
    EXIT WHEN c_candidatos%NOTFOUND;

    SELECT COUNT(DISTINCT k.competencia_id) INTO v_aprob
      FROM calificacion k JOIN matricula m ON m.id = k.matricula_id
      JOIN competencia c ON c.id = k.competencia_id
     WHERE m.estudiante_id = r.estudiante_id AND c.tecnico_id = r.tecnico_id AND k.nota >= 3;

    SELECT ROUND(100 * SUM(asistidas) / NULLIF(SUM(sesiones), 0), 1) INTO v_pct
      FROM v_asistencia_matricula
     WHERE estudiante_id = r.estudiante_id AND tecnico_id = r.tecnico_id AND estado_matricula <> 'Retirada';

    SELECT COUNT(*) INTO v_mora
      FROM v_estado_credito ec JOIN grupo g ON g.id = ec.grupo_id
     WHERE ec.estudiante_id = r.estudiante_id AND g.tecnico_id = r.tecnico_id AND ec.estado = 'En mora';

    v_faltas := NULL;
    IF v_aprob < 8 THEN
      v_faltas := v_faltas || (8 - v_aprob) || ' competencia(s) por aprobar; ';
    END IF;
    IF NVL(v_pct, 0) < 80 THEN
      v_faltas := v_faltas || 'asistencia ' || NVL(TO_CHAR(v_pct, 'FM990.0'), '0') || ' %; ';
    END IF;
    IF v_mora > 0 THEN
      v_faltas := v_faltas || 'en mora; ';
    END IF;

    IF v_faltas IS NULL THEN
      v_aptos := v_aptos + 1;
    END IF;
    pkg_util.pl(RPAD(r.tecnico, 5) || RPAD(r.cedula, 11) || RPAD(SUBSTR(r.estudiante, 1, 32), 33)
                || CASE WHEN v_faltas IS NULL THEN 'APTO para diploma'
                        ELSE 'Pendiente: ' || RTRIM(v_faltas, '; ') END);
  END LOOP;
  pkg_util.pl(CHR(10) || 'Revisados: ' || c_candidatos%ROWCOUNT || '   Aptos: ' || v_aptos);
  CLOSE c_candidatos;
EXCEPTION
  WHEN OTHERS THEN
    IF c_candidatos%ISOPEN THEN
      CLOSE c_candidatos;
    END IF;
    pkg_util.pl('Error en el reporte R5: ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- R6. LIQUIDACIÓN DE HONORARIOS DOCENTES POR PERIODO (hora cátedra)
--     Cada sesión registrada equivale a 2,5 horas (6:30 p. m. - 9:00 p. m.).
-- ---------------------------------------------------------------------
DECLARE
  v_periodo    periodo.codigo%TYPE := '2026-B';
  c_horas_ses  CONSTANT NUMBER := 2.5;
  v_dictadas   NUMBER;
  v_avance     NUMBER;
  v_total      NUMBER := 0;
  v_causado    NUMBER := 0;
  v_estado     VARCHAR2(25);
BEGIN
  pkg_util.pl('==================================================================');
  pkg_util.pl(' R6. HONORARIOS DOCENTES - PERIODO ' || v_periodo);
  pkg_util.pl('==================================================================');

  FOR d IN (SELECT d.id, d.apellidos || ' ' || d.nombres AS docente, c.horas_catedra, c.valor_hora
              FROM contrato_docente c
              JOIN docente d ON d.id = c.docente_id
              JOIN periodo p ON p.id = c.periodo_id
             WHERE p.codigo = v_periodo
             ORDER BY d.apellidos) LOOP

    SELECT COUNT(*) * c_horas_ses INTO v_dictadas
      FROM sesion_clase s JOIN grupo g ON g.id = s.grupo_id JOIN periodo p ON p.id = g.periodo_id
     WHERE g.docente_id = d.id AND p.codigo = v_periodo;

    BEGIN
      v_avance := ROUND(100 * v_dictadas / d.horas_catedra, 1);
    EXCEPTION
      WHEN ZERO_DIVIDE THEN v_avance := 0;
    END;

    v_estado := CASE
                  WHEN v_avance >= 100 THEN 'Contrato cumplido'
                  WHEN v_avance >= 50  THEN 'En ejecución'
                  WHEN v_avance > 0    THEN 'Inicio de ejecución'
                  ELSE 'Sin sesiones'
                END;

    pkg_util.pl(RPAD(SUBSTR(d.docente, 1, 30), 31) || LPAD(d.horas_catedra, 4) || ' h x '
                || LPAD(pkg_util.fn_moneda(d.valor_hora), 8) || ' = ' || LPAD(pkg_util.fn_moneda(d.horas_catedra * d.valor_hora), 11)
                || ' | dictadas ' || LPAD(TO_CHAR(v_dictadas, 'FM990.0'), 6) || ' h (' || TO_CHAR(v_avance, 'FM990.0') || ' %) '
                || 'causado ' || LPAD(pkg_util.fn_moneda(LEAST(v_dictadas, d.horas_catedra) * d.valor_hora), 10)
                || '  ' || v_estado);
    v_total   := v_total + d.horas_catedra * d.valor_hora;
    v_causado := v_causado + LEAST(v_dictadas, d.horas_catedra) * d.valor_hora;
  END LOOP;

  pkg_util.pl(CHR(10) || 'Valor total contratado: ' || pkg_util.fn_moneda(v_total));
  pkg_util.pl('Honorarios causados a la fecha: ' || pkg_util.fn_moneda(v_causado));
END;
/

-- ---------------------------------------------------------------------
-- R7. FACTURAS ELECTRÓNICAS PENDIENTES POR ANTIGÜEDAD
--     (la consulta usa el índice IX_PAGO_FACTURA)
-- ---------------------------------------------------------------------
DECLARE
  v_dias     NUMBER;
  v_rango    VARCHAR2(20);
  v_n        PLS_INTEGER := 0;
  v_valor    NUMBER := 0;
  v_vencidas PLS_INTEGER := 0;
BEGIN
  pkg_util.pl('==================================================================');
  pkg_util.pl(' R7. RECIBOS CON FACTURA ELECTRÓNICA PENDIENTE');
  pkg_util.pl('==================================================================');

  FOR p IN (SELECT p.numero_recibo, p.fecha_pago, p.valor, mp.nombre AS medio,
                   e.apellidos || ' ' || e.nombres AS estudiante
              FROM pago p
              JOIN medio_pago mp ON mp.id = p.medio_pago_id
              JOIN matricula m   ON m.id = p.matricula_id
              JOIN estudiante e  ON e.id = m.estudiante_id
             WHERE p.factura_estado = 'Pendiente' AND p.anulado = 0
             ORDER BY p.fecha_pago, p.numero_recibo) LOOP
    v_dias := TRUNC(SYSDATE) - p.fecha_pago;
    v_rango := CASE
                 WHEN v_dias <= 2  THEN 'A tiempo'
                 WHEN v_dias <= 7  THEN 'Atrasada'
                 ELSE 'Vencida'
               END;
    IF v_rango = 'Vencida' THEN
      v_vencidas := v_vencidas + 1;
    END IF;
    v_n := v_n + 1;
    v_valor := v_valor + p.valor;
    pkg_util.pl(RPAD(p.numero_recibo, 7) || pkg_util.fn_fecha(p.fecha_pago) || '  '
                || LPAD(pkg_util.fn_moneda(p.valor), 9) || '  ' || RPAD(p.medio, 14)
                || RPAD(SUBSTR(p.estudiante, 1, 28), 29) || LPAD(v_dias, 4) || ' días  ' || v_rango);
  END LOOP;

  pkg_util.pl(CHR(10) || v_n || ' recibos sin facturar por ' || pkg_util.fn_moneda(v_valor)
              || ' (' || v_vencidas || ' con más de 7 días)');
END;
/
