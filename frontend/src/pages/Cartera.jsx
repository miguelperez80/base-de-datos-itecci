import { useState } from 'react';
import { useListado } from '../hooks/useListado.js';
import { Buscador, Cabecera, Insignia, Paginacion, Pestanas, Tabla } from '../components/Tabla.jsx';
import DetalleMatricula from '../components/DetalleMatricula.jsx';
import { moneda } from '../utils/formato.js';

const ESTADOS = [
  { valor: 'En mora', texto: 'En mora' }, { valor: 'Al día', texto: 'Al día' },
  { valor: 'Paz y salvo', texto: 'Paz y salvo' }, { valor: null, texto: 'Todas' },
];

/** Reporte de cartera: estado de crédito de cada matrícula. */
export default function Cartera() {
  const [estado, setEstado] = useState('En mora');
  const lista = useListado('/reportes/cartera', { estado });
  const [detalle, setDetalle] = useState(null);

  return (
    <>
      <Cabecera
        titulo="Cartera"
        descripcion="Estado de crédito por matrícula. En mora: tiene al menos una cuota vencida sin pagar. Pulse una fila para registrar un pago."
      />
      <section className="tarjeta">
        <div className="herramientas">
          <Buscador valor={lista.busqueda} alCambiar={lista.setBusqueda} texto="Buscar por estudiante, documento o grupo…" />
          <Pestanas opciones={ESTADOS} valor={estado} alCambiar={setEstado} etiqueta="Filtrar por estado de crédito" />
        </div>
        <Tabla
          filas={lista.datos}
          cargando={lista.cargando}
          error={lista.error}
          alPulsarFila={(f) => setDetalle(f.id)}
          columnas={[
            { clave: 'estudiante', titulo: 'Estudiante', render: (f) => <><strong>{f.estudiante}</strong><div className="secundario num">{f.cedula}</div></> },
            { clave: 'telefono', titulo: 'Teléfono', render: (f) => <span className="num">{f.telefono}</span> },
            { clave: 'grupo', titulo: 'Grupo' },
            { clave: 'estado', titulo: 'Estado', render: (f) => <Insignia>{f.estado}</Insignia> },
            { clave: 'cuotas_vencidas', titulo: 'Cuotas vencidas', derecha: true },
            { clave: 'dias_mora', titulo: 'Días de mora', derecha: true },
            { clave: 'total_pagado', titulo: 'Pagado', derecha: true, render: (f) => moneda(f.total_pagado) },
            { clave: 'saldo', titulo: 'Saldo', derecha: true, render: (f) => <strong>{moneda(f.saldo)}</strong> },
          ]}
        />
        <Paginacion pagina={lista.pagina} paginas={lista.paginas} total={lista.total} alCambiar={lista.setPagina} />
      </section>
      {detalle && <DetalleMatricula id={detalle} alCerrar={() => setDetalle(null)} alCambiar={lista.recargar} />}
    </>
  );
}
