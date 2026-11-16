import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/http.js';

const VACIO = { datos: [], total: 0, pagina: 1, paginas: 1 };

/**
 * Listado paginado con búsqueda. La búsqueda espera 300 ms después de la última tecla
 * para no consultar al servidor en cada pulsación.
 */
export function useListado(ruta, { porPagina = 10, estado = null } = {}) {
  const [busqueda, setBusqueda] = useState('');
  const [q, setQ] = useState('');
  const [pagina, setPagina] = useState(1);
  const [resultado, setResultado] = useState(VACIO);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    const espera = setTimeout(() => { setQ(busqueda.trim()); setPagina(1); }, 300);
    return () => clearTimeout(espera);
  }, [busqueda]);

  useEffect(() => { setPagina(1); }, [estado]);

  useEffect(() => {
    let vigente = true;
    setCargando(true);
    api.get(ruta, { q, pagina, porPagina, estado })
      .then((r) => { if (vigente) { setResultado(r); setError(null); } })
      .catch((e) => { if (vigente) { setResultado(VACIO); setError(e.message); } })
      .finally(() => { if (vigente) setCargando(false); });
    return () => { vigente = false; };
  }, [ruta, q, pagina, porPagina, estado, version]);

  const recargar = useCallback(() => setVersion((v) => v + 1), []);

  return { ...resultado, cargando, error, busqueda, setBusqueda, pagina, setPagina, recargar };
}
