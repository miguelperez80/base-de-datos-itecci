-- =====================================================================
-- ITECCI - Avance PL/SQL
-- PRUEBAS.sql : evidencia de excepciones (d), triggers (g), formato (k) y paquetes CRUD (b)
-- Ejecutar como ITECCI después de DDL.sql y DATOS.sql.
-- Cada prueba termina en ROLLBACK: la base de datos queda igual (solo avanzan las secuencias).
-- Resultado esperado: cada prueba de error imprime "OK -> ORA-20xxx: ..." con el mensaje de la regla.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- P1. Trigger de formato (T1, regla k): teléfono con formato inválido
-- ---------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pkg_util.pl('P1. Teléfono inválido');
  pkg_estudiante.insertar(p_cedula => '1099000001', p_nombres => 'Laura', p_apellidos => 'Prueba Formato',
    p_fecha_nac => DATE '2000-05-10', p_telefono => '12345', p_email => 'laura@correo.com',
    p_direccion => 'Cra 1 # 2-3', p_ocupacion => 'Empleado', p_regimen_salud => 'Contributivo',
    p_estrato => 2, p_estado_civil => 'Soltero', p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P2. Excepción DUP_VAL_ON_INDEX: cédula que ya existe
-- ---------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pkg_util.pl('P2. Cédula duplicada');
  pkg_estudiante.insertar(p_cedula => '1017821631', p_nombres => 'Jessica', p_apellidos => 'Duplicada',
    p_fecha_nac => DATE '1995-01-01', p_telefono => '3001234567', p_email => 'dup@correo.com',
    p_direccion => 'Calle 1', p_ocupacion => 'Empleado', p_regimen_salud => 'Subsidiado',
    p_estrato => 1, p_estado_civil => 'Soltero', p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P3. Excepción con PRAGMA EXCEPTION_INIT (-2290, CHECK): estrato fuera de dominio
-- ---------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pkg_util.pl('P3. Estrato 9 (CHECK)');
  pkg_estudiante.insertar(p_cedula => '1099000002', p_nombres => 'Mario', p_apellidos => 'Prueba Check',
    p_fecha_nac => DATE '1990-03-15', p_telefono => '3101234567', p_email => 'mario@correo.com',
    p_direccion => 'Calle 2', p_ocupacion => 'Empleado', p_regimen_salud => 'Subsidiado',
    p_estrato => 9, p_estado_civil => 'Soltero', p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P4. Excepción NO_DATA_FOUND: consultar una cédula inexistente
-- ---------------------------------------------------------------------
DECLARE
  v_est estudiante%ROWTYPE;
BEGIN
  pkg_util.pl('P4. Estudiante inexistente');
  v_est := pkg_estudiante.consultar('999999999');
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- P5. Excepción con PRAGMA EXCEPTION_INIT (-2292, registros hijos): borrar estudiante con matrículas
-- ---------------------------------------------------------------------
BEGIN
  pkg_util.pl('P5. Eliminar estudiante con matrículas');
  pkg_estudiante.eliminar(1);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P6. Excepción de usuario (e_nota_invalida): nota 6.0
-- ---------------------------------------------------------------------
DECLARE
  v_mat NUMBER;
  v_id  NUMBER;
BEGIN
  pkg_util.pl('P6. Nota fuera de escala');
  SELECT MIN(id) INTO v_mat FROM matricula WHERE grupo_id = 9 AND estado = 'Activa';
  pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => 5, p_nota => 6, p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P7. Trigger T2: tercer día de clase para un grupo (RN-07)
-- ---------------------------------------------------------------------
BEGIN
  pkg_util.pl('P7. Tercer día de horario para SIS-2026B-S2');
  INSERT INTO horario_grupo (id, grupo_id, dia_semana) VALUES (seq_horario_grupo.NEXTVAL, 9, 5);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P8. Trigger T3: calificar una competencia de otro técnico
-- ---------------------------------------------------------------------
DECLARE
  v_mat NUMBER;
BEGIN
  pkg_util.pl('P8. Competencia de Comercio Exterior en un grupo de Sistemas');
  SELECT MIN(id) INTO v_mat FROM matricula WHERE grupo_id = 9 AND estado = 'Activa';
  INSERT INTO calificacion (id, matricula_id, competencia_id, tipo, nota, fecha)
  VALUES (seq_calificacion.NEXTVAL, v_mat, 9, 'Ordinaria', 4, TRUNC(SYSDATE));
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P9. Trigger T4: supletorio de una competencia que se aprobó (RN-22)
-- ---------------------------------------------------------------------
DECLARE
  v_mat  NUMBER;
  v_comp NUMBER;
  v_id   NUMBER;
BEGIN
  pkg_util.pl('P9. Supletorio sin haber perdido');
  SELECT k.matricula_id, k.competencia_id INTO v_mat, v_comp
    FROM calificacion k JOIN matricula m ON m.id = k.matricula_id
   WHERE k.tipo = 'Ordinaria' AND k.nota >= 3 AND m.estado <> 'Retirada' AND ROWNUM = 1;
  pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => v_comp, p_nota => 4,
                             p_tipo => 'Supletorio', p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P10. Trigger T5: modificar o anular un recibo con factura emitida (RN-18)
-- ---------------------------------------------------------------------
BEGIN
  pkg_util.pl('P10a. Cambiar el valor de un recibo facturado');
  UPDATE pago SET valor = 1000 WHERE id = 1;
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/
BEGIN
  pkg_util.pl('P10b. Anular un recibo facturado');
  UPDATE pago SET anulado = 1 WHERE id = 1;
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P11. Trigger T6: diploma a un estudiante que no cumple requisitos (RN-23/24/25)
-- ---------------------------------------------------------------------
DECLARE
  v_est NUMBER;
  v_num VARCHAR2(20);
BEGIN
  pkg_util.pl('P11. Diploma sin cumplir requisitos');
  SELECT MIN(estudiante_id) INTO v_est FROM matricula WHERE grupo_id = 17;
  pkg_certificacion.emitir_diploma(v_est, 2, 1, v_num);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P12. PKG_GRUPO: aula ocupada (RN-08). En 2026-B las 3 aulas están llenas de lunes a sábado.
-- ---------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pkg_util.pl('P12. Crear grupo en un aula ocupada');
  pkg_grupo.crear(p_tecnico => 1, p_periodo => 4, p_semestre => 1, p_docente => 1,
                  p_aula => 1, p_dia1 => 1, p_dia2 => 3, p_id => v_id);
  pkg_util.pl('   FALLÓ: se esperaba error');
EXCEPTION
  WHEN OTHERS THEN pkg_util.pl('   OK -> ' || SQLERRM);  ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P13. FLUJO COMPLETO EXITOSO: estudiante -> documentos -> matrícula -> pago -> factura -> notas
--      Evidencia: normalización de formato (T1), numeración de recibo y factura (secuencias),
--      auditoría (T7), prerrequisito RN-04, supletorio (T4), boletín y ficha.
-- ---------------------------------------------------------------------
DECLARE
  v_id    NUMBER;
  v_mat   NUMBER;
  v_cal   NUMBER;
  v_est   estudiante%ROWTYPE;
  v_rec   VARCHAR2(20);
  v_fact  pago.factura_numero%TYPE;
BEGIN
  pkg_util.pl('P13. Flujo completo');

  pkg_estudiante.insertar(p_cedula => ' 1099000003 ', p_nombres => '  juan   CARLOS ', p_apellidos => 'pérez   mera',
    p_fecha_nac => DATE '1998-08-20', p_telefono => '320 123 4567', p_email => '  Juan.Perez@Correo.COM ',
    p_direccion => 'Cra 6 # 10-20, Centro', p_ocupacion => 'Empleado', p_regimen_salud => 'Contributivo',
    p_estrato => 2, p_estado_civil => 'Soltero', p_autoriza => 1, p_id => v_id);
  v_est := pkg_estudiante.consultar('1099000003');
  pkg_util.pl('   Normalizado por T1: "' || v_est.nombres || ' ' || v_est.apellidos || '" tel ' || v_est.telefono
              || ' ' || v_est.email || ' autorizó el ' || pkg_util.fn_fecha(v_est.fecha_autorizacion));

  pkg_estudiante.registrar_documento(v_id, 'Cédula');
  pkg_estudiante.registrar_documento(v_id, 'Diploma de bachiller');

  sp_matricular(v_id, 17, 2);
  SELECT id INTO v_mat FROM matricula WHERE estudiante_id = v_id;
  pkg_util.pl('   Matrícula ' || v_mat || ' creada; saldo ' || pkg_util.fn_moneda(pkg_util.fn_saldo(v_mat)));

  v_rec := pkg_util.fn_siguiente_recibo;
  sp_registrar_pago(v_mat, v_rec, 220000, 3, 2);
  pkg_util.pl('   Recibo ' || v_rec || ' por ' || pkg_util.fn_moneda(220000)
              || '; saldo ' || pkg_util.fn_moneda(pkg_util.fn_saldo(v_mat)));

  UPDATE pago SET factura_estado = 'Emitida' WHERE numero_recibo = v_rec;
  SELECT factura_numero INTO v_fact FROM pago WHERE numero_recibo = v_rec;
  pkg_util.pl('   Factura asignada por T5: ' || v_fact);

  FOR a IN (SELECT operacion, detalle FROM auditoria
             WHERE tabla = 'PAGO' AND registro_id = (SELECT id FROM pago WHERE numero_recibo = v_rec)
             ORDER BY id) LOOP
    pkg_util.pl('   Auditoría T7: ' || a.operacion || ' - ' || a.detalle);
  END LOOP;

  pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => 9, p_nota => 2.5, p_id => v_cal);
  BEGIN
    pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => 10, p_nota => 4, p_id => v_cal);
  EXCEPTION
    WHEN OTHERS THEN pkg_util.pl('   Esperado -> ' || SQLERRM);
  END;
  pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => 9, p_nota => 3.5, p_tipo => 'Supletorio', p_id => v_cal);
  pkg_calificacion.registrar(p_matricula => v_mat, p_competencia => 10, p_nota => 4, p_id => v_cal);

  pkg_calificacion.boletin(v_mat);
  pkg_estudiante.imprimir_ficha('1099000003');

  ROLLBACK;
  pkg_util.pl('   ROLLBACK aplicado');
