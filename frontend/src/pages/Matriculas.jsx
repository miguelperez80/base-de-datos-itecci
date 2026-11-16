import { useEffect, useState } from 'react';
import { CircleAlert, Plus } from 'lucide-react';
import { api, ApiError } from '../api/http.js';
import { useAvisos } from '../context/AvisosContext.jsx';
import { useListado } from '../hooks/useListado.js';
import { Buscador, Cabecera, Insignia, Paginacion, Pestanas, Tabla } from '../components/Tabla.jsx';
import Modal from '../components/Modal.jsx';
import DetalleMatricula from '../components/DetalleMatricula.jsx';
import { fecha, moneda } from '../utils/formato.js';

const ESTADOS = [
  { valor: null, texto: 'Todas' }, { valor: 'Activa', texto: 'Activas' },
  { valor: 'Finalizada', texto: 'Finalizadas' }, { valor: 'Retirada', texto: 'Retiradas' },
];

// Asistente de matrícula: elegir estudiante (búsqueda) y grupo abierto. Las reglas las aplica sp_matricular.
function NuevaMatricula({ alCerrar, alCrear }) {
  const estudiantes = useListado('/estudiantes', { porPagina: 6 });
  const [estudiante, setEstudiante] = useState(null);
  const [grupos, setGrupos] = useState([]);
  const [grupoId, setGrupoId] = useState('');
  const [error, setError] = useState(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    api.get('/catalogos/grupos_abiertos').then(setGrupos).catch((e) => setError(e.message));
  }, []);

  const enviar = async (e) => {
    e.preventDefault();
    if (!estudiante || !grupoId) {
      setError('Seleccione el estudiante y el grupo.');
      return;
    }
    setEnviando(true);
    setError(null);
    try {
      alCrear(await api.post('/matriculas', { estudiante_id: estudiante.id, grupo_id: Number(grupoId) }));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Ocurrió un error inesperado.');
      setEnviando(false);
    }
  };

  return (
    <Modal titulo="Nueva matrícula" onCerrar={alCerrar}>
      <form onSubmit={enviar} noValidate>
        <div className="modal-cuerpo">
          {error && <div className="alerta error" role="alert" style={{ marginBottom: 16 }}><CircleAlert aria-hidden="true" /><span>{error}</span></div>}

          <div className="campo">
            <span className="etiqueta">1. Estudiante<span className="obligatorio" aria-hidden="true">*</span></span>
            {estudiante ? (
              <div className="alerta info" style={{ alignItems: 'center', justifyContent: 'space-between' }}>
                <span><strong>{estudiante.apellidos} {estudiante.nombres}</strong> · {estudiante.tipo_documento} {estudiante.cedula}</span>
                <button type="button" className="btn btn-secundario" onClick={() => setEstudiante(null)} disabled={enviando}>Cambiar</button>
              </div>
            ) : (
              <>
                <Buscador valor={estudiantes.busqueda} alCambiar={estudiantes.setBusqueda} texto="Buscar por nombre o documento…" />
                <div className="opciones-lista">
                  {estudiantes.datos.map((f) => (
                    <button type="button" key={f.id} onClick={() => setEstudiante(f)}>
                      <strong>{f.apellidos} {f.nombres}</strong> · {f.tipo_documento} {f.cedula}
                      {f.documentos < 2 && <span className="campo-error"> · faltan documentos requisito</span>}
                    </button>
                  ))}
                  {!estudiantes.cargando && estudiantes.datos.length === 0 && <p className="tabla-vacia">No se encontró ningún estudiante. Regístrelo primero en la sección Estudiantes.</p>}
                </div>
              </>
            )}
          </div>

          <div className="campo" style={{ marginTop: 16 }}>
            <label htmlFor="grupo">2. Grupo<span className="obligatorio" aria-hidden="true">*</span></label>
            <select id="grupo" className="entrada" value={grupoId} onChange={(e) => setGrupoId(e.target.value)} disabled={enviando}>
              <option value="">Seleccione un grupo abierto…</option>
              {grupos.map((g) => <option key={g.id} value={g.id}>{g.nombre}</option>)}
            </select>
            <p className="campo-ayuda">Al matricular se genera el plan de pagos: matrícula de $70.000 y cuatro cuotas ($150.000 + 3 de $100.000).</p>
          </div>
        </div>
        <div className="modal-pie">
          <button type="button" className="btn btn-secundario" onClick={alCerrar} disabled={enviando}>Cancelar</button>
          <button type="submit" className="btn btn-primario" disabled={enviando}>{enviando ? 'Matriculando…' : 'Matricular'}</button>
        </div>
      </form>
    </Modal>
  );
}

export default function Matriculas() {
  const avisos = useAvisos();
  const [estado, setEstado] = useState(null);
  const lista = useListado('/matriculas', { estado });
  const [detalle, setDetalle] = useState(null);
  const [nueva, setNueva] = useState(false);

  return (
    <>
      <Cabecera titulo="Matrículas" descripcion="Matrícula de estudiantes en los grupos, con su plan de pagos. Pulse una fila para ver el detalle o registrar un pago.">
        <button type="button" className="btn btn-primario" onClick={() => setNueva(true)}><Plus aria-hidden="true" /> Nueva matrícula</button>
      </Cabecera>

      <section className="tarjeta">
        <div className="herramientas">
          <Buscador valor={lista.busqueda} alCambiar={lista.setBusqueda} texto="Buscar por estudiante, documento o grupo…" />
          <Pestanas opciones={ESTADOS} valor={estado} alCambiar={setEstado} etiqueta="Filtrar por estado" />
        </div>
        <Tabla
          filas={lista.datos}
          cargando={lista.cargando}
          error={lista.error}
          alPulsarFila={(f) => setDetalle(f.id)}
          columnas={[
            { clave: 'id', titulo: 'N.º', render: (f) => <span className="num">{f.id}</span> },
            { clave: 'estudiante', titulo: 'Estudiante', render: (f) => <><strong>{f.estudiante}</strong><div className="secundario num">{f.cedula}</div></> },
            { clave: 'grupo', titulo: 'Grupo' },
            { clave: 'fecha_ingreso', titulo: 'Ingreso', render: (f) => fecha(f.fecha_ingreso) },
            { clave: 'estado', titulo: 'Matrícula', render: (f) => <Insignia>{f.estado}</Insignia> },
            { clave: 'estado_credito', titulo: 'Crédito', render: (f) => <Insignia>{f.estado_credito}</Insignia> },
            { clave: 'saldo', titulo: 'Saldo', derecha: true, render: (f) => moneda(f.saldo) },
          ]}
        />
        <Paginacion pagina={lista.pagina} paginas={lista.paginas} total={lista.total} alCambiar={lista.setPagina} />
      </section>

      {nueva && (
        <NuevaMatricula
          alCerrar={() => setNueva(false)}
          alCrear={(m) => { setNueva(false); avisos.exito(`Matrícula N.º ${m.id} registrada en ${m.grupo}`); lista.recargar(); setDetalle(m.id); }}
        />
      )}
      {detalle && <DetalleMatricula id={detalle} alCerrar={() => setDetalle(null)} alCambiar={lista.recargar} />}
    </>
  );
}
