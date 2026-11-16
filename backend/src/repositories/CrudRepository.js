import { OracleRepository, salida, tomar, parametros } from './OracleRepository.js';

/**
 * Repositorio CRUD sobre un paquete PL/SQL con la forma estándar del proyecto:
 *   insertar(..., p_id OUT) · actualizar(p_id, ...) · eliminar(p_id) · obtener(p_id) · listar(...)
 * Cada entidad solo declara su paquete y sus campos (abierto a extensión, cerrado a modificación).
 */
export class CrudRepository extends OracleRepository {
  /**
   * @param db conexión inyectada
   * @param {{ paquete: string, camposCrear: string[], camposEditar?: string[] }} definicion
   */
  constructor(db, { paquete, camposCrear, camposEditar }) {
    super(db);
    this.paquete = paquete;
    this.camposCrear = camposCrear;
    this.camposEditar = camposEditar ?? camposCrear;
  }

  listar(filtro) {
    return this.pagina(`${this.paquete}.listar`, filtro);
  }

  obtener(id) {
    return this.fila(`${this.paquete}.obtener(:id)`, { id });
  }

  async crear(datos) {
    const { id } = await this.llamar(
      `BEGIN ${this.paquete}.insertar(${parametros(this.camposCrear)}, p_id => :id); END;`,
      { ...tomar(datos, this.camposCrear), id: salida.numero() },
    );
    return id;
  }

  async actualizar(id, datos) {
    await this.llamar(
      `BEGIN ${this.paquete}.actualizar(p_id => :id, ${parametros(this.camposEditar)}); END;`,
      { id, ...tomar(datos, this.camposEditar) },
    );
  }

  async eliminar(id) {
    await this.llamar(`BEGIN ${this.paquete}.eliminar(:id); END;`, { id });
  }
}
