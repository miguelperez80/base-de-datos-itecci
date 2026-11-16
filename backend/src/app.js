import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import rateLimit from 'express-rate-limit';
import { env } from './config/env.js';
import { crearRutas } from './routes/index.js';
import { rutaNoEncontrada, manejadorErrores } from './middlewares/errorHandler.js';
import { AppError } from './utils/AppError.js';

export function crearApp(contenedor) {
  const app = express();

  app.disable('x-powered-by');
  app.use(helmet());                                            // cabeceras de seguridad
  // Un sitio público (GitHub Pages) que llama a localhost: el navegador exige esta cabecera en el preflight
  app.use((req, res, next) => {
    if (req.get('access-control-request-private-network')) res.set('Access-Control-Allow-Private-Network', 'true');
    next();
  });
  app.use(cors({ origin: env.FRONTEND_ORIGIN, credentials: true, methods: ['GET', 'POST', 'PUT', 'DELETE'] }));
  app.use(rateLimit({ windowMs: 60 * 1000, limit: 300, standardHeaders: 'draft-7', legacyHeaders: false }));
  // Las respuestas de la API llevan datos personales: no se guardan en caché
  app.use('/api', (_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });
  app.use(express.json({ limit: '50kb' }));
  app.use(cookieParser());

  // Defensa CSRF adicional a SameSite=Strict: las peticiones que modifican datos
  // solo se aceptan si vienen del frontend autorizado.
  app.use((req, _res, next) => {
    const modifica = !['GET', 'HEAD', 'OPTIONS'].includes(req.method);
    const origen = req.get('origin');
    if (modifica && origen && !env.FRONTEND_ORIGIN.includes(origen)) return next(AppError.prohibido('Origen no permitido'));
    return next();
  });

  app.use('/api', crearRutas(contenedor));
  app.use(rutaNoEncontrada);
  app.use(manejadorErrores);
  return app;
}
