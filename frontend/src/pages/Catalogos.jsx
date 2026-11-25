import { useState } from 'react';
import { CalendarDays } from 'lucide-react';
import CrudPage from '../components/CrudPage.jsx';
import CargaDocente from '../components/CargaDocente.jsx';
import DisponibilidadGrupo from '../components/DisponibilidadGrupo.jsx';
import { Insignia } from '../components/Tabla.jsx';
import { ROLES } from '../context/AuthContext.jsx';
import { hoyIso, moneda, numero, programaCorto } from '../utils/formato.js';

const opciones = (lista) => lista.map((v) => ({ valor: v, texto: v }));
const TODOS = [ROLES.COORDINADOR, ROLES.SECRETARIA];
const SOLO_COORDINADOR = [ROLES.COORDINADOR];

const DOCUMENTO = { patron: /^[0-9]{6,10}$/, mensaje: 'Entre 6 y 10 dígitos, sin puntos ni espacios', inputMode: 'numeric', maxLength: 10 };
const NOMBRE = { patron: /^[\p{L}][\p{L} .'-]+$/u, mensaje: 'Solo letras, espacios, puntos y guiones (mínimo 2)', maxLength: 80 };
const CORREO = { tipo: 'email', patron: /^[A-Za-z0-9._-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/, mensaje: 'Escriba un correo válido, por ejemplo nombre@correo.com', maxLength: 120 };
const TELEFONO = { tipo: 'tel', patron: /^[0-9+ ()-]{7,20}$/, mensaje: 'Entre 7 y 20 caracteres: dígitos, espacios y + ( ) -', maxLength: 20 };
const CELULAR = { tipo: 'tel', patron: /^3[0-9]{9}$/, mensaje: 'Celular de 10 dígitos que inicie en 3', inputMode: 'numeric', maxLength: 10, ejemplo: '3001234567' };
const siNo = (v) => <Insignia tono={v ? 'ok' : 'neutro'}>{v ? 'Activo' : 'Inactivo'}</Insignia>;

/** CRUD de estudiantes. */
export function Estudiantes() {
  return (
    <CrudPage
      titulo="Estudiantes"
      descripcion="Datos del formulario de matrícula y documentos requisito de cada estudiante."
      recurso="estudiantes"
      singular="Estudiante"
      escriben={TODOS}
      eliminan={SOLO_COORDINADOR}
      textoBuscar="Buscar por nombre o documento…"
      describir={(f) => `${f.nombres} ${f.apellidos}`}
      columnas={[
        { clave: 'cedula', titulo: 'Documento', render: (f) => <span className="num">{f.tipo_documento} {f.cedula}</span> },
        { clave: 'apellidos', titulo: 'Estudiante', render: (f) => <strong>{f.apellidos} {f.nombres}</strong> },
        { clave: 'telefono', titulo: 'Teléfono' },
        { clave: 'email', titulo: 'Correo', render: (f) => <span className="secundario">{f.email}</span> },
        { clave: 'documentos', titulo: 'Documentos', render: (f) => <Insignia tono={f.documentos >= 2 ? 'ok' : 'aviso'}>{f.documentos} de 3</Insignia> },
        { clave: 'matriculas', titulo: 'Matrículas', derecha: true },
      ]}
      inicial={{
        tipo_documento: 'CC', cedula: '', nombres: '', apellidos: '', fecha_nacimiento: '', telefono: '', email: '', direccion: '',
        ocupacion: '', regimen_salud: '', condicion_medica: '', estrato: '', estado_civil: '', nivel_formacion: '',
        autoriza_centrales: 0, doc_cedula: 0, doc_diploma: 0, doc_foto: 0,
      }}
      campos={[
        { nombre: 'tipo_documento', etiqueta: 'Tipo de documento', tipo: 'select', requerido: true, opciones: [
          { valor: 'CC', texto: 'Cédula de ciudadanía' }, { valor: 'TI', texto: 'Tarjeta de identidad' },
          { valor: 'CE', texto: 'Cédula de extranjería' }, { valor: 'PPT', texto: 'Permiso por protección temporal' },
        ] },
        { nombre: 'cedula', etiqueta: 'Número de documento', requerido: true, ...DOCUMENTO },
        { nombre: 'nombres', etiqueta: 'Nombres', requerido: true, ...NOMBRE },
        { nombre: 'apellidos', etiqueta: 'Apellidos', requerido: true, ...NOMBRE },
        { nombre: 'fecha_nacimiento', etiqueta: 'Fecha de nacimiento', tipo: 'date', requerido: true, max: hoyIso(), mensaje: 'La fecha no puede ser futura', ayuda: 'Con cédula de ciudadanía debe ser mayor de edad; la tarjeta de identidad es para menores' },
        { nombre: 'estado_civil', etiqueta: 'Estado civil', tipo: 'select', requerido: true, opciones: opciones(['Soltero', 'Casado', 'Unión libre', 'Separado', 'Viudo']) },
        { nombre: 'telefono', etiqueta: 'Celular', requerido: true, ...CELULAR, seccion: 'Contacto' },
        { nombre: 'email', etiqueta: 'Correo electrónico', requerido: true, ...CORREO },
        { nombre: 'direccion', etiqueta: 'Dirección', requerido: true, minLength: 5, maxLength: 150, ancho: true },
        { nombre: 'ocupacion', etiqueta: 'Ocupación', tipo: 'select', requerido: true, seccion: 'Información socioeconómica',
          opciones: opciones(['Desempleado', 'Empleado', 'Independiente', 'Estudiante básica/media', 'Estudiante superior', 'Empresa']) },
        { nombre: 'nivel_formacion', etiqueta: 'Nivel de formación', tipo: 'select', requerido: true, opciones: opciones(['Bachiller', 'Técnico', 'Tecnólogo', 'Profesional', 'Posgrado']) },
        { nombre: 'regimen_salud', etiqueta: 'Régimen de salud', tipo: 'select', requerido: true, opciones: opciones(['Contributivo', 'Subsidiado', 'Especial', 'Sin afiliación']) },
        { nombre: 'estrato', etiqueta: 'Estrato', tipo: 'number', requerido: true, min: 0, max: 6, mensaje: 'El estrato va de 0 a 6' },
        { nombre: 'condicion_medica', etiqueta: 'Condición médica (opcional)', tipo: 'textarea', maxLength: 200, ancho: true },
        { nombre: 'doc_cedula', etiqueta: 'Entregó copia del documento', tipo: 'checkbox', seccion: 'Documentos requisito y autorizaciones' },
        { nombre: 'doc_diploma', etiqueta: 'Entregó diploma de bachiller', tipo: 'checkbox' },
        { nombre: 'doc_foto', etiqueta: 'Entregó fotografía 3x4', tipo: 'checkbox' },
        { nombre: 'autoriza_centrales', etiqueta: 'Autoriza consulta en centrales de riesgo', tipo: 'checkbox' },
      ]}
    />
  );
}

/** CRUD de docentes. */
export function Docentes() {
  const [detalle, setDetalle] = useState(null);
  return (
    <>
      <CrudPage
        titulo="Docentes"
        descripcion="Docentes contratados por hora cátedra. Un docente con grupos no se elimina: se marca como inactivo."
        recurso="docentes"
        singular="Docente"
        escriben={SOLO_COORDINADOR}
        textoBuscar="Buscar por nombre o documento…"
        describir={(f) => `${f.nombres} ${f.apellidos}`}
        columnas={[
          { clave: 'cedula', titulo: 'Documento', render: (f) => <span className="num">{f.cedula}</span> },
          { clave: 'apellidos', titulo: 'Docente', render: (f) => <strong>{f.apellidos} {f.nombres}</strong> },
          { clave: 'email', titulo: 'Correo', render: (f) => <span className="secundario">{f.email}</span> },
          { clave: 'nivel_formacion', titulo: 'Formación' },
          { clave: 'anios_experiencia', titulo: 'Años de experiencia', derecha: true },
          { clave: 'estudiantes', titulo: 'Estudiantes actuales', derecha: true },
          { clave: 'dias', titulo: 'Días que dicta', render: (f) => f.dias ?? <span className="secundario">Sin grupos en curso</span> },
          { clave: 'activo', titulo: 'Estado', render: (f) => siNo(f.activo) },
        ]}
        accionesExtra={(f) => (
          <button
            type="button"
            className="btn btn-icono"
            onClick={() => setDetalle(f)}
            aria-label={`Ver grupos y estudiantes de ${f.nombres} ${f.apellidos}`}
            title="Grupos y estudiantes"
          >
            <CalendarDays aria-hidden="true" />
          </button>
        )}
        inicial={{ cedula: '', nombres: '', apellidos: '', email: '', telefono: '', nivel_formacion: '', anios_experiencia: '', activo: 1 }}
        campos={[
          { nombre: 'cedula', etiqueta: 'Número de documento', requerido: true, ...DOCUMENTO },
          { nombre: 'nivel_formacion', etiqueta: 'Nivel de formación', tipo: 'select', requerido: true, opciones: opciones(['Pregrado', 'Especialización', 'Maestría', 'Doctorado']) },
          { nombre: 'nombres', etiqueta: 'Nombres', requerido: true, ...NOMBRE },
          { nombre: 'apellidos', etiqueta: 'Apellidos', requerido: true, ...NOMBRE },
          { nombre: 'email', etiqueta: 'Correo electrónico', requerido: true, ...CORREO },
          { nombre: 'telefono', etiqueta: 'Teléfono (opcional)', ...TELEFONO },
          { nombre: 'anios_experiencia', etiqueta: 'Años de experiencia en docencia', tipo: 'number', requerido: true, min: 1, max: 60, mensaje: 'Se exige al menos 1 año de experiencia' },
          { nombre: 'activo', etiqueta: 'Docente activo', tipo: 'checkbox' },
        ]}
      />
      {detalle && <CargaDocente docente={detalle} onCerrar={() => setDetalle(null)} />}
    </>
  );
}

/** CRUD de contratos por hora cátedra. */
export function Contratos() {
  return (
    <CrudPage
      titulo="Contratos docentes"
      descripcion="Contrato por hora cátedra de cada docente en un periodo. Sin contrato en el periodo, el docente no puede tener grupos."
      recurso="contratos"
      singular="Contrato"
      escriben={SOLO_COORDINADOR}
      textoBuscar="Buscar por docente, documento o periodo…"
      describir={(f) => `${f.docente} · ${f.periodo}`}
      columnas={[
        { clave: 'periodo', titulo: 'Periodo', render: (f) => <strong>{f.periodo}</strong> },
        { clave: 'docente', titulo: 'Docente', render: (f) => <>{f.docente}{!f.activo && <div className="secundario">Inactivo</div>}</> },
        { clave: 'horas_catedra', titulo: 'Horas', derecha: true, render: (f) => numero(f.horas_catedra) },
        { clave: 'valor_hora', titulo: 'Valor hora', derecha: true, render: (f) => moneda(f.valor_hora) },
        { clave: 'total', titulo: 'Total contrato', derecha: true, render: (f) => <strong>{moneda(f.total)}</strong> },
        { clave: 'grupos', titulo: 'Grupos', derecha: true },
        { clave: 'horas_dictadas', titulo: 'Horas dictadas', derecha: true, render: (f) => `${numero(f.horas_dictadas)} de ${numero(f.horas_catedra)}` },
      ]}
      inicial={{ docente_id: '', periodo_id: '', horas_catedra: 80, valor_hora: '' }}
      campos={[
        { nombre: 'docente_id', etiqueta: 'Docente', tipo: 'select', numerico: true, catalogo: 'docentes_todos', requerido: true, soloCrear: true, ancho: true,
          ayuda: 'Solo se contrata a docentes activos' },
        { nombre: 'periodo_id', etiqueta: 'Periodo', tipo: 'select', numerico: true, catalogo: 'periodos', requerido: true, soloCrear: true,
          ayuda: 'Un contrato por docente y periodo' },
        { nombre: 'horas_catedra', etiqueta: 'Horas cátedra', tipo: 'number', requerido: true, min: 1, max: 1000, mensaje: 'Entre 1 y 1.000 horas', seccion: 'Condiciones',
          ayuda: 'Cada clase son 2,5 horas (6:30 p. m. a 9:00 p. m.)' },
        { nombre: 'valor_hora', etiqueta: 'Valor por hora (pesos)', tipo: 'number', requerido: true, min: 1000, max: 1000000, mensaje: 'Entre $1.000 y $1.000.000, sin decimales',
          patron: /^[0-9]+$/, inputMode: 'numeric', ejemplo: '25000' },
      ]}
    />
  );
}

/** CRUD de programas técnicos. */
export function Programas() {
  return (
    <CrudPage
      titulo="Programas técnicos"
      descripcion="Técnicos Laborales por Competencias que ofrece el instituto."
      recurso="tecnicos"
      singular="Programa"
      escriben={SOLO_COORDINADOR}
      textoBuscar="Buscar por nombre o código…"
      columnas={[
        { clave: 'codigo', titulo: 'Código', render: (f) => <strong>{f.codigo}</strong> },
        { clave: 'nombre', titulo: 'Programa' },
        { clave: 'competencias', titulo: 'Competencias', derecha: true },
        { clave: 'grupos', titulo: 'Grupos', derecha: true },
        { clave: 'activo', titulo: 'Estado', render: (f) => siNo(f.activo) },
      ]}
      inicial={{ codigo: '', nombre: '', activo: 1 }}
      campos={[
        { nombre: 'codigo', etiqueta: 'Código', requerido: true, patron: /^[A-Za-z0-9]{2,10}$/, mensaje: 'Entre 2 y 10 letras o números, sin espacios', maxLength: 10, ayuda: 'Se usa para armar el código de los grupos, por ejemplo SIS' },
        { nombre: 'activo', etiqueta: 'Programa activo', tipo: 'checkbox' },
        { nombre: 'nombre', etiqueta: 'Nombre del programa', requerido: true, minLength: 5, maxLength: 80, ancho: true },
      ]}
    />
  );
}

const DIAS = [
  { valor: 1, texto: 'Lunes' }, { valor: 2, texto: 'Martes' }, { valor: 3, texto: 'Miércoles' },
  { valor: 4, texto: 'Jueves' }, { valor: 5, texto: 'Viernes' }, { valor: 6, texto: 'Sábado' },
];

/** CRUD de grupos y su horario. */
export function Grupos() {
  return (
    <CrudPage
      titulo="Grupos"
      descripcion="Un grupo por programa, periodo y semestre. Jornada única: 6:30 p. m. a 9:00 p. m., dos días a la semana."
      recurso="grupos"
      singular="Grupo"
      escriben={SOLO_COORDINADOR}
      textoBuscar="Buscar por código, programa o docente…"
      describir={(f) => f.codigo}
      complemento={DisponibilidadGrupo}
      complementoTras="dia2"
      tamanoFormulario="amplio"
      columnas={[
        { clave: 'codigo', titulo: 'Grupo', render: (f) => <strong>{f.codigo}</strong> },
        { clave: 'tecnico', titulo: 'Programa', render: (f) => programaCorto(f.tecnico) },
        { clave: 'periodo', titulo: 'Periodo' },
        { clave: 'docente', titulo: 'Docente' },
        { clave: 'aula', titulo: 'Aula', render: (f) => <>{f.aula}<div className="secundario">{f.dias}</div></> },
        { clave: 'matriculados', titulo: 'Cupo', derecha: true, render: (f) => `${f.matriculados} / ${f.cupo_max}` },
        { clave: 'estado', titulo: 'Estado', render: (f) => <Insignia>{f.estado}</Insignia> },
      ]}
      inicial={{ tecnico_id: '', periodo_id: '', semestre: '', docente_id: '', aula_id: '', cupo_min: 15, cupo_max: 30, estado: 'En formación', dia1: '', dia2: '' }}
      campos={[
        { nombre: 'tecnico_id', etiqueta: 'Programa técnico', tipo: 'select', numerico: true, catalogo: 'tecnicos', requerido: true, soloCrear: true, ancho: true },
        { nombre: 'periodo_id', etiqueta: 'Periodo', tipo: 'select', numerico: true, catalogo: 'periodos', requerido: true, soloCrear: true },
        { nombre: 'semestre', etiqueta: 'Semestre', tipo: 'select', numerico: true, requerido: true, soloCrear: true, opciones: [{ valor: 1, texto: 'I semestre' }, { valor: 2, texto: 'II semestre' }] },
        { nombre: 'docente_id', etiqueta: 'Docente', tipo: 'select', numerico: true, requerido: true, seccion: 'Asignación',
          ayuda: 'Solo aparecen los docentes con contrato en el periodo' },
        { nombre: 'aula_id', etiqueta: 'Aula', tipo: 'select', numerico: true, catalogo: 'aulas', requerido: true },
        { nombre: 'dia1', etiqueta: 'Primer día de clase', tipo: 'select', numerico: true, requerido: true, opciones: DIAS },
        { nombre: 'dia2', etiqueta: 'Segundo día de clase', tipo: 'select', numerico: true, requerido: true, opciones: DIAS },
        { nombre: 'cupo_min', etiqueta: 'Cupo mínimo', tipo: 'number', requerido: true, min: 15, max: 30, mensaje: 'El cupo mínimo va de 15 a 30', seccion: 'Cupos y estado' },
        { nombre: 'cupo_max', etiqueta: 'Cupo máximo', tipo: 'number', requerido: true, min: 15, max: 30, mensaje: 'El cupo máximo va de 15 a 30' },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', requerido: true, opciones: opciones(['En formación', 'Activo', 'Cerrado', 'Cancelado']) },
      ]}
    />
  );
}
