import { Link } from 'react-router-dom';

/** Pantalla de mensaje (acceso restringido o página no encontrada). */
export function Mensaje({ titulo, texto }) {
  return (
    <div className="centro">
      <div>
        <h1>{titulo}</h1>
        <p style={{ color: 'var(--texto-2)', margin: '8px 0 20px' }}>{texto}</p>
        <Link className="btn btn-oscuro" to="/">Volver al tablero</Link>
      </div>
    </div>
  );
}
