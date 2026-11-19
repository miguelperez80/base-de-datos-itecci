import oracledb from 'oracledb';

/** Tipos de los parámetros de salida. */
export const salida = {
  cursor: () => ({ dir: oracledb.BIND_OUT, type: oracledb.CURSOR }),
  numero: () => ({ dir: oracledb.BIND_OUT, type: oracledb.NUMBER }),
  texto: (max = 200) => ({ dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: max }),
};

const enMinusculas = (fila) => Object.fromEntries(Object.entries(fila).map(([k, v]) => [k.toLowerCase(), v]));

/** Toma de un objeto los campos indicados; los que falten quedan en null. */
export const tomar = (datos, campos) => Object.fromEntries(campos.map((c) => [c, datos[c] ?? null]));

/** Arma la lista de parámetros por nombre: p_campo => :campo. */
export const parametros = (campos) => campos.map((c) => `p_${c} => :${c}`).join(', ');

/** Base de los repositorios: ejecuta paquetes PL/SQL con variables de enlace. */
export class OracleRepository {
  /** @param {{ getConnection: () => Promise<import('oracledb').Connection> }} db */
  constructor(db) {
    this.db = db;
  }

  /** Ejecuta un bloque PL/SQL y devuelve sus parámetros de salida, con los cursores leídos como arreglos. */
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

  /** Ejecuta una función que devuelve SYS_REFCURSOR y retorna sus filas. */
  async filas(llamada, binds = {}) {
    const { cur } = await this.llamar(`BEGIN :cur := ${llamada}; END;`, { ...binds, cur: salida.cursor() });
    return cur;
  }

  /** Ejecuta una función que devuelve SYS_REFCURSOR y retorna la primera fila o null. */
  async fila(llamada, binds = {}) {
    const [primera] = await this.filas(llamada, binds);
    return primera ?? null;
  }

  /** Ejecuta un procedimiento listar paginado y retorna las filas y el total. */
  async pagina(procedimiento, { q, offset, limit }, extras = {}) {
    const extra = Object.keys(extras).map((c) => `p_${c} => :${c}, `).join('');
    const { total, cur } = await this.llamar(
      `BEGIN ${procedimiento}(p_busqueda => :q, ${extra}p_offset => :offset, p_limit => :limit, p_total => :total, p_cursor => :cur); END;`,
      { q: q ?? null, ...extras, offset, limit, total: salida.numero(), cur: salida.cursor() },
    );
    return { filas: cur, total };
  }
}