EXCEPTION
  WHEN OTHERS THEN
    pkg_util.pl('   ERROR inesperado -> ' || SQLERRM);
    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P14. CRUD de PKG_DOCENTE y PKG_GRUPO en un periodo nuevo (2027-A)
-- ---------------------------------------------------------------------
DECLARE
  v_per   NUMBER;
  v_grupo NUMBER;
BEGIN
  pkg_util.pl('P14. CRUD docente y grupo');
  SELECT seq_periodo.NEXTVAL INTO v_per FROM dual;
  INSERT INTO periodo (id, anio, calendario, codigo, fecha_inicio, fecha_fin)
  VALUES (v_per, 2027, 'A', '2027-A', DATE '2027-02-01', DATE '2027-06-11');

  pkg_docente.registrar_contrato(1, v_per, 80, 26000);
  pkg_docente.actualizar(p_id => 1, p_email => NULL, p_telefono => '3101000099', p_nivel => NULL, p_exp => 7);
  pkg_docente.consultar(1);

  pkg_grupo.crear(p_tecnico => 1, p_periodo => v_per, p_semestre => 1, p_docente => 1,
                  p_aula => 1, p_dia1 => 1, p_dia2 => 3, p_id => v_grupo);
  pkg_grupo.consultar(v_grupo);

  BEGIN
    pkg_grupo.cambiar_estado(v_grupo, 'Activo');
  EXCEPTION
    WHEN OTHERS THEN pkg_util.pl('   Esperado -> ' || SQLERRM);
  END;

  pkg_grupo.eliminar(v_grupo);
  pkg_docente.eliminar(1);
  ROLLBACK;
  pkg_util.pl('   ROLLBACK aplicado');
