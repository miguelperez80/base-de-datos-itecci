# ITECCI · Gestión académica y de cartera

Proyecto final de Laboratorio de Bases de Datos II – Universidad del Cauca. Autor: Miguel Ángel Pérez.

Sistema para el Instituto Técnico Empresarial de la Cámara de Comercio de Ipiales (ITECCI): estudiantes, matrículas, recibos de caja, cartera, grupos, programas y docentes, sobre Oracle.

- **Interfaz publicada:** <https://miguelperez80.github.io/base-de-datos-itecci/> (solo el frontend; ver [GitHub Pages](#github-pages))

## Cómo ejecutarlo

**Opción rápida:** doble clic en `iniciar.bat`. Enciende el listener de Oracle si hace falta (pide permiso de administrador), abre el backend y el frontend, y lanza el navegador en <http://localhost:5173>.

**Manual**, en dos terminales:

```
cd backend          cd frontend
npm install         npm install
npm start           npm run dev
```

Abra siempre `http://localhost:5173` (no `127.0.0.1`): el backend solo acepta ese origen.

| Usuario | Contraseña | Rol |
|---|---|---|
| `coordinador` | `Coord2026#` | Coordinador General: acceso total |
| `secretaria` | `Secre2026#` | Secretaría: estudiantes, matrículas, pagos y cartera |

Son claves de demostración. Para cambiarlas: `npm run seed:usuarios -- <usuario> <clave nueva>` dentro de `backend/`.

### Requisitos

- Node.js 20 o superior.
- Oracle Database 12.2 o superior (probado en 23ai Free, servicio `freepdb1`), con el servicio de la base y el listener iniciados.
- `backend/.env` con los datos de conexión (plantilla en `backend/.env.example`).

### Reconstruir la base de datos

La base se reconstruye completa con **dos scripts**, como pide la guía:

| Script | Contenido |
|---|---|
| `DDL.sql` | Toda la definición: 22 tablas con sus restricciones, índices, secuencias, vistas, procedimientos, paquetes y triggers, más los permisos de los roles. Empieza borrando lo que exista, así que se puede volver a ejecutar |
| `DATOS.sql` | Los `INSERT` de los datos de prueba (≈10.500 registros en 21 tablas) |

Antes, una sola vez y como SYSTEM, `USUARIOS.sql` crea el usuario `itecci` y los roles. Luego, como `itecci`, se ejecuta `DDL.sql` y después `DATOS.sql` (en SQL Developer con F5), o los dos de una vez con `instalar.sql`:

```
$env:NLS_LANG = 'AMERICAN_AMERICA.AL32UTF8'
sqlplus itecci/"Itecci2026#"@localhost:1521/freepdb1 @instalar.sql
```

`NLS_LANG` en UTF-8 es necesario para que las tildes y eñes de los scripts se carguen bien.

### GitHub Pages

GitHub Pages solo sirve archivos estáticos, así que allí está únicamente el frontend. La base de datos y la API siguen en el equipo: el enlace funciona completo cuando el backend está encendido en ese mismo equipo (el navegador puede pedir permiso para acceder a la red local) y en otro equipo solo muestra la pantalla de ingreso.

El backend acepta ese origen porque está en `FRONTEND_ORIGIN` (`backend/.env`, valores separados por coma). Para volver a publicar: `npm run build:pages` en `frontend/` y subir `dist/` a la rama `gh-pages`.

## Arquitectura

Frontend y backend son dos proyectos independientes que se comunican por una API REST en `localhost`.

```
Navegador (React, :5173) ──HTTP/JSON + cookie──> API Express (:3000) ──node-oracledb──> Oracle (paquetes PL/SQL)
```

```
├── *.sql                    Base de datos (ver tabla abajo)
├── docs/                    Documento del proyecto y modelos conceptual y físico
├── backend/                 API REST · Node + Express
│   └── src/
│       ├── config/          Variables de entorno validadas y pool de conexiones
│       ├── routes/          Rutas, permisos por rol y validación de cada una
│       ├── controllers/     HTTP <-> servicio (sin reglas ni SQL)
│       ├── services/        Lógica de aplicación
│       ├── repositories/    Único acceso a Oracle: llamadas a paquetes PL/SQL
│       ├── validators/      Esquemas de validación de entrada (Zod)
│       ├── middlewares/     Autenticación, autorización, validación, errores
│       ├── utils/           AppError, traducción de errores ORA-, registro
│       └── container.js     Raíz de composición (inyección de dependencias)
└── frontend/                Interfaz · React + Vite
    └── src/
        ├── api/             Cliente HTTP (único módulo que usa fetch)
        ├── context/         Sesión y avisos
        ├── layouts/         MainLayout: la página maestra
        ├── components/      Tabla, Formulario, Modal, CrudPage (CRUD genérico)
        ├── pages/           Una pantalla por módulo
        └── styles/          Paleta institucional y estilos
```

