import oracledb from 'oracledb';

// Parámetros de salida de los procedimientos almacenados
export const salida = {
  cursor: () => ({ dir: oracledb.BIND_OUT, type: oracledb.CURSOR }),
  numero: () => ({ dir: oracledb.BIND_OUT, type: oracledb.NUMBER }),
  texto: (max = 200) => ({ dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: max }),
};

const enMinusculas = (fila) => Object.fromEntries(Object.entries(fila).map(([k, v]) => [k.toLowerCase(), v]));

// Toma de `datos` solo los campos indicados; lo que falte viaja como NULL.
export const tomar = (datos, campos) => Object.fromEntries(campos.map((c) => [c, datos[c] ?? null]));

// "p_a => :a, p_b => :b": parámetros por nombre para llamar un procedimiento
export const parametros = (campos) => campos.map((c) => `p_${c} => :${c}`).join(', ');

/**
 * Base de todos los repositorios. Es la única capa que habla con Oracle y lo hace
 * exclusivamente llamando paquetes PL/SQL con variables de enlace (bind variables):
 * ningún dato del usuario se concatena en el texto SQL.
 */
export class OracleRepository {
  /** @param {{ getConnection: () => Promise<import('oracledb').Connection> }} db */
  constructor(db) {
    this.db = db;
  }

  /** Ejecuta un bloque PL/SQL y devuelve sus parámetros de salida (los cursores ya leídos como arreglos). */
  async llamar(plsql, binds = {}) {
    const conexion = await this.db.getConnection();
    try {
      const { outBinds = {} } = await conexion.execute(plsql, binds, { autoCommit: true });
      for (const [nombre, valor] of Object.entries(outBinds)) {
        if (valor && typeof valor.getRows === 'function') {
          try {
            outBinds[nombre] = (await valor.getRows()).map(enMinusculas);
          } finally {
            await valor.close();
          }
        }
      }
      return outBinds;
    } finally {
      await conexion.close();
    }
  }

  /** Función que devuelve SYS_REFCURSOR -> arreglo de filas. */
  async filas(llamada, binds = {}) {
    const { cur } = await this.llamar(`BEGIN :cur := ${llamada}; END;`, { ...binds, cur: salida.cursor() });
    return cur;
  }

  /** Igual que filas(), pero devuelve la primera fila o null. */
  async fila(llamada, binds = {}) {
    const [primera] = await this.filas(llamada, binds);
    return primera ?? null;
  }

  /** Procedimiento "listar" paginado: (p_busqueda, [extras], p_offset, p_limit, p_total OUT, p_cursor OUT). */
  async pagina(procedimiento, { q, offset, limit }, extras = {}) {
    const extra = Object.keys(extras).map((c) => `p_${c} => :${c}, `).join('');
    const { total, cur } = await this.llamar(
      `BEGIN ${procedimiento}(p_busqueda => :q, ${extra}p_offset => :offset, p_limit => :limit, p_total => :total, p_cursor => :cur); END;`,
      { q: q ?? null, ...extras, offset, limit, total: salida.numero(), cur: salida.cursor() },
    );
    return { filas: cur, total };
  }
}
