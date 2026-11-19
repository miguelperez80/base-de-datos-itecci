import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { validar } from '../middlewares/validate.js';
import { autorizar, TODOS, SOLO_COORDINADOR } from '../middlewares/auth.js';
import * as v from '../validators/schemas.js';

/** Crea las rutas REST de un CRUD con los roles que pueden leer, escribir y eliminar. */
function rutasCrud(controlador, { crear, editar = crear, leen = TODOS, escriben, eliminan = SOLO_COORDINADOR }) {
  const r = Router();
  r.get('/', autorizar(...leen), validar({ query: v.listaQuery }), controlador.listar);
  r.get('/:id', autorizar(...leen), validar({ params: v.idParam }), controlador.obtener);
  r.post('/', autorizar(...escriben), validar({ body: crear }), controlador.crear);
  r.put('/:id', autorizar(...escriben), validar({ params: v.idParam, body: editar }), controlador.actualizar);
  r.delete('/:id', autorizar(...eliminan), validar({ params: v.idParam }), controlador.eliminar);
  return r;
}

/** Crea todas las rutas de la API con su autenticación, permisos y validación. */
export function crearRutas(c) {
  const api = Router();

  api.get('/salud', c.salud);

  const limiteLogin = rateLimit({
    windowMs: 15 * 60 * 1000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false,
    skipSuccessfulRequests: true,
    message: { error: { codigo: 'DEMASIADOS_INTENTOS', mensaje: 'Demasiados intentos fallidos. Espere 15 minutos.' } },
  });
  api.post('/auth/login', limiteLogin, validar({ body: v.loginBody }), c.auth.iniciarSesion);
  api.post('/auth/logout', c.auth.cerrarSesion);

  api.use(c.autenticar);
  api.get('/auth/yo', c.auth.yo);
  api.get('/catalogos/:nombre', validar({ params: v.catalogoParam }), c.catalogos.listar);

  api.use('/estudiantes', rutasCrud(c.estudiantes, { crear: v.estudianteBody, escriben: TODOS }));
  api.use('/docentes', rutasCrud(c.docentes, { crear: v.docenteBody, leen: SOLO_COORDINADOR, escriben: SOLO_COORDINADOR }));
  api.use('/contratos', rutasCrud(c.contratos, {
    crear: v.contratoCrearBody, editar: v.contratoEditarBody, leen: SOLO_COORDINADOR, escriben: SOLO_COORDINADOR,
  }));
  api.use('/tecnicos', rutasCrud(c.tecnicos, { crear: v.tecnicoBody, escriben: SOLO_COORDINADOR }));
  api.use('/grupos', rutasCrud(c.grupos, { crear: v.grupoCrearBody, editar: v.grupoEditarBody, escriben: SOLO_COORDINADOR }));

  api.get('/matriculas', validar({ query: v.listaQuery }), c.matriculas.listar);
  api.get('/matriculas/:id', validar({ params: v.idParam }), c.matriculas.detalle);
  api.post('/matriculas', validar({ body: v.matriculaBody }), c.matriculas.matricular);
  api.post('/matriculas/:id/retiro', validar({ params: v.idParam, body: v.retiroBody }), c.matriculas.retirar);

  api.get('/pagos', validar({ query: v.listaQuery }), c.pagos.listar);
  api.post('/pagos', validar({ body: v.pagoBody }), c.pagos.registrar);
  api.post('/pagos/:id/anulacion', autorizar(...SOLO_COORDINADOR), validar({ params: v.idParam, body: v.anulacionBody }), c.pagos.anular);

  api.get('/reportes/tablero', c.reportes.tablero);
  api.get('/reportes/cartera', validar({ query: v.listaQuery }), c.reportes.cartera);

  const diccionario = Router();
  diccionario.use(autorizar(...SOLO_COORDINADOR));
  diccionario.get('/tablas', c.diccionario.tablas);
  diccionario.get('/tablas/:tabla/columnas', validar({ params: v.tablaParam }), c.diccionario.columnas);
  diccionario.get('/objetos', c.diccionario.objetos);
  diccionario.get('/subprogramas', c.diccionario.subprogramas);
  api.use('/diccionario', diccionario);

  return api;
}
