-- =====================================================================
-- 06_consultas.sql : consultas SQL de evidencia (Oracle 11g/18c)
-- Ejecutar como ITECCI.  Requiere 02_ddl.sql, 03_dml.sql y 04_plsql_vistas.sql.
-- =====================================================================
SET LINESIZE 200 PAGESIZE 60
SET DEFINE OFF

-- =====================================================================
-- A. RESTRICCIONES / FILTROS (WHERE)
-- =====================================================================

-- A1. Igualdad (=): estudiantes de estrato 3 que son independientes
SELECT cedula, nombres, apellidos, ocupacion
  FROM estudiante
 WHERE estrato = 3 AND ocupacion = 'Independiente'
 ORDER BY apellidos;

-- A2. Diferente (<>): matrículas del periodo 2026-A cuyo estado no es 'Finalizada' (es decir, estudiantes retirados)
SELECT m.id AS matricula, m.estado, g.codigo AS grupo
  FROM matricula m JOIN grupo g ON g.id = m.grupo_id
 WHERE m.estado <> 'Finalizada' AND g.periodo_id = 3
 ORDER BY g.codigo, m.id;

-- A3. BETWEEN: recibos de caja del 16 al 17 de septiembre de 2026 con valor entre 100.000 y 220.000
SELECT numero_recibo, fecha_pago, valor, medio_pago_id
  FROM pago
 WHERE fecha_pago BETWEEN DATE '2026-09-16' AND DATE '2026-09-17'
   AND valor BETWEEN 100000 AND 220000
 ORDER BY fecha_pago, numero_recibo;

-- A4. LIKE: estudiantes cuyo apellido comienza por "Cu" y competencias que contienen la palabra "contable"
SELECT cedula, apellidos, nombres FROM estudiante WHERE apellidos LIKE 'Cu%' ORDER BY apellidos, nombres;
SELECT id, nombre FROM competencia WHERE LOWER(nombre) LIKE '%contable%' ORDER BY id;

-- A5. IN: grupos del periodo 2026-B de los técnicos de Sistemas (1), Contabilidad (5) y Diseño (6)
SELECT codigo, semestre, estado
  FROM grupo
 WHERE periodo_id = 4 AND tecnico_id IN (1, 5, 6)
 ORDER BY codigo;

-- A6. IS NULL: recibos de caja sin factura electrónica emitida (factura_numero nulo)
SELECT numero_recibo, fecha_pago, valor, factura_estado
  FROM pago
 WHERE factura_numero IS NULL
 ORDER BY fecha_pago, numero_recibo;

-- A7. IS NOT NULL: estudiantes que reportaron una condición médica
SELECT cedula, nombres, apellidos, condicion_medica
  FROM estudiante
 WHERE condicion_medica IS NOT NULL
 ORDER BY apellidos;

-- =====================================================================
-- B. JOINS
-- =====================================================================

-- B1. CROSS JOIN: oferta posible (todos los técnicos x todos los periodos) frente a los grupos realmente abiertos
SELECT t.codigo AS tecnico, p.codigo AS periodo,
       (SELECT COUNT(*) FROM grupo g WHERE g.tecnico_id = t.id AND g.periodo_id = p.id) AS grupos_abiertos
  FROM tecnico t CROSS JOIN periodo p
 ORDER BY p.codigo, t.codigo;

-- B2. INNER JOIN: estudiantes matriculados en el periodo 2026-B con su técnico, grupo, docente y aula
SELECT e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, t.nombre AS tecnico, g.codigo AS grupo,
       d.apellidos || ' ' || d.nombres AS docente, a.nombre AS aula
  FROM matricula m
  INNER JOIN estudiante e ON e.id = m.estudiante_id
  INNER JOIN grupo g      ON g.id = m.grupo_id
  INNER JOIN tecnico t    ON t.id = g.tecnico_id
  INNER JOIN docente d    ON d.id = g.docente_id
  INNER JOIN aula a       ON a.id = g.aula_id
 WHERE g.periodo_id = 4 AND g.codigo = 'CON-2026B-S1'
 ORDER BY e.apellidos, e.nombres;

-- B3. LEFT JOIN: todos los estudiantes de Sistemas y su diploma (NULL = aún no se ha graduado)
SELECT e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, d.numero_diploma, d.fecha_emision
  FROM estudiante e
  INNER JOIN matricula m ON m.estudiante_id = e.id
  INNER JOIN grupo g     ON g.id = m.grupo_id AND g.tecnico_id = 1 AND g.codigo = 'SIS-2025A-S1'
  LEFT JOIN diploma d    ON d.estudiante_id = e.id AND d.tecnico_id = 1
 ORDER BY d.numero_diploma, e.apellidos;

