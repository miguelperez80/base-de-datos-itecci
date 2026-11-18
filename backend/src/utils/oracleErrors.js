import { AppError } from './AppError.js';

// Mensajes legibles para las restricciones UNIQUE más comunes del esquema.
const UNICOS = {
  UQ_ESTUDIANTE_CEDULA: 'Ya existe un estudiante con ese número de documento',
  UQ_DOCENTE_CEDULA: 'Ya existe un docente con ese número de documento',
  UQ_DOCENTE_EMAIL: 'Ya existe un docente con ese correo electrónico',
  UQ_CONTRATO: 'El docente ya tiene contrato en ese periodo',
  UQ_TECNICO_CODIGO: 'Ya existe un programa técnico con ese código',
  UQ_TECNICO_NOMBRE: 'Ya existe un programa técnico con ese nombre',
  UQ_GRUPO: 'Ya existe un grupo para ese programa, periodo y semestre',
  UQ_GRUPO_CODIGO: 'Ya existe un grupo con ese código',
  UQ_MATRICULA: 'El estudiante ya tiene una matrícula en ese grupo',
  UQ_PAGO_RECIBO: 'Ya existe un recibo con ese número',
};

const nombreRestriccion = (mensaje) => /\(\w+\.(\w+)\)/.exec(mensaje ?? '')?.[1];

// Texto que acompaña a ORA-20xxx (lo escribe RAISE_APPLICATION_ERROR), sin la pila de PL/SQL.
const mensajeNegocio = (mensaje) =>
  (mensaje ?? '').split('\n')[0].replace(/^ORA-\d+:\s*/, '').trim() || 'La operación no cumple una regla del negocio';

/**
 * Convierte un error de Oracle en un AppError con el código HTTP adecuado.
 * Devuelve null si el error no es de Oracle o no se reconoce (se tratará como 500).
 */
export function traducirErrorOracle(err) {
  const num = err?.errorNum;
  if (typeof num !== 'number') {
    // Errores del controlador (NJS-xxx): casi siempre la base de datos no responde
    if (typeof err?.code === 'string' && err.code.startsWith('NJS-')) {
      return new AppError(503, 'BD_NO_DISPONIBLE', 'La base de datos no está disponible. Intente de nuevo en unos segundos.');
    }
    return null;
  }

  if (num === 20404) return AppError.noEncontrado(mensajeNegocio(err.message));
  if (num >= 20000 && num <= 20999) return AppError.reglaNegocio(mensajeNegocio(err.message));

  switch (num) {
    case 1:
      return AppError.conflicto(UNICOS[nombreRestriccion(err.message)] ?? 'Ya existe un registro con esos datos');
    case 2291:
      return AppError.reglaNegocio('Uno de los registros relacionados no existe');
    case 2292:
      return AppError.conflicto('No se puede eliminar: hay registros que dependen de este');
    case 2290:
      return AppError.reglaNegocio('Uno de los valores no está permitido para este registro');
    case 1400:
      return AppError.reglaNegocio('Falta un dato obligatorio');
    case 1438:
    case 12899:
      return AppError.reglaNegocio('Uno de los valores es demasiado largo');
    case 1017:
    case 12154:
    case 12514:
    case 12541:
    case 3113:
    case 3114:
      return new AppError(503, 'BD_NO_DISPONIBLE', 'La base de datos no está disponible. Intente de nuevo en unos segundos.');
    default:
      return null;
  }
}
