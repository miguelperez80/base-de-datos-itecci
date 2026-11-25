import { useEffect, useId, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { CircleAlert } from 'lucide-react';
import { api, ApiError } from '../api/http.js';
import { ROLES, useAuth } from '../context/AuthContext.jsx';
import { useAvisos } from '../context/AvisosContext.jsx';
import { Cabecera, Insignia } from '../components/Tabla.jsx';
import Modal, { Confirmacion } from '../components/Modal.jsx';
import { fecha, programaCorto } from '../utils/formato.js';

const formatoNota = (n) => (n === null || n === undefined ? '—' : Number(n).toFixed(1).replace('.', ','));
const tonoNota = (n) => (n === null || n === undefined ? '' : n >= 3 ? 'aprobada' : 'perdida');
const NOTA_VALIDA = /^[1-5]([.,][0-9])?$/;

/** Campo para escribir una nota y guardarla, con su validación y el registro de quién la guardó. */
function CampoNota({ titulo, nota, deshabilitado, motivo, ocupado, alGuardar, alEliminar }) {
  const id = useId();
  const [valor, setValor] = useState(nota ? formatoNota(nota.nota) : '');
  const [error, setError] = useState(null);

  const guardar = (e) => {
    e.preventDefault();
    const texto = valor.trim();
    if (!NOTA_VALIDA.test(texto) || Number(texto.replace(',', '.')) > 5) {
      setError('Escriba una nota de 1,0 a 5,0 con un decimal');
      return;
    }
    setError(null);
    alGuardar(texto.replace(',', '.'));
  };

  return (
    <form className="nota-bloque" onSubmit={guardar} noValidate>
      <label htmlFor={id}><h3>{titulo}</h3></label>
      {deshabilitado ? (
        <p className="secundario">{motivo}</p>
      ) : (
        <>
          <div className="nota-fila">
            <input
              id={id}
              className="entrada nota-entrada num"
              inputMode="decimal"
              maxLength={3}
              placeholder="3,5"
              value={valor}
              disabled={ocupado}
              aria-invalid={error ? 'true' : undefined}
              onChange={(e) => { setValor(e.target.value); setError(null); }}
            />
            <button type="submit" className="btn btn-primario" disabled={ocupado}>
              {nota ? 'Corregir' : 'Registrar'}
            </button>
            {nota && alEliminar && (
              <button type="button" className="btn btn-peligro" disabled={ocupado} onClick={alEliminar}>Eliminar</button>
            )}
          </div>
          {error && <p className="campo-error">{error}</p>}
          {nota && !error && (
            <p className="campo-ayuda">
              Registrada el {fecha(nota.fecha)}{nota.registrado_por ? ` por ${nota.registrado_por}` : ''}
            </p>
          )}
        </>
      )}
    </form>
  );
}

/** Ventana para registrar, corregir o eliminar la nota ordinaria y el supletorio de una competencia. */
function EditarNota({ estudiante, competencia, alCerrar, alCambiar }) {
  const { tieneRol } = useAuth();
  const avisos = useAvisos();
  const [ocupado, setOcupado] = useState(false);
  const [error, setError] = useState(null);
  const [porEliminar, setPorEliminar] = useState(null);
  const { ordinaria, supletorio } = estudiante.notas[competencia.id];
  const puedeEliminar = tieneRol([ROLES.COORDINADOR]);

  const ejecutar = async (accion, mensaje) => {
    setOcupado(true);
    setError(null);
    try {
      await accion();
      avisos.exito(mensaje);
      alCambiar();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Ocurrió un error inesperado.');
      setOcupado(false);
    }
  };

  const guardar = (tipo, existente) => (nota) => ejecutar(
    () => (existente
      ? api.put(`/calificaciones/${existente.id}`, { nota })
      : api.post('/calificaciones', { matricula_id: estudiante.matricula_id, competencia_id: competencia.id, tipo, nota })),
    `Nota ${tipo.toLowerCase()} ${existente ? 'corregida' : 'registrada'}`,
  );

  const eliminar = () => {
    const nota = porEliminar;
    setPorEliminar(null);
    ejecutar(() => api.delete(`/calificaciones/${nota.id}`), `Nota ${nota.tipo.toLowerCase()} eliminada`);
  };

  const supletorioHabilitado = ordinaria && ordinaria.nota < 3;

  return (
    <>
      <Modal
        titulo={`Competencia ${competencia.orden}: ${competencia.nombre}`}
        onCerrar={alCerrar}
        pie={<button type="button" className="btn btn-secundario" onClick={alCerrar}>Cerrar</button>}
      >
        <div className="modal-cuerpo">
          <dl className="ficha">
            <div><dt>Estudiante</dt><dd>{estudiante.estudiante}</dd></div>
            <div><dt>Documento</dt><dd className="num">{estudiante.cedula}</dd></div>
            <div><dt>Nota definitiva</dt><dd>{formatoNota(estudiante.notas[competencia.id].definitiva)}</dd></div>
          </dl>
          {error && (
            <div className="alerta error" role="alert" style={{ marginBottom: 16 }}>
              <CircleAlert aria-hidden="true" /><span>{error}</span>
            </div>
          )}
          <CampoNota
            key={`o${ordinaria?.id}${ordinaria?.nota}`}
            titulo="Nota ordinaria"
            nota={ordinaria}
            ocupado={ocupado}
            alGuardar={guardar('Ordinaria', ordinaria)}
            alEliminar={puedeEliminar ? () => setPorEliminar(ordinaria) : undefined}
          />
          <CampoNota
            key={`s${supletorio?.id}${supletorio?.nota}`}
            titulo="Supletorio"
            nota={supletorio}
            deshabilitado={!supletorioHabilitado && !supletorio}
            motivo={ordinaria ? 'Solo hay supletorio si la nota ordinaria es menor a 3,0 (RN-22).' : 'Registre primero la nota ordinaria.'}
            ocupado={ocupado}
            alGuardar={guardar('Supletorio', supletorio)}
            alEliminar={puedeEliminar ? () => setPorEliminar(supletorio) : undefined}
          />
          <p className="campo-ayuda">
            Escala de 1,0 a 5,0; se aprueba con 3,0. El supletorio reemplaza a la nota ordinaria y se presenta una sola vez.
          </p>
        </div>
      </Modal>
      {porEliminar && (
        <Confirmacion
          titulo="Eliminar nota"
          mensaje={`¿Seguro que desea eliminar la nota ${porEliminar.tipo.toLowerCase()} de ${formatoNota(porEliminar.nota)}?`}
          onConfirmar={eliminar}
          onCerrar={() => setPorEliminar(null)}
        />
      )}
    </>
  );
}

/** Planilla de notas por grupo: registro y corrección de notas ordinarias y supletorios de cada competencia. */
export default function Calificaciones() {
  const avisos = useAvisos();
  const [parametros, setParametros] = useSearchParams();
  const grupoId = parametros.get('grupo') ?? '';
  const [grupos, setGrupos] = useState([]);
  const [planilla, setPlanilla] = useState(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState(null);
  const [edicion, setEdicion] = useState(null);

  useEffect(() => {
    api.get('/catalogos/grupos_notas').then(setGrupos).catch((e) => avisos.error(e.message));
  }, []);

  const cargar = () => {
    if (!grupoId) { setPlanilla(null); return; }
    setCargando(true);
    setError(null);
    api.get(`/calificaciones/grupos/${grupoId}`)
      .then(setPlanilla)
      .catch((e) => setError(e.message))
      .finally(() => setCargando(false));
  };

  useEffect(cargar, [grupoId]);

  const elegirGrupo = (valor) => setParametros(valor ? { grupo: valor } : {});

  const recargarTrasCambio = () => {
    setEdicion(null);
    cargar();
  };

  const g = planilla?.grupo;
  const vigentes = planilla?.estudiantes.filter((e) => e.estado !== 'Retirada') ?? [];

  return (
    <>
      <Cabecera
        titulo="Calificaciones"
        descripcion="Notas de las competencias de cada grupo, a partir de las planillas que entrega el docente."
      />

      <section className="tarjeta">
        <div className="herramientas">
          <label className="campo selector-grupo">
            <span className="sr-only">Grupo</span>
            <select className="entrada" value={grupoId} onChange={(e) => elegirGrupo(e.target.value)}>
              <option value="">Elija un grupo…</option>
              {grupos.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
          </label>
        </div>

        {!grupoId && <div className="tabla-vacia"><strong>Elija un grupo</strong>Se mostrará la planilla de notas de sus estudiantes.</div>}
        {error && <div className="tabla-vacia" role="alert"><strong>No se pudo cargar la planilla</strong>{error}</div>}
        {grupoId && cargando && !planilla && <div className="tabla-vacia">Cargando planilla…</div>}

        {planilla && g && (
          <div className="tarjeta-cuerpo">
            <dl className="ficha">
              <div><dt>Programa</dt><dd>{programaCorto(g.tecnico)}</dd></div>
              <div><dt>Periodo</dt><dd>{g.periodo} · semestre {g.semestre}</dd></div>
              <div><dt>Docente</dt><dd>{g.docente}</dd></div>
              <div><dt>Estudiantes</dt><dd>{vigentes.length}</dd></div>
              <div><dt>Estado del grupo</dt><dd><Insignia>{g.estado}</Insignia></dd></div>
            </dl>

            <div className="tabla-envoltura">
              <table className="tabla planilla">
                <thead>
                  <tr>
                    <th scope="col">Estudiante</th>
                    {planilla.competencias.map((c) => (
                      <th key={c.id} scope="col" className="derecha" title={c.nombre}>
                        C{c.orden}<span className="planilla-competencia">{c.nombre}</span>
                      </th>
                    ))}
                    <th scope="col" className="derecha">Promedio</th>
                    <th scope="col" className="derecha">Aprobadas</th>
                    <th scope="col" className="derecha">Asistencia</th>
                    <th scope="col">Crédito</th>
                  </tr>
                </thead>
                <tbody>
                  {planilla.estudiantes.length === 0 && (
                    <tr><td colSpan={planilla.competencias.length + 5}><div className="tabla-vacia">El grupo no tiene estudiantes matriculados.</div></td></tr>
                  )}
                  {planilla.estudiantes.map((e) => {
                    const retirada = e.estado === 'Retirada';
                    return (
                      <tr key={e.matricula_id} className={retirada ? 'retirada' : undefined}>
                        <td>
                          <strong>{e.estudiante}</strong>
                          <div className="secundario num">{e.cedula}{retirada && ' · Retirada'}</div>
                        </td>
                        {planilla.competencias.map((c) => {
                          const n = e.notas[c.id];
                          return (
                            <td key={c.id} className="derecha">
                              <button
                                type="button"
                                className={`celda-nota ${tonoNota(n.definitiva)}`}
                                disabled={retirada}
                                onClick={() => setEdicion({ estudiante: e, competencia: c })}
                                aria-label={`Nota de ${e.estudiante} en la competencia ${c.orden}: ${formatoNota(n.definitiva)}`}
                              >
                                {formatoNota(n.definitiva)}
                                {n.supletorio && <span className="celda-nota-detalle">sup. · ord. {formatoNota(n.ordinaria?.nota)}</span>}
                              </button>
                            </td>
                          );
                        })}
                        <td className="derecha num">{formatoNota(e.promedio)}</td>
                        <td className="derecha num">{e.aprobadas} / {planilla.competencias.length}</td>
                        <td className={`derecha num ${e.asistencia !== null && e.asistencia < 80 ? 'texto-mal' : ''}`}>
                          {e.asistencia === null ? '—' : `${String(e.asistencia).replace('.', ',')} %`}
                        </td>
                        <td>{e.credito ? <Insignia>{e.credito}</Insignia> : '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <p className="campo-ayuda planilla-leyenda">
              Haga clic en una nota para registrarla o corregirla. Verde: aprobada (3,0 o más); rojo: perdida. Asistencia en rojo:
              por debajo del 80 % exigido para el diploma. Los estudiantes en mora no reciben su boletín hasta ponerse al día (RN-25).
            </p>
          </div>
        )}
      </section>

      {edicion && (
        <EditarNota
          estudiante={edicion.estudiante}
          competencia={edicion.competencia}
          alCerrar={() => setEdicion(null)}
          alCambiar={recargarTrasCambio}
        />
      )}
    </>
  );
}
