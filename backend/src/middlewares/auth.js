import { AppError } from '../utils/AppError.js';
import { logger } from '../utils/logger.js';

export const COOKIE_SESION = 'itecci_sesion';
export const ROLES = Object.freeze({ COORDINADOR: 'COORDINADOR', SECRETARIA: 'SECRETARIA' });
export const TODOS = [ROLES.COORDINADOR, ROLES.SECRETARIA];
export const SOLO_COORDINADOR = [ROLES.COORDINADOR];

// Autenticación: la sesión viaja en una cookie httpOnly con un JWT firmado.
export const autenticar = (tokenService) => (req, _res, next) => {
  const token = req.cookies?.[COOKIE_SESION];
  if (!token) return next(AppError.noAutenticado());
  try {
    req.usuario = tokenService.verificar(token);
    return next();
  } catch {
    return next(AppError.noAutenticado('La sesión expiró. Inicie sesión de nuevo.'));
  }
};

// Autorización por rol: se decide en el servidor, no en la interfaz.
export const autorizar = (...roles) => (req, _res, next) => {
  if (!req.usuario) return next(AppError.noAutenticado());
  if (!roles.includes(req.usuario.rol)) {
    logger.seguridad('acceso_denegado', { usuario: req.usuario.username, rol: req.usuario.rol, metodo: req.method, ruta: req.originalUrl });
    return next(AppError.prohibido());
  }
  return next();
};
