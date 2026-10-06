-- =====================================================================
-- 00_limpiar.sql : (OPCIONAL) borra los objetos del proyecto ITECCI para repetir las pruebas desde cero.
-- Ejecutar conectado como ITECCI. Solo toca los 21 objetos del proyecto; ignora cualquier otra tabla
-- (por ejemplo tablas internas que crea la extensión de VS Code, como DBTOOLS$...).
-- Cada DROP va protegido: si uno falla, se muestra el nombre y el script continúa.
-- =====================================================================
SET SERVEROUTPUT ON
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('TECNICO','COMPETENCIA','PERIODO','AULA','USUARIO','DOCENTE','DOCENTE_FORMACION',
                                  'CONTRATO_DOCENTE','GRUPO','HORARIO_GRUPO','ESTUDIANTE','DOCUMENTO_ESTUDIANTE',
                                  'MATRICULA','MEDIO_PAGO','CUOTA','PAGO','APLICACION_PAGO','SESION_CLASE',
                                  'ASISTENCIA','CALIFICACION','DIPLOMA')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS';
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
  FOR v IN (SELECT view_name FROM user_views WHERE view_name IN ('V_ESTADO_CREDITO','V_BOLETIN')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP VIEW "' || v.view_name || '"';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar vista ' || v.view_name || ': ' || SQLERRM);
    END;
  END LOOP;
  FOR p IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type = 'PROCEDURE' AND object_name IN ('SP_GENERAR_PLAN_PAGOS','SP_MATRICULAR','SP_REGISTRAR_PAGO')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP PROCEDURE "' || p.object_name || '"';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No se pudo borrar procedimiento ' || p.object_name || ': ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Limpieza terminada.');
END;
/