**MVC:** el modelo son los repositorios y los paquetes PL/SQL; los controladores están en `backend/src/controllers`; la vista es el proyecto `frontend`.

### Scripts de base de datos

| Script | Usuario | Contenido |
|---|---|---|
| `USUARIOS.sql` | SYSTEM | Usuario `itecci` y roles `rol_coordinador` y `rol_secretaria` (una sola vez) |
| **`DDL.sql`** | ITECCI | **Definición completa:** 22 tablas, restricciones, índices, secuencias, vistas, procedimientos, paquetes (`PKG_*` del avance y `PKG_API_*` de la aplicación), 10 triggers y permisos |
| **`DATOS.sql`** | ITECCI | **Datos de prueba:** ≈10.500 `INSERT` |
| `CONSULTAS.sql` | ITECCI | Consultas SQL de evidencia (punto 1): filtros, JOINs, ordenamientos, agrupación, subconsultas |
| `REPORTES.sql` | ITECCI | **Avance PL/SQL:** 7 bloques anónimos de reporte |
| `PRUEBAS.sql` | ITECCI | **Avance PL/SQL:** pruebas de excepciones, triggers y CRUD (terminan en ROLLBACK) |
| `DICCIONARIO.sql` | ITECCI | **Avance PL/SQL:** consultas al diccionario de datos |
| `instalar.sql` | ITECCI | Ejecuta `DDL.sql` y `DATOS.sql` desde SQL*Plus |

Antes de `REPORTES.sql` y `PRUEBAS.sql` active la salida: `SET SERVEROUTPUT ON` (ya viene en los scripts; en SQL Developer, *Ver → Salida de DBMS*).

**Cómo conviven el avance y la aplicación.** Los paquetes del avance (`PKG_ESTUDIANTE`, `PKG_DOCENTE`, `PKG_GRUPO`, `PKG_CALIFICACION`, `PKG_CERTIFICACION`, `PKG_UTIL`) se conservan tal cual: imprimen por `DBMS_OUTPUT` y se prueban desde SQL. La API necesita cursores paginados y parámetros de salida, así que usa paquetes aparte con prefijo `PKG_API_`. Las reglas no se duplican: todo lo que la aplicación escribe pasa por los triggers del avance, por `SP_MATRICULAR` y `SP_REGISTRAR_PAGO`, y el número de recibo sale de `PKG_UTIL.fn_siguiente_recibo`.

## Mapa de requisitos del avance PL/SQL (punto 2)

