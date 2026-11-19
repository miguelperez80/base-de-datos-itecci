import { env } from './config/env.js';
import { db } from './config/db.js';
import {
  EstudianteRepository, DocenteRepository, ContratoRepository, TecnicoRepository, GrupoRepository,
} from './repositories/entidades.js';
import {
  UsuarioRepository, CatalogoRepository, MatriculaRepository, PagoRepository, ReporteRepository, DiccionarioRepository,
} from './repositories/procesos.js';
import { CrudService } from './services/CrudService.js';
import { AuthService, TokenService } from './services/AuthService.js';
import { MatriculaService, PagoService, ReporteService, DiccionarioService } from './services/procesos.js';
import * as ctl from './controllers/controllers.js';
import { autenticar } from './middlewares/auth.js';

/** Crea repositorios, servicios y controladores, e inyecta en cada uno la capa inferior. */
export function crearContenedor(conexion = db) {
  const tokens = new TokenService({ secreto: env.JWT_SECRET, minutos: env.JWT_EXPIRES_MIN });
  const diccionarioRepo = new DiccionarioRepository(conexion);

  return {
    autenticar: autenticar(tokens),
    auth: ctl.authController(new AuthService(new UsuarioRepository(conexion), tokens), {
      minutos: env.JWT_EXPIRES_MIN, segura: env.NODE_ENV === 'production',
    }),
    catalogos: ctl.catalogoController(new CatalogoRepository(conexion)),
    estudiantes: ctl.crudController(new CrudService(new EstudianteRepository(conexion), 'El estudiante')),
    docentes: ctl.crudController(new CrudService(new DocenteRepository(conexion), 'El docente')),
    contratos: ctl.crudController(new CrudService(new ContratoRepository(conexion), 'El contrato')),
    tecnicos: ctl.crudController(new CrudService(new TecnicoRepository(conexion), 'El programa técnico')),
    grupos: ctl.crudController(new CrudService(new GrupoRepository(conexion), 'El grupo')),
    matriculas: ctl.matriculaController(new MatriculaService(new MatriculaRepository(conexion))),
    pagos: ctl.pagoController(new PagoService(new PagoRepository(conexion))),
    reportes: ctl.reporteController(new ReporteService(new ReporteRepository(conexion))),
    diccionario: ctl.diccionarioController(new DiccionarioService(diccionarioRepo)),
    salud: async (_req, res) => {
      await diccionarioRepo.ping();
      res.json({ estado: 'ok', baseDatos: 'conectada' });
    },
  };
}
