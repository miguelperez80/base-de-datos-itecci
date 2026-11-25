process.env.NODE_ENV = 'test';
process.env.DB_USER = 'prueba';
process.env.DB_PASSWORD = 'prueba';
process.env.DB_CONNECT_STRING = 'localhost:1521/prueba';
process.env.JWT_SECRET = 'secreto-de-prueba-de-al-menos-treinta-y-dos-caracteres';
process.env.JWT_EXPIRES_MIN = '120';
process.env.FRONTEND_ORIGIN = 'http://localhost:5173,https://miguelperez80.github.io';

const { default: bcrypt } = await import('bcryptjs');
const { crearContenedor } = await import('../src/container.js');
const { crearApp } = await import('../src/app.js');

export const ORIGEN = 'http://localhost:5173';
export const SECRETO = process.env.JWT_SECRET;
export const CLAVES = { coordinador: 'Coord2026#', secretaria: 'Secre2026#' };

const USUARIOS = {
  coordinador: { ID: 1, USERNAME: 'coordinador', NOMBRE: 'Coordinación', ROL: 'COORDINADOR', PASSWORD_HASH: bcrypt.hashSync(CLAVES.coordinador, 4), ACTIVO: 1 },
  secretaria: { ID: 2, USERNAME: 'secretaria', NOMBRE: 'Secretaría', ROL: 'SECRETARIA', PASSWORD_HASH: bcrypt.hashSync(CLAVES.secretaria, 4), ACTIVO: 1 },
};

/** Registro de lo que la aplicación escribe en consola durante las pruebas (y no se imprime). */
export const registro = [];
console.log = (linea) => registro.push(String(linea));
console.error = (linea) => registro.push(String(linea));

const cursor = (filas) => ({ getRows: async () => filas, close: async () => {} });

const errorOracle = (numero, mensaje) => Object.assign(new Error(`ORA-${numero}: ${mensaje}\nORA-06512: at line 1`), { errorNum: numero });

/**
 * Doble de la conexión a Oracle: guarda cada bloque PL/SQL con sus variables de enlace
 * y responde como lo harían los paquetes.
 */
export function crearBaseSimulada() {
  const llamadas = [];
  return {
    llamadas,
    getConnection: async () => ({
      close: async () => {},
      execute: async (sql, binds = {}) => {
        llamadas.push({ sql, binds });
        if (sql.includes('pkg_api_seguridad.obtener_usuario')) {
          const usuario = USUARIOS[binds.username];
          return { outBinds: { cur: cursor(usuario ? [usuario] : []) } };
        }
        if (sql.includes('pkg_api_pago.registrar')) {
          throw errorOracle(20010, 'El pago (900000) supera el saldo pendiente (100000)');
        }
        if (sql.includes('pkg_api_reportes.indicadores')) {
          throw new Error('TypeError en C:\\servidor\\backend\\src\\repositorio.js:42 con clave interna Itecci2026#');
        }
        return { outBinds: { cur: cursor([]), total: 0, id: 1 } };
      },
    }),
  };
}

/** Levanta la API en un puerto libre con una base simulada. */
export async function iniciarServidor() {
  const db = crearBaseSimulada();
  const servidor = crearApp(crearContenedor(db)).listen(0, '127.0.0.1');
  await new Promise((resolver) => servidor.once('listening', resolver));
  const base = `http://127.0.0.1:${servidor.address().port}`;

  const pedir = async (metodo, ruta, { cookie, cuerpo, origen = ORIGEN, cabeceras = {} } = {}) => {
    const respuesta = await fetch(base + ruta, {
      method: metodo,
      headers: {
        ...(origen ? { Origin: origen } : {}),
        ...(cuerpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(cookie ? { Cookie: cookie } : {}),
        ...cabeceras,
      },
      body: cuerpo === undefined ? undefined : (typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo)),
    });
    const texto = await respuesta.text();
    let json = null;
    try { json = JSON.parse(texto); } catch { json = null; }
    return { status: respuesta.status, headers: respuesta.headers, json, texto };
  };

  const iniciarSesion = async (usuario, clave = CLAVES[usuario]) => {
    const r = await pedir('POST', '/api/auth/login', { cuerpo: { username: usuario, password: clave } });
    return { ...r, cookie: r.headers.get('set-cookie')?.split(';')[0] };
  };

  return { base, db, pedir, iniciarSesion, cerrar: () => new Promise((resolver) => servidor.close(resolver)) };
}
