import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { CircleAlert, CircleCheck } from 'lucide-react';

const AvisosContext = createContext(null);
let consecutivo = 0;

// Mensajes breves de confirmación o error en la esquina inferior derecha
export function AvisosProvider({ children }) {
  const [avisos, setAvisos] = useState([]);

  const mostrar = useCallback((tipo, texto) => {
    const id = ++consecutivo;
    setAvisos((lista) => [...lista, { id, tipo, texto }]);
    setTimeout(() => setAvisos((lista) => lista.filter((a) => a.id !== id)), tipo === 'error' ? 7000 : 4000);
  }, []);

  const valor = useMemo(() => ({
    exito: (texto) => mostrar('exito', texto),
    error: (texto) => mostrar('error', texto),
  }), [mostrar]);

  return (
    <AvisosContext.Provider value={valor}>
      {children}
      <div className="avisos" role="status" aria-live="polite">
        {avisos.map((a) => (
          <div key={a.id} className={`emergente ${a.tipo === 'error' ? 'error' : ''}`}>
            {a.tipo === 'error' ? <CircleAlert aria-hidden="true" /> : <CircleCheck aria-hidden="true" />}
            <span>{a.texto}</span>
          </div>
        ))}
      </div>
    </AvisosContext.Provider>
  );
}

export const useAvisos = () => useContext(AvisosContext);