| Req. | Requisito | Dónde está |
|---|---|---|
| a | Bloques anónimos de reporte (mín. 5) | `REPORTES.sql`: R1 cartera en mora, R2 boletín, R3 asistencia, R4 recaudo mensual, R5 candidatos a diploma, R6 honorarios docentes, R7 facturas pendientes |
| b | Paquetes CRUD (mín. 4) | `PKG_ESTUDIANTE`, `PKG_DOCENTE`, `PKG_GRUPO`, `PKG_CALIFICACION` (+ `PKG_CERTIFICACION`, `PKG_UTIL`) |
| c | IF, CASE, WHILE, FOR, LOOP | IF/ELSIF en todos; CASE en R1, R2, R6, T1, `cambiar_estado`; WHILE en R3 y R4; FOR numérico en R3 y `pkg_docente.consultar`; LOOP/EXIT WHEN en R4 y R5 |
| d | Excepciones (mín. 5) | NO_DATA_FOUND, DUP_VAL_ON_INDEX, TOO_MANY_ROWS, ZERO_DIVIDE, OTHERS, PRAGMA EXCEPTION_INIT (-2290, -2291, -2292), excepciones de usuario, RAISE_APPLICATION_ERROR (-20100…-20251) |
| e | Cursores (mín. 4, uno con parámetros) | `c_grupos(p_periodo)` y `c_morosos(p_grupo)` en R1; `c_matriculas(p_estudiante)`; `c_horario(p_grupo)`; explícito OPEN/FETCH/CLOSE en R5; REF CURSOR en `pkg_estudiante.buscar` |
| f | RECORD, TABLE, BULK COLLECT | RECORD `t_contrato`, `t_asistencia`, `t_mes`; TABLE INDEX BY PLS_INTEGER y BY VARCHAR2; BULK COLLECT en R3 y `pkg_docente.contratos`; VARRAY `t_dias`; `%ROWTYPE` |
| g | Triggers de reglas de negocio (mín. 4) | 10 triggers en `DDL.sql`: 7 del avance (sección 4) y 3 complementarios (sección 5) |
| h | Vista | `V_ASISTENCIA_MATRICULA` |
| i | Diccionario de datos (tablas y procedimientos) | `DICCIONARIO.sql` DD1–DD3 (tablas), DD4–DD6 (procedimientos y paquetes), DD7–DD11; en la aplicación, la pantalla "Diccionario de datos" |
| j | Índices y secuencias justificados | `IX_CALIF_COMPETENCIA`, `IX_PAGO_FACTURA`, `IX_EST_APELLIDO_UPPER` (basado en función), `IX_AUDITORIA_REG`; `SEQ_RECIBO`, `SEQ_FACTURA` (NOCACHE), `SEQ_AUDITORIA` |
| k | Regla de formato de datos | `PKG_UTIL`: moneda `$1.234.567`, fecha `DD/MM/AAAA` y larga, nota `0.0`; `TRG_ESTUDIANTE_FORMATO` (cédula, celular, email, nombres); `TRG_PAGO_FACTURA` (recibo numérico, factura `FE-000000`) |

### Reglas de negocio en triggers

| Trigger | Tabla | Regla |
|---|---|---|
| TRG_ESTUDIANTE_FORMATO | ESTUDIANTE | Cédula 6–10 dígitos, celular `3XXXXXXXXX`, email válido en minúscula, nombres con mayúscula inicial; CC solo mayores de 18, TI solo menores; fecha de autorización automática (RN-27) |
| TRG_HORARIO_REGLAS | HORARIO_GRUPO | Máximo 2 días por grupo (RN-07); un aula no se cruza el mismo día y periodo (RN-08) |
| TRG_CALIFICACION_VALIDA | CALIFICACION | La competencia pertenece al técnico y semestre del grupo; no se califica matrícula retirada ni con fecha futura |
| TRG_CALIFICACION_SUPLETORIO | CALIFICACION | Solo hay supletorio si la ordinaria fue < 3.0 (RN-22) |
| TRG_PAGO_FACTURA | PAGO | Formato de recibo y factura; numeración consecutiva de factura; recibo facturado no se modifica ni se anula (RN-18) |
| TRG_DIPLOMA_REQUISITOS | DIPLOMA | 8 competencias aprobadas, asistencia ≥ 80 %, sin mora (RN-23, RN-24, RN-25) |
| TRG_AUDITORIA_PAGO | PAGO | Registra en AUDITORIA toda inserción, modificación o borrado de recibos |
| TRG_DOCENTE_FORMATO | DOCENTE | Cédula 6–10 dígitos, email válido en minúscula, nombres con mayúscula inicial |
| TRG_GRUPO_ASIGNACION | GRUPO | El cupo no supera la capacidad del aula; no se asigna un docente inactivo |
| TRG_MATRICULA_ESTADO | MATRICULA | No cambia de estudiante ni de grupo; una matrícula retirada no se reactiva |

## Documentación

- `docs/Base de datos Oracle para ITECCI - Documento.pdf`: documento del proyecto (requisitos, reglas de negocio, modelos).
- `docs/modelo_conceptual.png` y `docs/modelo_fisico.png`.

## Cómo se cumple el punto 3 de la guía

