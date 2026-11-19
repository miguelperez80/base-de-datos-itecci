import { z } from 'zod';

z.setErrorMap((issue, ctx) => {
  switch (issue.code) {
    case z.ZodIssueCode.invalid_type:
      return { message: issue.received === 'undefined' || issue.received === 'null' ? 'Este dato es obligatorio' : 'El tipo de dato no es válido' };
    case z.ZodIssueCode.too_small:
      return { message: issue.type === 'string' ? `Debe tener al menos ${issue.minimum} caracteres` : `Debe ser mayor o igual a ${issue.minimum}` };
    case z.ZodIssueCode.too_big:
      return { message: issue.type === 'string' ? `No puede superar ${issue.maximum} caracteres` : `Debe ser menor o igual a ${issue.maximum}` };
    case z.ZodIssueCode.invalid_enum_value:
      return { message: 'Seleccione una de las opciones disponibles' };
    case z.ZodIssueCode.unrecognized_keys:
      return { message: `Campos no permitidos: ${issue.keys.join(', ')}` };
    default:
      return { message: ctx.defaultError };
  }
});

const texto = (min, max) => z.string().trim().min(min).max(max);
const opcional = (max) =>
  z.union([z.string().trim().max(max), z.null(), z.undefined()]).transform((v) => (v ? v : null));
const nombrePropio = (max) =>
  texto(2, max).regex(/^[\p{L}][\p{L} .'-]*$/u, 'Solo se admiten letras, espacios, puntos, apóstrofos y guiones');
const documento = z.string().trim().regex(/^[0-9]{6,10}$/, 'Debe tener entre 6 y 10 dígitos, sin puntos ni espacios');
const email = z.string().trim().toLowerCase().max(120).regex(/^[a-z0-9._-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$/, 'El correo electrónico no es válido');
const celular = z.string().transform((v) => v.replace(/[^0-9]/g, '')).pipe(z.string().regex(/^3[0-9]{9}$/, 'Debe ser un celular de 10 dígitos que inicie en 3'));
const telefono = z.string().trim().regex(/^[0-9+ ()-]{7,20}$/, 'Entre 7 y 20 caracteres: dígitos, espacios y + ( ) -');
const fecha = z.string().trim().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use el formato AAAA-MM-DD')
  .refine((v) => !Number.isNaN(Date.parse(v)), 'La fecha no existe');
const entero = (min, max) => z.coerce.number().int('Debe ser un número entero').min(min).max(max);
const id = entero(1, 9_999_999);
const bandera = z.union([z.boolean(), z.literal(0), z.literal(1)]).transform((v) => (v ? 1 : 0));

/** Esquemas de validación de la API. */
export const idParam = z.object({ id });

export const listaQuery = z.object({
  q: z.string().trim().max(80).optional().transform((v) => v || null),
  pagina: entero(1, 100_000).default(1),
  porPagina: entero(1, 100).default(10),
  estado: z.string().trim().max(20).optional().transform((v) => v || null),
});

export const loginBody = z.object({
  username: z.string().trim().toLowerCase().min(3).max(40).regex(/^[a-z0-9._-]+$/, 'Usuario no válido'),
  password: z.string().min(1).max(72),
}).strict();

export const estudianteBody = z.object({
  tipo_documento: z.enum(['CC', 'TI', 'CE', 'PPT']),
  cedula: documento,
  nombres: nombrePropio(80),
  apellidos: nombrePropio(80),
  fecha_nacimiento: fecha,
  telefono: celular,
  email,
  direccion: texto(5, 150),
  ocupacion: z.enum(['Desempleado', 'Empleado', 'Independiente', 'Estudiante básica/media', 'Estudiante superior', 'Empresa']),
  regimen_salud: z.enum(['Contributivo', 'Subsidiado', 'Especial', 'Sin afiliación']),
  condicion_medica: opcional(200),
  estrato: entero(0, 6),
  estado_civil: z.enum(['Soltero', 'Casado', 'Unión libre', 'Separado', 'Viudo']),
  nivel_formacion: z.enum(['Bachiller', 'Técnico', 'Tecnólogo', 'Profesional', 'Posgrado']),
  autoriza_centrales: bandera,
  doc_cedula: bandera,
  doc_diploma: bandera,
  doc_foto: bandera,
}).strict();

export const docenteBody = z.object({
  cedula: documento,
  nombres: nombrePropio(80),
  apellidos: nombrePropio(80),
  email,
  telefono: z.union([telefono, z.literal(''), z.null(), z.undefined()]).transform((v) => (v ? v : null)),
  nivel_formacion: z.enum(['Pregrado', 'Especialización', 'Maestría', 'Doctorado']),
  anios_experiencia: entero(1, 60),
  activo: bandera,
}).strict();

const contratoEditable = {
  horas_catedra: entero(1, 1000),
  valor_hora: z.coerce.number().int('El valor por hora no lleva decimales').min(1000, 'El valor mínimo por hora es $1.000').max(1_000_000),
};
export const contratoCrearBody = z.object({ docente_id: id, periodo_id: id, ...contratoEditable }).strict();
export const contratoEditarBody = z.object({ docente_id: id.optional(), periodo_id: id.optional(), ...contratoEditable }).strict();

export const tecnicoBody = z.object({
  codigo: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{2,10}$/, 'Entre 2 y 10 letras o números, sin espacios'),
  nombre: texto(5, 80),
  activo: bandera,
}).strict();

const ESTADOS_GRUPO = ['En formación', 'Activo', 'Cerrado', 'Cancelado'];
const grupoEditable = {
  docente_id: id,
  aula_id: id,
  cupo_min: entero(15, 30),
  cupo_max: entero(15, 30),
  estado: z.enum(ESTADOS_GRUPO),
  dia1: entero(1, 6),
  dia2: entero(1, 6),
};
const reglasGrupo = (g, ctx) => {
  if (g.cupo_min > g.cupo_max) ctx.addIssue({ code: 'custom', path: ['cupo_min'], message: 'El cupo mínimo no puede superar al máximo' });
  if (g.dia1 === g.dia2) ctx.addIssue({ code: 'custom', path: ['dia2'], message: 'Los dos días de clase deben ser distintos' });
};
export const grupoCrearBody = z.object({ tecnico_id: id, periodo_id: id, semestre: entero(1, 2), ...grupoEditable })
  .strict().superRefine(reglasGrupo);
export const grupoEditarBody = z.object({ tecnico_id: id.optional(), periodo_id: id.optional(), semestre: entero(1, 2).optional(), ...grupoEditable })
  .strict().superRefine(reglasGrupo);

export const matriculaBody = z.object({ estudiante_id: id, grupo_id: id }).strict();
export const retiroBody = z.object({ observacion: texto(5, 300) }).strict();

export const pagoBody = z.object({
  matricula_id: id,
  valor: z.coerce.number().int('El valor no lleva decimales').min(1000, 'El valor mínimo es $1.000').max(10_000_000),
  medio_pago_id: entero(1, 99),
  referencia: opcional(60),
}).strict();
export const anulacionBody = z.object({ motivo: texto(5, 300) }).strict();

export const tablaParam = z.object({
  tabla: z.string().trim().toUpperCase().regex(/^[A-Z][A-Z0-9_$#]{0,29}$/, 'Nombre de tabla no válido'),
});
export const catalogoParam = z.object({
  nombre: z.enum(['periodos', 'aulas', 'medios_pago', 'tecnicos', 'docentes', 'docentes_todos', 'grupos_abiertos']),
});
