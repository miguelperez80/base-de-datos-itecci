import { AppError } from '../utils/AppError.js';

/** Convierte página y tamaño de página en offset y límite. */
export const aFiltro = ({ q, pagina, porPagina, estado }) => ({
  q, estado, offset: (pagina - 1) * porPagina, limit: porPagina,
});

/** Arma la respuesta paginada. */
export const aPagina = ({ filas, total }, { pagina, porPagina }) => ({
  datos: filas, total, pagina, porPagina, paginas: Math.max(1, Math.ceil(total / porPagina)),
});

/** Operaciones CRUD de una entidad sobre su repositorio. */
export class CrudService {
  constructor(repositorio, nombreEntidad) {
    this.repositorio = repositorio;
    this.nombreEntidad = nombreEntidad;
  }

  async listar(consulta) {
    return aPagina(await this.repositorio.listar(aFiltro(consulta)), consulta);
  }

  async obtener(id) {
    const registro = await this.repositorio.obtener(id);
    if (!registro) throw AppError.noEncontrado(`${this.nombreEntidad} no existe`);
    return registro;
  }

  async crear(datos) {
    const id = await this.repositorio.crear(datos);
    return this.obtener(id);
  }

  async actualizar(id, datos) {
    await this.repositorio.actualizar(id, datos);
    return this.obtener(id);
  }

  async eliminar(id) {
    await this.repositorio.eliminar(id);
  }
}