| Requisito | Dónde |
|---|---|
| Diseño arquitectónico en directorios | Estructura de arriba: `backend/` y `frontend/` por capas |
| Diseño web con página maestra | `frontend/src/layouts/MainLayout.jsx` (menú, barra superior y área de contenido compartidos) |
| Autenticación con inicio de sesión | `POST /api/auth/login`, contraseñas con bcrypt, sesión en cookie `httpOnly` |
| Formatos de entrada de datos | Validación en el formulario, en la API (`validators/schemas.js`) y en la base (`TRG_ESTUDIANTE_FORMATO`, `PKG_API_UTIL.a_fecha`) |
| Restricción de acceso a funcionalidades | Por rol, en `routes/index.js` (servidor) y en el menú y los botones (interfaz) |
| Controles de presentación de CRUD | Estudiantes, Docentes, Contratos docentes, Programas y Grupos (`components/CrudPage.jsx`) |
| Procedimientos almacenados de Oracle | Toda operación pasa por un paquete PL/SQL; el backend no contiene sentencias SQL sobre tablas |
| Programación de grupos | Al crear o editar un grupo se listan solo los docentes con contrato en el periodo y se muestra la ocupación por día de docentes y aulas (`PKG_API_GRUPO.disponibilidad`) |
| Carga de los docentes | En Docentes, los estudiantes actuales y los días que dicta cada uno; el detalle muestra sus grupos con horario, aula y estudiantes (`PKG_API_DOCENTE.carga`) |
| Manejo del diccionario de datos | Pantalla "Diccionario de datos" → `PKG_API_DICCIONARIO` (`USER_TABLES`, `USER_TAB_COLUMNS`, `USER_OBJECTS`, `USER_PROCEDURES`…) |

## Seguridad (OWASP Top 10)

| Riesgo | Medida |
|---|---|
| A01 Control de acceso | Middleware `autorizar(...)` por ruta; la interfaz solo oculta, el servidor decide |
| A02 Fallos criptográficos | bcrypt (costo 12); JWT firmado con expiración; secretos en `.env`, fuera del repositorio |
| A03 Inyección | Solo variables de enlace hacia PL/SQL; el único SQL dinámico (`PKG_API_DICCIONARIO.contar_filas`) valida contra `USER_TABLES` y usa `DBMS_ASSERT`; React escapa todo lo que muestra |
| A04 Diseño inseguro | Reglas del negocio en procedimientos y triggers: no dependen de la interfaz |
| A05 Configuración | `helmet`, CORS limitado al frontend, cuerpo máximo de 50 kB, sin `X-Powered-By`, respuestas `no-store` |
| A06 Componentes vulnerables | Dependencias fijadas en `package-lock.json` con hash de integridad; versiones mayores vigentes; revisión con `npm audit` |
| A07 Autenticación | Máximo 10 intentos fallidos cada 15 minutos por IP; mismo mensaje y mismo tiempo de respuesta si el usuario no existe |
| CSRF (parte de A01) | Cookie `SameSite=Strict` y verificación de origen en peticiones que modifican datos (CSRF) |
| A08 Integridad de datos | El token de sesión va firmado (HS256, emisor y vencimiento verificados): uno alterado, sin firma o de otra clave se rechaza |
| A09 Registro | Se registran inicios de sesión, intentos fallidos y accesos denegados; nunca contraseñas ni tokens |
| A10 SSRF | El servidor no hace peticiones a URLs; una URL recibida se guarda como texto |

**Pruebas de seguridad:** `backend/test/owasp.test.js` comprueba cada riesgo del OWASP Top 10 (33 pruebas) levantando la API con una base de datos simulada, así que no necesita Oracle:

```
cd backend
npm test
```

**Manejo de errores:** un único manejador (`middlewares/errorHandler.js`) responde siempre `{ error: { codigo, mensaje, detalles } }`. Los `ORA-20xxx` de `RAISE_APPLICATION_ERROR` llegan al usuario como mensaje de regla de negocio (422); las restricciones únicas como 409; lo inesperado como 500 con un número de referencia, sin detalles internos.

**SOLID:** cada capa tiene una sola responsabilidad; `CrudRepository` y `CrudPage` se extienden declarando una entidad nueva, sin modificarlos; los servicios reciben su repositorio por constructor (`container.js`), así que dependen de una abstracción y no de Oracle.

## Limitaciones conocidas

- La API se conecta con el usuario dueño del esquema (`itecci`). En producción convendría un usuario de servicio con solo `EXECUTE` sobre los paquetes.
- La cookie de sesión no lleva `Secure` en desarrollo porque `localhost` no usa HTTPS; se activa sola con `NODE_ENV=production`.
- No hay pantallas para calificaciones, asistencia ni diplomas: se manejan desde SQL con `PKG_CALIFICACION`, `PKG_CERTIFICACION` y los reportes de `REPORTES.sql`.
- Al anular un recibo desde la aplicación se anula también su factura en el mismo paso, que es lo que exige RN-18.
