/** Error de la aplicación con código HTTP y mensaje para el usuario. */
export class AppError extends Error {
  constructor(status, codigo, mensaje, detalles) {
    super(mensaje);
    this.name = 'AppError';
    this.status = status;
    this.codigo = codigo;
    this.detalles = detalles;
  }

  static validacion(detalles) {
    return new AppError(400, 'VALIDACION', 'Revise los datos del formulario', detalles);
  }
  static noAutenticado(mensaje = 'Debe iniciar sesión') {
    return new AppError(401, 'NO_AUTENTICADO', mensaje);
  }
  static prohibido(mensaje = 'Su rol no tiene permiso para esta acción') {
    return new AppError(403, 'PROHIBIDO', mensaje);
  }
  static noEncontrado(mensaje = 'El registro no existe') {
    return new AppError(404, 'NO_ENCONTRADO', mensaje);
  }
  static conflicto(mensaje) {
    return new AppError(409, 'CONFLICTO', mensaje);
  }
  static reglaNegocio(mensaje) {
    return new AppError(422, 'REGLA_NEGOCIO', mensaje);
  }
}
