import { COOKIE_SESION } from '../middlewares/auth.js';

/** Controlador HTTP de un CRUD. */
export const crudController = (servicio) => ({
  listar: async (req, res) => res.json(await servicio.listar(req.valid.query)),
  obtener: async (req, res) => res.json(await servicio.obtener(req.valid.params.id)),
  crear: async (req, res) => res.status(201).json(await servicio.crear(req.valid.body)),
  actualizar: async (req, res) => res.json(await servicio.actualizar(req.valid.params.id, req.valid.body)),
  eliminar: async (req, res) => {
    await servicio.eliminar(req.valid.params.id);
    res.status(204).end();
  },
});

/** Controlador de inicio de sesión, cierre de sesión y usuario actual. */
export const authController = (authService, { minutos, segura }) => {
  const opcionesCookie = (req) => {
    const otroSitio = !/^http:\/\/localhost(:\d+)?$/.test(req.get('origin') ?? 'http://localhost');
    return { httpOnly: true, path: '/api', sameSite: otroSitio ? 'none' : 'strict', secure: otroSitio || segura };
  };
  return {
    iniciarSesion: async (req, res) => {
      const { usuario, token } = await authService.iniciarSesion(req.valid.body, req.ip);
      res.cookie(COOKIE_SESION, token, { ...opcionesCookie(req), maxAge: minutos * 60 * 1000 });
      res.json({ usuario });
    },
    cerrarSesion: (req, res) => {
      res.clearCookie(COOKIE_SESION, opcionesCookie(req));
      res.status(204).end();
    },
    yo: (req, res) => res.json({ usuario: req.usuario }),
  };
};

/** Controlador de las listas desplegables. */
export const catalogoController = (catalogoRepository) => ({
  listar: async (req, res) => res.json(await catalogoRepository.listar(req.valid.params.nombre)),
});

/** Controlador de matrículas: listado, detalle, matrícula y retiro. */
export const matriculaController = (servicio) => ({
  listar: async (req, res) => res.json(await servicio.listar(req.valid.query)),
  detalle: async (req, res) => res.json(await servicio.detalle(req.valid.params.id)),
  matricular: async (req, res) => res.status(201).json(await servicio.matricular(req.valid.body, req.usuario)),
  retirar: async (req, res) => res.json(await servicio.retirar(req.valid.params.id, req.valid.body.observacion)),
});

/** Controlador de recibos de caja: listado, registro y anulación. */
export const pagoController = (servicio) => ({
  listar: async (req, res) => res.json(await servicio.listar(req.valid.query)),
  registrar: async (req, res) => res.status(201).json(await servicio.registrar(req.valid.body, req.usuario)),
  anular: async (req, res) => {
    await servicio.anular(req.valid.params.id, req.valid.body.motivo, req.usuario);
    res.status(204).end();
  },
});

/** Controlador del tablero y la cartera. */
export const reporteController = (servicio) => ({
  tablero: async (_req, res) => res.json(await servicio.tablero()),
  cartera: async (req, res) => res.json(await servicio.cartera(req.valid.query)),
});

/** Controlador del diccionario de datos. */
export const diccionarioController = (servicio) => ({
  tablas: async (_req, res) => res.json(await servicio.tablas()),
  columnas: async (req, res) => res.json(await servicio.columnas(req.valid.params.tabla)),
  objetos: async (_req, res) => res.json(await servicio.objetos()),
  subprogramas: async (_req, res) => res.json(await servicio.subprogramas()),
});

/** Controlador de la disponibilidad de docentes y aulas para programar grupos. */
export const disponibilidadController = (servicio) => ({
  consultar: async (req, res) => res.json(await servicio.consultar(req.valid.query)),
});

/** Controlador de los grupos y estudiantes de cada docente. */
export const cargaDocenteController = (servicio) => ({
  consultar: async (req, res) => res.json(await servicio.consultar(req.valid.params.id)),
});
