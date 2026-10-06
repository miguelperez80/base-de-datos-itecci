-- =====================================================================
-- 05_roles_permisos.sql : privilegios sobre los objetos. Ejecutar como ITECCI, después de crear tablas y vistas.
-- Coordinador General: lectura y escritura sobre todo.  Secretaria: matrícula, pagos y consulta.
-- =====================================================================
SET SERVEROUTPUT ON
-- Solo se otorgan permisos sobre los objetos del proyecto (se ignoran vistas/tablas internas de la extensión de VS Code)
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('TECNICO','COMPETENCIA','PERIODO','AULA','USUARIO','DOCENTE','DOCENTE_FORMACION',
                                  'CONTRATO_DOCENTE','GRUPO','HORARIO_GRUPO','ESTUDIANTE','DOCUMENTO_ESTUDIANTE',
                                  'MATRICULA','MEDIO_PAGO','CUOTA','PAGO','APLICACION_PAGO','SESION_CLASE',
                                  'ASISTENCIA','CALIFICACION','DIPLOMA')) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO rol_coordinador';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || t.table_name || ' TO rol_secretaria';
  END LOOP;
  FOR v IN (SELECT view_name FROM user_views WHERE view_name IN ('V_ESTADO_CREDITO','V_BOLETIN')) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || v.view_name || ' TO rol_coordinador';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || v.view_name || ' TO rol_secretaria';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || s.sequence_name || ' TO rol_coordinador';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || s.sequence_name || ' TO rol_secretaria';
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Permisos otorgados.');
END;
/

-- La secretaria solo escribe en las tablas de su proceso (no en catálogos, docentes, diplomas ni usuarios)
GRANT INSERT, UPDATE ON estudiante            TO rol_secretaria;
GRANT INSERT, UPDATE ON documento_estudiante  TO rol_secretaria;
GRANT INSERT, UPDATE ON matricula             TO rol_secretaria;
GRANT INSERT, UPDATE ON cuota                 TO rol_secretaria;
GRANT INSERT, UPDATE ON pago                  TO rol_secretaria;
GRANT INSERT         ON aplicacion_pago       TO rol_secretaria;
GRANT INSERT, UPDATE ON sesion_clase          TO rol_secretaria;
GRANT INSERT, UPDATE ON asistencia            TO rol_secretaria;
GRANT INSERT, UPDATE ON calificacion          TO rol_secretaria;
GRANT EXECUTE ON sp_matricular     TO rol_secretaria;
GRANT EXECUTE ON sp_registrar_pago TO rol_secretaria;
GRANT EXECUTE ON sp_matricular     TO rol_coordinador;
GRANT EXECUTE ON sp_registrar_pago TO rol_coordinador;

-- La secretaria no ve los hashes de contraseña
REVOKE SELECT ON usuario FROM rol_secretaria;

-- Para trabajar con los nombres sin prefijo (opcional, como DBA):  CREATE PUBLIC SYNONYM ... o ALTER SESSION SET CURRENT_SCHEMA = itecci;