import { useEffect, useState } from 'react';
import { api } from '../api/http.js';
import { Cabecera, Insignia, Pestanas, Tabla } from '../components/Tabla.jsx';
import Modal from '../components/Modal.jsx';
import { numero } from '../utils/formato.js';

const VISTAS = [
  { valor: 'tablas', texto: 'Tablas' },
  { valor: 'objetos', texto: 'Objetos del esquema' },
  { valor: 'subprogramas', texto: 'Procedimientos y funciones' },
];

const COLUMNAS = {
  tablas: [
    { clave: 'tabla', titulo: 'Tabla', render: (f) => <strong>{f.tabla}</strong> },
    { clave: 'filas', titulo: 'Filas', derecha: true, render: (f) => numero(f.filas) },
    { clave: 'columnas', titulo: 'Columnas', derecha: true },
    { clave: 'restricciones', titulo: 'Restricciones', derecha: true },
    { clave: 'indices', titulo: 'Índices', derecha: true },
    { clave: 'triggers', titulo: 'Triggers', derecha: true },
  ],
  objetos: [
    { clave: 'objeto', titulo: 'Objeto', render: (f) => <strong>{f.objeto}</strong> },
    { clave: 'tipo', titulo: 'Tipo' },
    { clave: 'estado', titulo: 'Estado', render: (f) => <Insignia>{f.estado}</Insignia> },
    { clave: 'creado', titulo: 'Creado' },
    { clave: 'modificado', titulo: 'Última modificación' },
  ],
  subprogramas: [
    { clave: 'objeto', titulo: 'Objeto', render: (f) => <strong>{f.objeto}</strong> },
    { clave: 'tipo', titulo: 'Tipo' },
    { clave: 'subprograma', titulo: 'Subprograma', render: (f) => f.subprograma ?? '—' },
    { clave: 'parametros', titulo: 'Parámetros', derecha: true },
  ],
};

const ORIGEN = {
  tablas: 'USER_TABLES, USER_TAB_COLUMNS, USER_CONSTRAINTS, USER_INDEXES y USER_TRIGGERS',
  objetos: 'USER_OBJECTS',
  subprogramas: 'USER_PROCEDURES y USER_ARGUMENTS',
};

/** Consulta del diccionario de datos de Oracle: tablas, columnas, objetos y subprogramas. */
export default function Diccionario() {
  const [vista, setVista] = useState('tablas');
  const [filas, setFilas] = useState([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState(null);
  const [tabla, setTabla] = useState(null);

  useEffect(() => {
    let vigente = true;
    setCargando(true);
    setFilas([]);
    api.get(`/diccionario/${vista}`)
      .then((r) => { if (vigente) { setFilas(r.map((f, i) => ({ ...f, _i: i }))); setError(null); } })
      .catch((e) => { if (vigente) setError(e.message); })
      .finally(() => { if (vigente) setCargando(false); });
    return () => { vigente = false; };
  }, [vista]);

  const verColumnas = async (f) => {
    try {
      setTabla({ nombre: f.tabla, columnas: await api.get(`/diccionario/tablas/${encodeURIComponent(f.tabla)}/columnas`) });
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <>
      <Cabecera titulo="Diccionario de datos" descripcion={`Metadatos del esquema ITECCI leídos de ${ORIGEN[vista]}.`} />
      <section className="tarjeta">
        <div className="herramientas">
          <Pestanas opciones={VISTAS} valor={vista} alCambiar={setVista} etiqueta="Sección del diccionario" />
          {!cargando && <span className="campo-ayuda" style={{ margin: 0 }}>{numero(filas.length)} elementos{vista === 'tablas' && ' · pulse una tabla para ver sus columnas'}</span>}
        </div>
        <Tabla columnas={COLUMNAS[vista]} filas={filas} cargando={cargando} error={error} clave="_i" alPulsarFila={vista === 'tablas' ? verColumnas : undefined} />
      </section>

      {tabla && (
        <Modal titulo={`Tabla ${tabla.nombre}`} onCerrar={() => setTabla(null)} pie={<button type="button" className="btn btn-secundario" onClick={() => setTabla(null)}>Cerrar</button>}>
          <Tabla
            clave="orden"
            filas={tabla.columnas}
            columnas={[
              { clave: 'orden', titulo: 'N.º' },
              { clave: 'columna', titulo: 'Columna', render: (f) => <strong>{f.columna}</strong> },
              { clave: 'tipo', titulo: 'Tipo de dato' },
              { clave: 'admite_nulos', titulo: 'Admite nulos' },
              { clave: 'llaves', titulo: 'Llaves', render: (f) => (f.llaves ? <Insignia tono="neutro">{f.llaves}</Insignia> : '—') },
            ]}
          />
        </Modal>
      )}
    </>
  );
}
