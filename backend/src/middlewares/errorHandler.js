import { randomUUID } from 'node:crypto';
import { AppError } from '../utils/AppError.js';
import { traducirErrorOracle } from '../utils/oracleErrors.js';
import { logger } from '../utils/logger.js';

/** Responde 404 para rutas inexistentes. */
export function rutaNoEncontrada(req, _res, next) {
  next(AppError.noEncontrado(`No existe la ruta ${req.method} ${req.path}`));
}

/** Responde todos los errores con el formato { error: { codigo, mensaje, detalles } }. */
export function manejadorErrores(err, req, res, _next) {
  let error = err instanceof AppError ? err : traducirErrorOracle(err);

  if (!error && err?.type === 'entity.parse.failed') {
    error = new AppError(400, 'JSON_INVALIDO', 'El cuerpo de la petición no es un JSON válido');
  }
  if (!error && err?.type === 'entity.too.large') {
    error = new AppError(413, 'DEMASIADO_GRANDE', 'La petición es demasiado grande');
  }

  if (!error) {
    const referencia = randomUUID();
    logger.error('error no controlado', {
      referencia, metodo: req.method, ruta: req.path, usuario: req.usuario?.username, error: err?.message, pila: err?.stack,
    });
    return res.status(500).json({
      error: { codigo: 'ERROR_INTERNO', mensaje: 'Ocurrió un error inesperado. Si persiste, informe esta referencia.', referencia },
    });
  }

  if (error.status >= 500) {
    logger.error('servicio no disponible', { ruta: req.path, error: err?.message });
  }
  return res.status(error.status).json({
    error: { codigo: error.codigo, mensaje: error.message, detalles: error.detalles },
  });
}
