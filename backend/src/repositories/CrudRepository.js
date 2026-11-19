import { OracleRepository, salida, tomar, parametros } from './OracleRepository.js';

/**
 * Repositorio CRUD sobre un paquete PL/SQL con los procedimientos
 * insertar, actualizar, eliminar, obtener y listar.
 */
export class CrudRepository extends OracleRepository {
  /**
   * @param db conexión a la base de datos
   * @param {{ paquete: string, camposCrear: string[], camposEditar?: string[] }} definicion
   */
  constructor(db, { paquete, camposCrear, camposEditar }) {
    super(db);
    this.paquete = paquete;
    this.camposCrear = camposCrear;
    this.camposEditar = camposEditar ?? camposCrear;
  }

  /** Lista una página de registros. */
  listar(filtro) {
    return this.pagina(`${this.paquete}.listar`, filtro);
  }

  /** Retorna un registro o null. */
  obtener(id) {
    return this.fila(`${this.paquete}.obtener(:id)`, { id });
  }

  /** Inserta un registro y retorna su id. */
  async crear(datos) {
    const { id } = await this.llamar(
      `BEGIN ${this.paquete}.insertar(${parametros(this.camposCrear)}, p_id => :id); END;`,
      { ...tomar(datos, this.camposCrear), id: salida.numero() },
    );
    return id;
  }

  /** Actualiza un registro. */
  async actualizar(id, datos) {
    await this.llamar(
      `BEGIN ${this.paquete}.actualizar(p_id => :id, ${parametros(this.camposEditar)}); END;`,
      { id, ...tomar(datos, this.camposEditar) },
    );
  }

  /** Elimina un registro. */
  async eliminar(id) {
    await this.llamar(`BEGIN ${this.paquete}.eliminar(:id); END;`, { id });
  }
}
