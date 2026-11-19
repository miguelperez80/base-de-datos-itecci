import { AppError } from '../utils/AppError.js';

/** Valida params, query y body con esquemas Zod y deja el resultado en req.valid. */
export const validar = (esquemas) => (req, _res, next) => {
  req.valid = req.valid ?? {};
  for (const parte of ['params', 'query', 'body']) {
    const esquema = esquemas[parte];
    if (!esquema) continue;
    const resultado = esquema.safeParse(req[parte] ?? {});
    if (!resultado.success) {
      const detalles = resultado.error.issues.map((i) => ({ campo: i.path.join('.'), mensaje: i.message }));
      return next(AppError.validacion(detalles));
    }
    req.valid[parte] = resultado.data;
  }
  return next();
};
