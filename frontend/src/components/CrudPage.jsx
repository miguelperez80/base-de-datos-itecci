import { useEffect, useState } from 'react';
import { Pencil, Plus, Trash2 } from 'lucide-react';
import { api } from '../api/http.js';
import { useAuth } from '../context/AuthContext.jsx';
import { useAvisos } from '../context/AvisosContext.jsx';
import { useListado } from '../hooks/useListado.js';
import { Buscador, Cabecera, Paginacion, Tabla } from './Tabla.jsx';
import Formulario from './Formulario.jsx';
import Modal, { Confirmacion } from './Modal.jsx';

/** Pantalla para listar, buscar, crear, editar y eliminar registros a partir de sus columnas y campos. */
export default function CrudPage({
  titulo, descripcion, recurso, singular, columnas, campos, inicial,
  escriben, eliminan = ['COORDINADOR'], describir = (f) => f.nombre, textoBuscar,
  accionesExtra, complemento, complementoTras, tamanoFormulario,
}) {
  const { tieneRol } = useAuth();
  const avisos = useAvisos();
  const lista = useListado(`/${recurso}`);
  const [formulario, setFormulario] = useState(null);
  const [porEliminar, setPorEliminar] = useState(null);
  const [eliminando, setEliminando] = useState(false);
  const [catalogos, setCatalogos] = useState({});

  const puedeEscribir = tieneRol(escriben);
  const puedeEliminar = tieneRol(eliminan);

  useEffect(() => {
    if (!puedeEscribir) return;
    const nombres = [...new Set(campos.filter((c) => c.catalogo).map((c) => c.catalogo))];
    Promise.all(nombres.map((n) => api.get(`/catalogos/${n}`).then((filas) => [n, filas.map((f) => ({ valor: f.id, texto: f.nombre }))])))
      .then((pares) => setCatalogos(Object.fromEntries(pares)))
      .catch((e) => avisos.error(e.message));
  }, [recurso, puedeEscribir]);

  const abrirEdicion = async (fila) => {
    try {
      const registro = await api.get(`/${recurso}/${fila.id}`);
      const valores = Object.fromEntries(campos.map((c) => [c.nombre, registro[c.nombre] ?? '']));
      setFormulario({ id: fila.id, valores });
    } catch (e) {
      avisos.error(e.message);
    }
  };

  const guardar = async (carga) => {
    if (formulario.id) await api.put(`/${recurso}/${formulario.id}`, carga);
    else await api.post(`/${recurso}`, carga);
    avisos.exito(`${singular} ${formulario.id ? 'actualizado' : 'registrado'} correctamente`);
    setFormulario(null);
    lista.recargar();
  };

  const eliminar = async () => {
    setEliminando(true);
    try {
      await api.delete(`/${recurso}/${porEliminar.id}`);
      avisos.exito(`${singular} eliminado`);
      lista.recargar();
    } catch (e) {
      avisos.error(e.message);
    } finally {
      setEliminando(false);
      setPorEliminar(null);
    }
  };

  const acciones = (accionesExtra || puedeEscribir || puedeEliminar) ? (fila) => (
    <>
      {accionesExtra?.(fila)}
      {puedeEscribir && (
        <button type="button" className="btn btn-icono" onClick={() => abrirEdicion(fila)} aria-label={`Editar ${describir(fila)}`} title="Editar">
          <Pencil aria-hidden="true" />
        </button>
      )}
      {puedeEliminar && (
        <button type="button" className="btn btn-icono peligro" onClick={() => setPorEliminar(fila)} aria-label={`Eliminar ${describir(fila)}`} title="Eliminar">
          <Trash2 aria-hidden="true" />
        </button>
      )}
    </>
  ) : undefined;

  return (
    <>
      <Cabecera titulo={titulo} descripcion={descripcion}>
        {puedeEscribir && (
          <button type="button" className="btn btn-primario" onClick={() => setFormulario({ id: null, valores: inicial })}>
            <Plus aria-hidden="true" /> Nuevo {singular.toLowerCase()}
          </button>
        )}
      </Cabecera>

      <section className="tarjeta">
        <div className="herramientas">
          <Buscador valor={lista.busqueda} alCambiar={lista.setBusqueda} texto={textoBuscar ?? 'Buscar…'} />
        </div>
        <Tabla columnas={columnas} filas={lista.datos} cargando={lista.cargando} error={lista.error} acciones={acciones} />
        <Paginacion pagina={lista.pagina} paginas={lista.paginas} total={lista.total} alCambiar={lista.setPagina} />
      </section>

      {formulario && (
        <Modal titulo={`${formulario.id ? 'Editar' : 'Nuevo'} ${singular.toLowerCase()}`} tamano={tamanoFormulario} onCerrar={() => setFormulario(null)}>
          <Formulario
            campos={campos}
            inicial={formulario.valores}
            catalogos={catalogos}
            editando={!!formulario.id}
            alGuardar={guardar}
            alCancelar={() => setFormulario(null)}
            Complemento={complemento}
            complementoTras={complementoTras}
            idRegistro={formulario.id}
          />
        </Modal>
      )}

      {porEliminar && (
        <Confirmacion
          titulo={`Eliminar ${singular.toLowerCase()}`}
          mensaje={`¿Seguro que desea eliminar "${describir(porEliminar)}"? Esta acción no se puede deshacer.`}
          ocupado={eliminando}
          onConfirmar={eliminar}
          onCerrar={() => setPorEliminar(null)}
        />
      )}
    </>
  );
}