-- B4. RIGHT JOIN: competencias del técnico de Comercio Exterior que aún no tienen ninguna calificación registrada
SELECT c.orden, c.nombre AS competencia_sin_notas
  FROM calificacion k
  RIGHT JOIN competencia c ON c.id = k.competencia_id AND k.tipo = 'Ordinaria'
 WHERE c.tecnico_id = 2 AND k.id IS NULL
 ORDER BY c.orden;

-- =====================================================================
-- C. AGRUPACIÓN (GROUP BY / HAVING)
-- =====================================================================

-- C1. Matriculados por grupo en el periodo 2026-B; solo grupos con 19 o más estudiantes
SELECT g.codigo AS grupo, COUNT(*) AS matriculados
  FROM matricula m JOIN grupo g ON g.id = m.grupo_id
 WHERE g.periodo_id = 4
 GROUP BY g.codigo
HAVING COUNT(*) >= 19
 ORDER BY g.codigo;

-- C2. Recaudo por medio de pago desde julio de 2026; solo medios con más de 100 recibos
SELECT mp.nombre AS medio_pago, COUNT(*) AS recibos, SUM(p.valor) AS recaudado, ROUND(AVG(p.valor), 0) AS promedio
  FROM pago p JOIN medio_pago mp ON mp.id = p.medio_pago_id
 WHERE p.anulado = 0 AND p.fecha_pago >= DATE '2026-07-01'
 GROUP BY mp.nombre
HAVING COUNT(*) > 100
 ORDER BY recaudado DESC;

-- C3. Promedio de notas y reprobados por competencia del técnico de Sistemas (solo notas ordinarias)
SELECT c.orden, c.nombre AS competencia, COUNT(*) AS notas, ROUND(AVG(k.nota), 2) AS promedio,
       SUM(CASE WHEN k.nota < 3 THEN 1 ELSE 0 END) AS perdieron
  FROM calificacion k JOIN competencia c ON c.id = k.competencia_id
 WHERE c.tecnico_id = 1 AND k.tipo = 'Ordinaria'
 GROUP BY c.orden, c.nombre
 ORDER BY c.orden;

-- =====================================================================
-- D. ORDENAMIENTOS
-- =====================================================================

-- D1. Fila simple, ORDER BY simple: docentes por apellido
SELECT apellidos, nombres, nivel_formacion, anios_experiencia_docencia
  FROM docente
 ORDER BY apellidos;

-- D2. Fila simple, ORDER BY múltiple: estudiantes por estrato (mayor a menor) y luego por apellido y nombre
SELECT estrato, apellidos, nombres, ocupacion
  FROM estudiante
 WHERE estrato >= 3
 ORDER BY estrato DESC, apellidos ASC, nombres ASC;

-- D3. Con función de grupo: técnicos ordenados por cantidad de matrículas (de más a menos)
SELECT t.nombre AS tecnico, COUNT(m.id) AS matriculas
  FROM tecnico t
  JOIN grupo g ON g.tecnico_id = t.id
  JOIN matricula m ON m.grupo_id = g.id
 GROUP BY t.nombre
 ORDER BY COUNT(m.id) DESC, t.nombre;

-- D4. Con función de grupo: grupos ordenados por el valor total recaudado (SUM) de mayor a menor
SELECT g.codigo AS grupo, COUNT(DISTINCT m.id) AS matriculas, SUM(p.valor) AS recaudado
  FROM grupo g
  JOIN matricula m ON m.grupo_id = g.id
  JOIN pago p ON p.matricula_id = m.id
 WHERE p.anulado = 0
 GROUP BY g.codigo
 ORDER BY SUM(p.valor) DESC, g.codigo;

-- =====================================================================
-- E. CONSULTA INTEGRADORA: ESTADO DE CRÉDITO (vista v_estado_credito)
-- =====================================================================

-- E1. Estudiantes en mora del periodo 2026-B, de mayor a menor mora
SELECT e.cedula, e.apellidos || ' ' || e.nombres AS estudiante, e.telefono, g.codigo AS grupo,
       ec.saldo, ec.cuotas_vencidas, ec.dias_mora
  FROM v_estado_credito ec
  JOIN estudiante e ON e.id = ec.estudiante_id
  JOIN grupo g ON g.id = ec.grupo_id
 WHERE ec.estado = 'En mora' AND g.periodo_id = 4
 ORDER BY ec.dias_mora DESC, ec.saldo DESC, e.apellidos;

-- E2. Resumen de cartera por estado
SELECT estado, COUNT(*) AS matriculas, SUM(saldo) AS saldo_total
  FROM v_estado_credito
 GROUP BY estado
 ORDER BY estado;
