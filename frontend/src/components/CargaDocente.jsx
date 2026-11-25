import { useEffect, useState } from 'react';
import { CircleAlert } from 'lucide-react';
import { api } from '../api/http.js';
import Modal from './Modal.jsx';
import { Insignia } from './Tabla.jsx';
import { numero, programaCorto } from '../utils/formato.js';

const VIGENTE = ['En formación', 'Activo'];

/** Grupos de un docente con sus días de clase, aula y estudiantes matriculados en cada uno. */
export default function CargaDocente({ docente, onCerrar }) {
  const [grupos, setGrupos] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.get(`/docentes/${docente.id}/carga`).then(setGrupos).catch((e) => setError(e.message));
  }, [docente.id]);

  const vigentes = (grupos ?? []).filter((g) => VIGENTE.includes(g.estado));
  const estudiantesActuales = vigentes.reduce((t, g) => t + g.matriculados, 0);

  return (
    <Modal
      titulo={`${docente.apellidos} ${docente.nombres}`}
      tamano="amplio"
      onCerrar={onCerrar}
      pie={<button type="button" className="btn btn-secundario" onClick={onCerrar}>Cerrar</button>}
    >
      <div className="modal-cuerpo">
        {error && <div className="alerta error" role="alert"><CircleAlert aria-hidden="true" /><span>{error}</span></div>}
        {!error && !grupos && <p className="secundario">Cargando grupos…</p>}

        {grupos && (
          <>
            <dl className="ficha">
              <div><dt>Grupos en curso</dt><dd>{vigentes.length}</dd></div>
              <div><dt>Estudiantes actuales</dt><dd>{numero(estudiantesActuales)}</dd></div>
              <div><dt>Días que dicta</dt><dd>{docente.dias ?? 'Sin grupos en curso'}</dd></div>
              <div><dt>Grupos en total</dt><dd>{grupos.length}</dd></div>
            </dl>

            {grupos.length === 0 && <p className="tabla-vacia"><strong>Sin grupos</strong>Este docente no tiene grupos asignados.</p>}

            {grupos.map((g) => (
              <details key={g.id} className="grupo-docente" open={VIGENTE.includes(g.estado)}>
                <summary>
                  <span className="grupo-docente-titulo">
                    <strong>{g.codigo}</strong>
                    <span>{programaCorto(g.tecnico)} · {g.periodo}</span>
                  </span>
                  <span className="grupo-docente-horario">{g.dias} · {g.horario} · {g.aula}</span>
                  <span className="grupo-docente-estado">
                    <span className="num">{g.matriculados} estudiantes</span>
                    <Insignia>{g.estado}</Insignia>
                  </span>
                </summary>
                {g.estudiantes.length === 0 ? (
                  <p className="secundario grupo-docente-vacio">No hay estudiantes matriculados en este grupo.</p>
                ) : (
                  <div className="tabla-envoltura">
                    <table className="tabla">
                      <thead>
                        <tr>
                          <th scope="col">Documento</th>
                          <th scope="col">Estudiante</th>
                          <th scope="col">Teléfono</th>
                          <th scope="col" className="derecha">Asistencia</th>
                          <th scope="col">Matrícula</th>
                        </tr>
                      </thead>
                      <tbody>
                        {g.estudiantes.map((e) => (
                          <tr key={e.id}>
                            <td className="num">{e.cedula}</td>
                            <td>{e.estudiante}</td>
                            <td className="num">{e.telefono}</td>
                            <td className="derecha num">{e.asistencia == null ? '—' : `${String(e.asistencia).replace('.', ',')} %`}</td>
                            <td><Insignia>{e.estado}</Insignia></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </details>
            ))}
          </>
        )}
      </div>
    </Modal>
  );
}
