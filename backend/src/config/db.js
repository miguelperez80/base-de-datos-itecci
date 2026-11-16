import oracledb from 'oracledb';
import { env } from './env.js';

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

let pool;

export async function iniciarPool() {
  pool = await oracledb.createPool({
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    connectString: env.DB_CONNECT_STRING,
    poolMin: 1,
    poolMax: 8,
    poolIncrement: 1,
  });
  return pool;
}

export async function cerrarPool() {
  if (pool) {
    await pool.close(5);
    pool = undefined;
  }
}

// Único punto por el que los repositorios obtienen conexiones (se les inyecta este objeto).
export const db = {
  getConnection() {
    if (!pool) throw new Error('El pool de conexiones no se ha iniciado');
    return pool.getConnection();
  },
};
