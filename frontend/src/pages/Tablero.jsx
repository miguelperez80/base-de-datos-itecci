import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/http.js';
import { useAuth } from '../context/AuthContext.jsx';
import { Cabecera, Insignia } from '../components/Tabla.jsx';
import { mes, moneda, monedaCorta, numero, programaCorto } from '../utils/formato.js';

function Indicador({ titulo, valor, nota, acento }) {
  return (
    <div className={`tarjeta indicador ${acento ? 'acento' : ''}`}>
      <h3>{titulo}</h3>
      <div className="valor">{valor}</div>
      {nota && <div className="nota">{nota}</div>}
    </div>
  );
}

export default function Tablero() {
  const { usuario } = useAuth();
  const [datos, setDatos] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.get('/reportes/tablero').then(setDatos).catch((e) => setError(e.message));
  }, []);

  if (error) return <div className="alerta error" role="alert">{error}</div>;
  if (!datos) return <div className="cargando-pagina" style={{ minHeight: '40vh' }} role="status">Cargando indicadores…</div>;

  const { indicadores: i, cartera, recaudo, porTecnico } = datos;
  const maxRecaudo = Math.max(1, ...recaudo.map((r) => r.recaudado));
  const maxTecnico = Math.max(1, ...porTecnico.map((t) => t.matriculas));
  const totalMatriculas = cartera.reduce((s, c) => s + c.matriculas, 0) || 1;

  return (
    <>
      <Cabecera titulo={`Bienvenido, ${usuario.nombre}`} descripcion="Resumen del estado académico y de cartera del instituto." />

      <div className="indicadores">
        <Indicador titulo="Cartera pendiente" valor={moneda(i.cartera_pendiente)} nota={`${numero(i.matriculas_en_mora)} matrículas en mora`} acento />
        <Indicador titulo="Recaudo del mes" valor={moneda(i.recaudo_mes)} nota="Recibos no anulados" acento />
        <Indicador titulo="Matrículas activas" valor={numero(i.matriculas_activas)} nota={`${numero(i.estudiantes)} estudiantes registrados`} />
        <Indicador titulo="Grupos abiertos" valor={numero(i.grupos_abiertos)} nota={`${numero(i.docentes_activos)} docentes activos`} />
      </div>

      <div className="dos-columnas">
        <section className="tarjeta">
          <div className="tarjeta-titulo"><h2>Recaudo por mes</h2><span className="campo-ayuda" style={{ margin: 0 }}>Últimos meses con recibos</span></div>
          <div className="tarjeta-cuerpo">
            {recaudo.length === 0 ? <p className="tabla-vacia">Aún no hay recibos registrados.</p> : (
              <div className="barras" role="img" aria-label={`Recaudo mensual: ${recaudo.map((r) => `${mes(r.mes)} ${moneda(r.recaudado)}`).join(', ')}`}>
                {recaudo.map((r) => (
                  <div className="columna" key={r.mes} title={`${mes(r.mes)}: ${moneda(r.recaudado)} en ${r.recibos} recibos`}>
                    <span className="cifra">{monedaCorta(r.recaudado)}</span>
                    <div className="barra" style={{ height: `${(r.recaudado / maxRecaudo) * 100}%` }} />
                    <span className="eje">{mes(r.mes)}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </section>

        <section className="tarjeta">
          <div className="tarjeta-titulo"><h2>Estado de crédito</h2><Link to="/cartera">Ver cartera</Link></div>
          <div className="tabla-envoltura">
            <table className="tabla">
              <thead><tr><th scope="col">Estado</th><th scope="col" className="derecha">Matrículas</th><th scope="col" className="derecha">Saldo</th></tr></thead>
              <tbody>
                {cartera.map((c) => (
                  <tr key={c.estado}>
                    <td><Insignia>{c.estado}</Insignia></td>
                    <td className="derecha num">{numero(c.matriculas)} <span className="secundario">({Math.round((c.matriculas / totalMatriculas) * 100)} %)</span></td>
                    <td className="derecha num">{moneda(c.saldo)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section className="tarjeta">
        <div className="tarjeta-titulo"><h2>Matrículas por programa técnico</h2><span className="campo-ayuda" style={{ margin: 0 }}>Sin contar retiros</span></div>
        <div className="tarjeta-cuerpo">
          <div className="barras-h">
            {porTecnico.map((t) => (
              <div className="fila-barra" key={t.codigo}>
                <span>{programaCorto(t.tecnico)}</span>
                <strong className="num">{numero(t.matriculas)}</strong>
                <div className="pista" aria-hidden="true"><div className="relleno" style={{ width: `${(t.matriculas / maxTecnico) * 100}%` }} /></div>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
