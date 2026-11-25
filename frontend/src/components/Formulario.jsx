import { useCallback, useId, useState } from 'react';
import { CircleAlert } from 'lucide-react';
import { ApiError } from '../api/http.js';

/**
 * Valida los valores del formulario según la definición de los campos.
 * Campo: { nombre, etiqueta, tipo, requerido, patron, mensaje, min, max, maxLength, opciones, catalogo, ancho, soloCrear, ayuda, seccion }
 * Tipos: text | email | tel | date | number | select | textarea | checkbox
 * @returns {Object} errores por nombre de campo
 */
export function validarCampos(campos, valores) {
  const errores = {};
  for (const c of campos) {
    const v = valores[c.nombre];
    if (c.tipo === 'checkbox') continue;
    const vacio = v === '' || v === null || v === undefined;
    if (vacio) {
      if (c.requerido) errores[c.nombre] = 'Este dato es obligatorio';
      continue;
    }
    if (c.patron && !c.patron.test(String(v).trim())) errores[c.nombre] = c.mensaje ?? 'El formato no es válido';
    else if (c.tipo === 'number' && (Number.isNaN(Number(v)) || (c.min !== undefined && Number(v) < c.min) || (c.max !== undefined && Number(v) > c.max))) {
      errores[c.nombre] = c.mensaje ?? `Debe estar entre ${c.min} y ${c.max}`;
    } else if (c.tipo === 'date' && c.max && v > c.max) errores[c.nombre] = c.mensaje ?? 'La fecha no es válida';
    else if (c.minLength && String(v).trim().length < c.minLength) errores[c.nombre] = `Debe tener al menos ${c.minLength} caracteres`;
  }
  return errores;
}

/** Convierte los valores del formulario al tipo que espera la API. */
export function aCarga(campos, valores) {
  const carga = {};
  for (const c of campos) {
    const v = valores[c.nombre];
    if (c.tipo === 'checkbox') carga[c.nombre] = v ? 1 : 0;
    else if (c.tipo === 'number' || c.numerico) carga[c.nombre] = v === '' || v === null || v === undefined ? null : Number(v);
    else carga[c.nombre] = typeof v === 'string' ? v.trim() : (v ?? '');
  }
  return carga;
}

/** Campo de formulario con su etiqueta, ayuda y error. */
export function Campo({ campo, valor, error, alCambiar, opciones, deshabilitado }) {
  const id = useId();
  const idError = `${id}-error`;
  const comunes = {
    id, name: campo.nombre, disabled: deshabilitado, className: 'entrada',
    'aria-invalid': error ? 'true' : undefined, 'aria-describedby': error ? idError : undefined,
  };

  if (campo.tipo === 'checkbox') {
    return (
      <div className={`campo ${campo.ancho ? 'ancho' : ''}`}>
        <label className="casilla" htmlFor={id}>
          <input id={id} type="checkbox" checked={!!valor} disabled={deshabilitado} onChange={(e) => alCambiar(campo.nombre, e.target.checked ? 1 : 0)} />
          {campo.etiqueta}
        </label>
      </div>
    );
  }

  let control;
  if (campo.tipo === 'select') {
    control = (
      <select {...comunes} value={valor ?? ''} onChange={(e) => alCambiar(campo.nombre, e.target.value)}>
        <option value="">Seleccione…</option>
        {(opciones ?? []).map((o) => <option key={o.valor} value={o.valor}>{o.texto}</option>)}
      </select>
    );
  } else if (campo.tipo === 'textarea') {
    control = <textarea {...comunes} value={valor ?? ''} maxLength={campo.maxLength} onChange={(e) => alCambiar(campo.nombre, e.target.value)} />;
  } else {
    control = (
      <input
        {...comunes}
        type={campo.tipo ?? 'text'}
        value={valor ?? ''}
        maxLength={campo.maxLength}
        min={campo.min}
        max={campo.max}
        inputMode={campo.inputMode}
        autoComplete={campo.autoComplete ?? 'off'}
        placeholder={campo.ejemplo}
        onChange={(e) => alCambiar(campo.nombre, e.target.value)}
      />
    );
  }

  return (
    <div className={`campo ${campo.ancho ? 'ancho' : ''}`}>
      <label htmlFor={id}>
        {campo.etiqueta}
        {campo.requerido && <span className="obligatorio" aria-hidden="true">*</span>}
      </label>
      {control}
      {error ? <p className="campo-error" id={idError}>{error}</p> : campo.ayuda && <p className="campo-ayuda">{campo.ayuda}</p>}
    </div>
  );
}

