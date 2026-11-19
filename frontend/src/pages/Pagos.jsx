import { useState } from 'react';
import { useListado } from '../hooks/useListado.js';
import { Buscador, Cabecera, Insignia, Paginacion, Tabla } from '../components/Tabla.jsx';
import DetalleMatricula from '../components/DetalleMatricula.jsx';
import { fecha, moneda } from '../utils/formato.js';

/** Listado de recibos de caja. */
export default function Pagos() {
  const lista = useListado('/pagos');
  const [detalle, setDetalle] = useState(null);

  return (
    <>
      <Cabecera
        titulo="Recibos de caja"
        descripcion="Pagos recibidos. Para registrar un pago nuevo o anular un recibo, pulse la fila y use la ficha de la matrícula."
      />
      <section className="tarjeta">
        <div className="herramientas">
          <Buscador valor={lista.busqueda} alCambiar={lista.setBusqueda} texto="Buscar por recibo, estudiante o documento…" />
        </div>
        <Tabla
          filas={lista.datos}
          cargando={lista.cargando}
          error={lista.error}
          alPulsarFila={(f) => setDetalle(f.matricula_id)}
          columnas={[
            { clave: 'numero_recibo', titulo: 'Recibo', render: (f) => <strong className="num">{f.numero_recibo}</strong> },
            { clave: 'fecha_pago', titulo: 'Fecha', render: (f) => fecha(f.fecha_pago) },
            { clave: 'estudiante', titulo: 'Estudiante', render: (f) => <>{f.estudiante}<div className="secundario">{f.grupo}</div></> },
            { clave: 'medio_pago', titulo: 'Medio', render: (f) => <>{f.medio_pago}{f.referencia && <div className="secundario">{f.referencia}</div>}</> },
            { clave: 'factura_estado', titulo: 'Factura', render: (f) => <Insignia>{f.factura_estado}</Insignia> },
            { clave: 'anulado', titulo: 'Recibo', render: (f) => (f.anulado ? <Insignia>Anulado</Insignia> : <Insignia tono="ok">Vigente</Insignia>) },
            { clave: 'valor', titulo: 'Valor', derecha: true, render: (f) => moneda(f.valor) },
          ]}
        />
        <Paginacion pagina={lista.pagina} paginas={lista.paginas} total={lista.total} alCambiar={lista.setPagina} />
      </section>
      {detalle && <DetalleMatricula id={detalle} alCerrar={() => setDetalle(null)} alCambiar={lista.recargar} />}
    </>
  );
}
