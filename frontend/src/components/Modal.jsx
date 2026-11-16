import { useEffect, useId, useRef } from 'react';
import { X } from 'lucide-react';

// Ventana modal accesible: se cierra con Esc, lleva el foco adentro y lo devuelve al cerrar.
export default function Modal({ titulo, tamano = '', onCerrar, children, pie }) {
  const idTitulo = useId();
  const caja = useRef(null);

  useEffect(() => {
    const anterior = document.activeElement;
    const primero = caja.current?.querySelector('input:not([disabled]), select:not([disabled]), textarea:not([disabled])')
      ?? caja.current?.querySelector('button');
    primero?.focus();
    const alTeclear = (e) => { if (e.key === 'Escape') onCerrar(); };
    document.addEventListener('keydown', alTeclear);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', alTeclear);
      document.body.style.overflow = '';
      anterior?.focus?.();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="modal-fondo" onMouseDown={(e) => { if (e.target === e.currentTarget) onCerrar(); }}>
      <div className={`modal ${tamano}`} role="dialog" aria-modal="true" aria-labelledby={idTitulo} ref={caja}>
        <div className="modal-cabecera">
          <h2 id={idTitulo}>{titulo}</h2>
          <button type="button" className="btn btn-icono" onClick={onCerrar} aria-label="Cerrar ventana"><X aria-hidden="true" /></button>
        </div>
        {children}
        {pie && <div className="modal-pie">{pie}</div>}
      </div>
    </div>
  );
}

export function Confirmacion({ titulo, mensaje, textoConfirmar = 'Eliminar', ocupado, onConfirmar, onCerrar }) {
  return (
    <Modal
      titulo={titulo}
      tamano="estrecho"
      onCerrar={onCerrar}
      pie={(
        <>
          <button type="button" className="btn btn-secundario" onClick={onCerrar} disabled={ocupado}>Cancelar</button>
          <button type="button" className="btn btn-primario" onClick={onConfirmar} disabled={ocupado}>
            {ocupado ? 'Procesando…' : textoConfirmar}
          </button>
        </>
      )}
    >
      <div className="modal-cuerpo"><p>{mensaje}</p></div>
    </Modal>
  );
}