EXCEPTION
  WHEN OTHERS THEN
    pkg_util.pl('   ERROR inesperado -> ' || SQLERRM);
    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P15. Funciones de formato (regla k) y ZERO_DIVIDE controlado
-- ---------------------------------------------------------------------
DECLARE
  v_mat NUMBER;
BEGIN
  pkg_util.pl('P15. Formatos');
  pkg_util.pl('   Moneda:      ' || pkg_util.fn_moneda(18800000));
  pkg_util.pl('   Fecha:       ' || pkg_util.fn_fecha(DATE '2026-10-05'));
  pkg_util.pl('   Fecha larga: ' || pkg_util.fn_fecha_larga(DATE '2026-10-05'));
  pkg_util.pl('   Nota:        ' || pkg_util.fn_nota(3));
  SELECT MIN(id) INTO v_mat FROM matricula WHERE grupo_id = 17;
  pkg_util.pl('   % asistencia matrícula ' || v_mat || ': ' || NVL(TO_CHAR(pkg_util.fn_pct_asistencia(v_mat)), 'sin sesiones (ZERO_DIVIDE controlado)'));
END;
/

-- Consulta de la vista nueva (h)
SELECT g.codigo AS grupo, COUNT(*) AS matriculas,
       ROUND(AVG(v.porcentaje), 1) AS asistencia_promedio,
       SUM(CASE WHEN v.estado_asistencia = 'No cumple' THEN 1 ELSE 0 END) AS no_cumplen
  FROM v_asistencia_matricula v JOIN grupo g ON g.id = v.grupo_id
 WHERE v.estado_matricula <> 'Retirada'
 GROUP BY g.codigo
 ORDER BY g.codigo;