/**
 * Formulario generado a partir de la definición de sus campos.
 * Complemento: componente opcional que se muestra después del campo complementoTras; recibe los valores,
 * puede cambiarlos y puede reemplazar las opciones de una lista con fijarOpciones(campo, opciones).
 */
export default function Formulario({
  campos, inicial, catalogos = {}, editando, textoGuardar = 'Guardar', alGuardar, alCancelar,
  Complemento, complementoTras, idRegistro,
}) {
  const [valores, setValores] = useState(inicial);
  const [opcionesFijadas, setOpcionesFijadas] = useState({});
  const [errores, setErrores] = useState({});
  const [general, setGeneral] = useState(null);
  const [enviando, setEnviando] = useState(false);

  const cambiar = (nombre, valor) => {
    setValores((v) => ({ ...v, [nombre]: valor }));
    setErrores((e) => (e[nombre] ? { ...e, [nombre]: undefined } : e));
  };

  const fijarOpciones = useCallback((nombre, opciones) => {
    setOpcionesFijadas((o) => ({ ...o, [nombre]: opciones }));
  }, []);

  const complemento = Complemento && (
    <div className="campo ancho">
      <Complemento valores={valores} cambiar={cambiar} fijarOpciones={fijarOpciones} idRegistro={idRegistro} />
    </div>
  );

  const enviar = async (e) => {
    e.preventDefault();
    const encontrados = validarCampos(campos, valores);
    setErrores(encontrados);
    setGeneral(Object.keys(encontrados).length ? 'Revise los campos marcados.' : null);
    if (Object.keys(encontrados).length) return;

    setEnviando(true);
    try {
      await alGuardar(aCarga(campos, valores));
    } catch (err) {
      if (err instanceof ApiError) {
        setErrores(err.porCampo);
        setGeneral(err.referencia ? `${err.message} (${err.referencia})` : err.message);
      } else {
        setGeneral('Ocurrió un error inesperado.');
      }
      setEnviando(false);
    }
  };

  return (
    <form onSubmit={enviar} noValidate>
      <div className="modal-cuerpo">
        {general && (
          <div className="alerta error" role="alert" style={{ marginBottom: 16 }}>
            <CircleAlert aria-hidden="true" /><span>{general}</span>
          </div>
        )}
        <div className="form-rejilla">
          {campos.map((c) => (
            <FragmentoCampo key={c.nombre} campo={c}>
              <Campo
                campo={c}
                valor={valores[c.nombre]}
                error={errores[c.nombre]}
                alCambiar={cambiar}
                opciones={opcionesFijadas[c.nombre] ?? (c.catalogo ? catalogos[c.catalogo] : c.opciones)}
                deshabilitado={enviando || (editando && c.soloCrear)}
              />
              {c.nombre === complementoTras && complemento}
            </FragmentoCampo>
          ))}
          {!complementoTras && complemento}
        </div>
      </div>
      <div className="modal-pie">
        <button type="button" className="btn btn-secundario" onClick={alCancelar} disabled={enviando}>Cancelar</button>
        <button type="submit" className="btn btn-primario" disabled={enviando}>{enviando ? 'Guardando…' : textoGuardar}</button>
      </div>
    </form>
  );
}

function FragmentoCampo({ campo, children }) {
  return (
    <>
      {campo.seccion && <div className="form-seccion"><h3>{campo.seccion}</h3></div>}
      {children}
    </>
  );
}
