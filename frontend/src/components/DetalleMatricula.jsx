import { useCallback, useEffect, useState } from 'react';
import { Ban, Banknote, UserMinus } from 'lucide-react';
import { api } from '../api/http.js';
import { useAuth } from '../context/AuthContext.jsx';
import { useAvisos } from '../context/AvisosContext.jsx';
import { fecha, moneda } from '../utils/formato.js';
import Modal from './Modal.jsx';
import Formulario from './Formulario.jsx';
import { Insignia } from './Tabla.jsx';

/** Detalle de una matrícula con su plan de pagos y recibos; permite registrar pagos, anular recibos y retirar la matrícula. */
export default function DetalleMatricula({ id, alCerrar, alCambiar }) {
  const { esCoordinador } = useAuth();
  const avisos = useAvisos();
  const [m, setM] = useState(null);
  const [modo, setModo] = useState('ver');
  const [medios, setMedios] = useState([]);

  const cargar = useCallback(() => api.get(`/matriculas/${id}`).then(setM).catch((e) => { avisos.error(e.message); alCerrar(); }),
    [id]);

  useEffect(() => {
    cargar();
    api.get('/catalogos/medios_pago').then((f) => setMedios(f.map((x) => ({ valor: x.id, texto: x.nombre })))).catch(() => {});
  }, [cargar]);

  const terminar = async (mensaje) => {
    avisos.exito(mensaje);
    setModo('ver');
    await cargar();
    alCambiar?.();
  };

  const registrarPago = async (carga) => {
    const recibo = await api.post('/pagos', { ...carga, matricula_id: id });
    await terminar(`Recibo de caja N.º ${recibo.numero_recibo} registrado`);
  };
  const retirar = async (carga) => {
    await api.post(`/matriculas/${id}/retiro`, carga);
    await terminar('Matrícula retirada');
  };
  const anular = async (carga) => {
    await api.post(`/pagos/${modo.anular.id}/anulacion`, carga);
    await terminar(`Recibo N.º ${modo.anular.numero_recibo} anulado`);
  };

  if (!m) {
    return <Modal titulo="Matrícula" tamano="amplio" onCerrar={alCerrar}><div className="modal-cuerpo" role="status">Cargando…</div></Modal>;
  }

  if (modo === 'pago') {
    return (
      <Modal titulo={`Registrar pago · ${m.estudiante}`} tamano="estrecho" onCerrar={() => setModo('ver')}>
        <Formulario
          textoGuardar="Registrar pago"
          inicial={{ valor: '', medio_pago_id: '', referencia: '' }}
          catalogos={{ medios }}
          campos={[
            { nombre: 'valor', etiqueta: 'Valor recibido (pesos)', tipo: 'number', requerido: true, min: 1000, max: m.saldo, ancho: true,
              mensaje: `El valor debe estar entre $1.000 y el saldo (${moneda(m.saldo)})`, ayuda: `Saldo pendiente: ${moneda(m.saldo)}. Se aplica a las cuotas más antiguas.` },
            { nombre: 'medio_pago_id', etiqueta: 'Medio de pago', tipo: 'select', numerico: true, catalogo: 'medios', requerido: true, ancho: true },
            { nombre: 'referencia', etiqueta: 'Referencia (opcional)', maxLength: 60, ancho: true, ayuda: 'Número de transferencia o comprobante' },
          ]}
          alGuardar={registrarPago}
          alCancelar={() => setModo('ver')}
        />
      </Modal>
    );
  }

  if (modo === 'retiro' || modo.anular) {
    const esRetiro = modo === 'retiro';
    return (
      <Modal titulo={esRetiro ? `Retirar matrícula · ${m.estudiante}` : `Anular recibo N.º ${modo.anular.numero_recibo}`} tamano="estrecho" onCerrar={() => setModo('ver')}>
        <Formulario
          textoGuardar={esRetiro ? 'Retirar matrícula' : 'Anular recibo'}
          inicial={{ [esRetiro ? 'observacion' : 'motivo']: '' }}
          campos={[{
            nombre: esRetiro ? 'observacion' : 'motivo', etiqueta: esRetiro ? 'Motivo del retiro' : 'Motivo de la anulación',
            tipo: 'textarea', requerido: true, minLength: 5, maxLength: 250, ancho: true,
            ayuda: esRetiro ? 'El retiro no se puede deshacer. Las cuotas pendientes siguen en cartera.' : `Se anulará el recibo por ${moneda(modo.anular.valor)} y el saldo volverá a quedar pendiente.`,
          }]}
          alGuardar={esRetiro ? retirar : anular}
          alCancelar={() => setModo('ver')}
        />
      </Modal>
    );
  }

  return (
    <Modal
      titulo={`Matrícula N.º ${m.id}`}
      tamano="amplio"
      onCerrar={alCerrar}
      pie={(
        <>
          {m.estado === 'Activa' && (
            <button type="button" className="btn btn-peligro" onClick={() => setModo('retiro')}><UserMinus aria-hidden="true" /> Retirar matrícula</button>
          )}
          <button type="button" className="btn btn-secundario" onClick={alCerrar}>Cerrar</button>
          {m.saldo > 0 && (
            <button type="button" className="btn btn-primario" onClick={() => setModo('pago')}><Banknote aria-hidden="true" /> Registrar pago</button>
          )}
        </>
      )}
    >
      <div className="modal-cuerpo">
        <dl className="ficha">
          <div><dt>Estudiante</dt><dd>{m.estudiante}</dd></div>
          <div><dt>Documento</dt><dd className="num">{m.cedula}</dd></div>
          <div><dt>Grupo</dt><dd>{m.grupo} · semestre {m.semestre}</dd></div>
          <div><dt>Ingreso</dt><dd>{fecha(m.fecha_ingreso)}</dd></div>
          <div><dt>Matrícula</dt><dd><Insignia>{m.estado}</Insignia></dd></div>
          <div><dt>Crédito</dt><dd><Insignia>{m.estado_credito}</Insignia>{m.dias_mora > 0 && <span className="campo-ayuda"> {m.dias_mora} días de mora</span>}</dd></div>
          <div><dt>Total pagado</dt><dd className="num">{moneda(m.total_pagado)} de {moneda(m.total_obligado)}</dd></div>
          <div><dt>Saldo</dt><dd className="num" style={{ color: m.saldo > 0 ? 'var(--rojo-oscuro)' : 'var(--ok)' }}>{moneda(m.saldo)}</dd></div>
        </dl>
        {m.observaciones && <div className="alerta info"><span><strong>Observación:</strong> {m.observaciones}</span></div>}

        <h3 className="seccion-titulo">Plan de pagos</h3>
        <div className="tabla-envoltura">
          <table className="tabla">
            <thead><tr><th scope="col">Concepto</th><th scope="col">Vence</th><th scope="col" className="derecha">Valor</th><th scope="col" className="derecha">Pagado</th><th scope="col" className="derecha">Saldo</th><th scope="col">Estado</th></tr></thead>
            <tbody>
              {m.cuotas.map((c) => (
                <tr key={c.numero}>
                  <td>{c.numero === 0 ? 'Matrícula' : `Cuota ${c.numero}`}</td>
                  <td>{fecha(c.fecha_vencimiento)}</td>
                  <td className="derecha num">{moneda(c.valor)}</td>
                  <td className="derecha num">{moneda(c.pagado)}</td>
                  <td className="derecha num">{moneda(c.saldo)}</td>
                  <td><Insignia>{c.estado}</Insignia></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <h3 className="seccion-titulo">Recibos de caja</h3>
        {m.pagos.length === 0 ? <p className="campo-ayuda">Esta matrícula aún no tiene pagos.</p> : (
          <div className="tabla-envoltura">
            <table className="tabla">
              <thead><tr><th scope="col">Recibo</th><th scope="col">Fecha</th><th scope="col">Medio</th><th scope="col" className="derecha">Valor</th><th scope="col">Estado</th>{esCoordinador && <th scope="col" className="acciones"><span className="sr-only">Acciones</span></th>}</tr></thead>
              <tbody>
                {m.pagos.map((p) => (
                  <tr key={p.id}>
                    <td className="num">{p.numero_recibo}</td>
                    <td>{fecha(p.fecha_pago)}</td>
                    <td>{p.medio_pago}{p.referencia && <div className="secundario">{p.referencia}</div>}</td>
                    <td className="derecha num">{moneda(p.valor)}</td>
                    <td>{p.anulado ? <Insignia>Anulado</Insignia> : <Insignia tono="ok">Vigente</Insignia>}</td>
                    {esCoordinador && (
                      <td className="acciones">
                        {!p.anulado && (
                          <button type="button" className="btn btn-icono peligro" onClick={() => setModo({ anular: p })} aria-label={`Anular recibo ${p.numero_recibo}`} title="Anular recibo">
                            <Ban aria-hidden="true" />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </Modal>
  );
}
