import { ChevronLeft, ChevronRight, Search } from 'lucide-react';
import { numero } from '../utils/formato.js';

/**
 * Tabla de datos.
 * columnas: [{ clave, titulo, derecha?, render?(fila) }]
 */
export function Tabla({ columnas, filas, cargando, error, vacio = 'No hay registros para mostrar', alPulsarFila, acciones, clave = 'id' }) {
  const total = columnas.length + (acciones ? 1 : 0);
  return (
    <div className="tabla-envoltura">
      <table className="tabla">
        <thead>
          <tr>
            {columnas.map((c) => <th key={c.clave} scope="col" className={c.derecha ? 'derecha' : undefined}>{c.titulo}</th>)}
            {acciones && <th scope="col" className="acciones"><span className="sr-only">Acciones</span></th>}
          </tr>
        </thead>
        <tbody>
          {cargando && filas.length === 0 && Array.from({ length: 5 }, (_, i) => (
            <tr key={`e${i}`}>{Array.from({ length: total }, (_, j) => <td key={j}><div className="esqueleto" /></td>)}</tr>
          ))}
          {!cargando && error && (
            <tr><td colSpan={total}><div className="tabla-vacia" role="alert"><strong>No se pudo cargar la información</strong>{error}</div></td></tr>
          )}
          {!cargando && !error && filas.length === 0 && (
            <tr><td colSpan={total}><div className="tabla-vacia"><strong>Sin resultados</strong>{vacio}</div></td></tr>
          )}
          {filas.map((fila) => (
            <tr
              key={fila[clave]}
              className={alPulsarFila ? 'clicable' : undefined}
              onClick={alPulsarFila ? () => alPulsarFila(fila) : undefined}
              tabIndex={alPulsarFila ? 0 : undefined}
              onKeyDown={alPulsarFila ? (e) => { if (e.key === 'Enter') alPulsarFila(fila); } : undefined}
            >
              {columnas.map((c) => (
                <td key={c.clave} className={c.derecha ? 'derecha num' : undefined}>{c.render ? c.render(fila) : (fila[c.clave] ?? '—')}</td>
              ))}
              {acciones && <td className="acciones" onClick={(e) => e.stopPropagation()}>{acciones(fila)}</td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Controles de paginación. */
export function Paginacion({ pagina, paginas, total, alCambiar }) {
  return (
    <div className="paginacion">
      <span>{numero(total)} {total === 1 ? 'registro' : 'registros'}</span>
      <div className="paginacion-controles">
        <button type="button" className="btn btn-secundario btn-icono" onClick={() => alCambiar(pagina - 1)} disabled={pagina <= 1} aria-label="Página anterior">
          <ChevronLeft aria-hidden="true" />
        </button>
        <span>Página {pagina} de {paginas}</span>
        <button type="button" className="btn btn-secundario btn-icono" onClick={() => alCambiar(pagina + 1)} disabled={pagina >= paginas} aria-label="Página siguiente">
          <ChevronRight aria-hidden="true" />
        </button>
      </div>
    </div>
  );
}

/** Campo de búsqueda. */
export function Buscador({ valor, alCambiar, texto = 'Buscar…' }) {
  return (
    <div className="buscador">
      <Search aria-hidden="true" />
      <input type="search" className="entrada" value={valor} onChange={(e) => alCambiar(e.target.value)} placeholder={texto} aria-label={texto} maxLength={80} />
    </div>
  );
}

/** Pestañas para filtrar por estado. */
export function Pestanas({ opciones, valor, alCambiar, etiqueta }) {
  return (
    <div className="pestanas" role="group" aria-label={etiqueta}>
      {opciones.map((o) => (
        <button key={o.valor ?? 'todas'} type="button" aria-pressed={valor === o.valor} onClick={() => alCambiar(o.valor)}>{o.texto}</button>
      ))}
    </div>
  );
}

const TONOS = {
  'Activa': 'ok', 'Activo': 'ok', 'Paz y salvo': 'ok', 'Pagada': 'ok', 'Emitida': 'ok', 'VALID': 'ok', 'Sí': 'ok',
  'Al día': 'aviso', 'Pendiente': 'aviso', 'En formación': 'aviso',
  'En mora': 'mal', 'Vencida': 'mal', 'Anulado': 'mal', 'Anulada': 'mal', 'Cancelado': 'mal', 'Retirada': 'mal', 'INVALID': 'mal',
};

/** Etiqueta de estado con texto y color. */
export function Insignia({ children, tono }) {
  return <span className={`insignia ${tono ?? TONOS[children] ?? 'neutro'}`}>{children}</span>;
}

/** Encabezado de una pantalla. */
export function Cabecera({ titulo, descripcion, children }) {
  return (
    <div className="pagina-cabecera">
      <div>
        <h1>{titulo}</h1>
        {descripcion && <p>{descripcion}</p>}
      </div>
      {children}
    </div>
  );
}
