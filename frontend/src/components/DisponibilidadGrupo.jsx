import { useEffect, useState } from 'react';
import { CircleAlert, CircleCheck } from 'lucide-react';
import { api } from '../api/http.js';

export const DIAS_SEMANA = [
  { valor: 1, corto: 'Lun', largo: 'Lunes' }, { valor: 2, corto: 'Mar', largo: 'Martes' },
  { valor: 3, corto: 'Mié', largo: 'Miércoles' }, { valor: 4, corto: 'Jue', largo: 'Jueves' },
  { valor: 5, corto: 'Vie', largo: 'Viernes' }, { valor: 6, corto: 'Sáb', largo: 'Sábado' },
];

const grupoDelDia = (fila, dia) => fila?.ocupacion.find((o) => o.dia === dia)?.grupo;
const diasLibres = (fila) => DIAS_SEMANA.filter((d) => !grupoDelDia(fila, d.valor));
const listaDias = (dias) => dias.map((d) => d.corto).join(', ');

const textoDocente = (d) => {
  const ocupados = DIAS_SEMANA.filter((x) => grupoDelDia(d, x.valor));
  return `${d.nombre} — ${ocupados.length ? `dicta ${listaDias(ocupados)}` : 'sin grupos'}`;
};

const textoAula = (a) => {
  const libres = diasLibres(a);
  return `${a.nombre} (${a.capacidad} puestos) — ${libres.length ? `libre ${listaDias(libres)}` : 'sin días libres'}`;
};

/**
 * Disponibilidad de docentes y aulas del periodo elegido en el formulario de grupos.
 * Limita la lista de docentes a los que tienen contrato en el periodo, indica en cada opción los días
 * ocupados o libres y muestra la ocupación por día, los cruces con los días elegidos y los días libres en común.
 */
export default function DisponibilidadGrupo({ valores, cambiar, fijarOpciones, idRegistro }) {
  const periodo = valores.periodo_id ? Number(valores.periodo_id) : null;
  const [datos, setDatos] = useState(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!periodo) {
      setDatos(null);
      fijarOpciones('docente_id', []);
      return undefined;
    }
    let vigente = true;
    setCargando(true);
    setError(null);
    const consulta = new URLSearchParams({ periodo_id: periodo, ...(idRegistro ? { grupo_id: idRegistro } : {}) });
    api.get(`/grupos/disponibilidad?${consulta}`)
      .then((r) => {
        if (!vigente) return;
        setDatos(r);
        fijarOpciones('docente_id', r.docentes.map((d) => ({ valor: d.id, texto: textoDocente(d) })));
        fijarOpciones('aula_id', r.aulas.map((a) => ({ valor: a.id, texto: textoAula(a) })));
        if (valores.docente_id && !r.docentes.some((d) => d.id === Number(valores.docente_id))) cambiar('docente_id', '');
      })
      .catch((e) => vigente && setError(e.message))
      .finally(() => vigente && setCargando(false));
    return () => { vigente = false; };
  }, [periodo, idRegistro]);

  if (!periodo) {
    return <p className="alerta info">Elija el periodo para ver los docentes con contrato y la disponibilidad de las aulas.</p>;
  }
  if (error) return <p className="alerta error" role="alert"><CircleAlert aria-hidden="true" />{error}</p>;
  if (cargando || !datos) return <p className="alerta info">Consultando disponibilidad…</p>;

  const docente = datos.docentes.find((d) => d.id === Number(valores.docente_id));
  const aula = datos.aulas.find((a) => a.id === Number(valores.aula_id));
  const elegidos = [valores.dia1, valores.dia2].filter(Boolean).map(Number);

  const cruces = [];
  for (const dia of elegidos) {
    const nombre = DIAS_SEMANA.find((d) => d.valor === dia)?.largo;
    const gDocente = grupoDelDia(docente, dia);
    const gAula = grupoDelDia(aula, dia);
    if (gDocente) cruces.push(`El docente dicta el ${nombre} el grupo ${gDocente}`);
    if (gAula) cruces.push(`${aula.nombre} está ocupada el ${nombre} por el grupo ${gAula}`);
  }

  const comunes = docente && aula
    ? DIAS_SEMANA.filter((d) => !grupoDelDia(docente, d.valor) && !grupoDelDia(aula, d.valor))
    : [];

  const filas = [
    ...datos.aulas.map((a) => ({ clave: `a${a.id}`, nombre: `${a.nombre} (${a.capacidad})`, fila: a, elegida: a.id === aula?.id })),
    ...datos.docentes.map((d) => ({ clave: `d${d.id}`, nombre: d.nombre, fila: d, elegida: d.id === docente?.id, docente: true })),
  ];

  return (
    <div className="disponibilidad">
      <h3>Disponibilidad del periodo · 6:30 p. m. a 9:00 p. m.</h3>

      {datos.docentes.length === 0 && (
        <p className="alerta error" role="alert">
          <CircleAlert aria-hidden="true" />
          Ningún docente activo tiene contrato en este periodo. Regístrelo primero en Contratos docentes.
        </p>
      )}

      {cruces.length > 0 && (
        <div className="alerta error" role="alert">
          <CircleAlert aria-hidden="true" />
          <span>{cruces.join('. ')}.</span>
        </div>
      )}

      {docente && aula && cruces.length === 0 && elegidos.length === 2 && (
        <p className="alerta ok"><CircleCheck aria-hidden="true" />El docente y el aula están libres los días elegidos.</p>
      )}

      {docente && aula && (cruces.length > 0 || elegidos.length < 2) && (
        <div className="disponibilidad-sugerencia">
          {comunes.length >= 2 ? (
            <>
              <span>Libres para ambos: <strong>{comunes.map((d) => d.largo).join(', ')}</strong></span>
              <button
                type="button"
                className="btn btn-secundario"
                onClick={() => { cambiar('dia1', comunes[0].valor); cambiar('dia2', comunes[1].valor); }}
              >
                Usar {comunes[0].largo} y {comunes[1].largo}
              </button>
            </>
          ) : (
            <span>El docente y el aula no tienen dos días libres en común. Elija otra aula u otro docente.</span>
          )}
        </div>
      )}

      <div className="tabla-envoltura">
        <table className="tabla disponibilidad-tabla">
          <thead>
            <tr>
              <th scope="col">Aula / docente</th>
              {DIAS_SEMANA.map((d) => (
                <th key={d.valor} scope="col" className={elegidos.includes(d.valor) ? 'dia-elegido' : undefined}>{d.corto}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filas.map((f, i) => (
              <tr key={f.clave} className={`${f.elegida ? 'fila-elegida' : ''} ${f.docente && !filas[i - 1]?.docente ? 'inicio-docentes' : ''}`}>
                <th scope="row">{f.nombre}</th>
                {DIAS_SEMANA.map((d) => {
                  const grupo = grupoDelDia(f.fila, d.valor);
                  return (
                    <td key={d.valor} className={`${grupo ? 'ocupado' : 'libre'} ${elegidos.includes(d.valor) ? 'dia-elegido' : ''}`}>
                      {grupo ?? 'Libre'}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
