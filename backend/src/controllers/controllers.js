import { COOKIE_SESION } from '../middlewares/auth.js';

// Los controladores solo traducen HTTP <-> servicio. No contienen reglas ni SQL.
// Con Express 5, si una función async falla, el error llega solo al manejador central.

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

export const authController = (authService, { minutos, segura }) => {
  // Desde el frontend local la cookie es SameSite=Strict. Desde el frontend publicado (otro sitio)
  // el navegador solo la acepta con SameSite=None y Secure; ahí la protección CSRF la da la
  // verificación de origen de app.js, que solo deja pasar los orígenes de FRONTEND_ORIGIN.
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

export const catalogoController = (catalogoRepository) => ({
  listar: async (req, res) => res.json(await catalogoRepository.listar(req.valid.params.nombre)),
});

export const matriculaController = (servicio) => ({
  listar: async (req, res) => res.json(await servicio.listar(req.valid.query)),
  detalle: async (req, res) => res.json(await servicio.detalle(req.valid.params.id)),
  matricular: async (req, res) => res.status(201).json(await servicio.matricular(req.valid.body, req.usuario)),
  retirar: async (req, res) => res.json(await servicio.retirar(req.valid.params.id, req.valid.body.observacion)),
});

export const pagoController = (servicio) => ({
  listar: async (req, res) => res.json(await servicio.listar(req.valid.query)),
  registrar: async (req, res) => res.status(201).json(await servicio.registrar(req.valid.body, req.usuario)),
  anular: async (req, res) => {
    await servicio.anular(req.valid.params.id, req.valid.body.motivo, req.usuario);
    res.status(204).end();
  },
});

export const reporteController = (servicio) => ({
  tablero: async (_req, res) => res.json(await servicio.tablero()),
  cartera: async (req, res) => res.json(await servicio.cartera(req.valid.query)),
});

export const diccionarioController = (servicio) => ({
  tablas: async (_req, res) => res.json(await servicio.tablas()),
  columnas: async (req, res) => res.json(await servicio.columnas(req.valid.params.tabla)),
  objetos: async (_req, res) => res.json(await servicio.objetos()),
  subprogramas: async (_req, res) => res.json(await servicio.subprogramas()),
});
