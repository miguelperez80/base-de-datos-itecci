import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import jwt from 'jsonwebtoken';
import { iniciarServidor, registro, SECRETO, CLAVES } from './apoyo.js';

const COOKIE = 'itecci_sesion';
const tokenCon = (datos, opciones = {}, secreto = SECRETO) => `${COOKIE}=${jwt.sign(datos, secreto, {
  algorithm: 'HS256', expiresIn: '10m', subject: '1', issuer: 'itecci-api', ...opciones,
})}`;
const COORDINADOR = { username: 'coordinador', nombre: 'Coordinación', rol: 'COORDINADOR' };

let api;
let coordinador;
let secretaria;

before(async () => {
  api = await iniciarServidor();
  coordinador = (await api.iniciarSesion('coordinador')).cookie;
  secretaria = (await api.iniciarSesion('secretaria')).cookie;
});
after(() => api.cerrar());

describe('A01 Pérdida de control de acceso', () => {
  test('sin sesión no se puede consultar ningún dato (401)', async () => {
    for (const ruta of ['/api/estudiantes', '/api/matriculas', '/api/pagos', '/api/reportes/tablero', '/api/diccionario/tablas']) {
      const r = await api.pedir('GET', ruta);
      assert.equal(r.status, 401, ruta);
    }
  });

  test('la secretaria no puede entrar a funciones de coordinación aunque escriba la URL (403)', async () => {
    const intentos = [
      ['GET', '/api/docentes'],
      ['GET', '/api/contratos'],
      ['GET', '/api/diccionario/tablas'],
      ['GET', '/api/grupos/disponibilidad?periodo_id=3'],
      ['DELETE', '/api/estudiantes/1'],
      ['POST', '/api/pagos/1/anulacion', { motivo: 'Prueba de anulación' }],
    ];
    for (const [metodo, ruta, cuerpo] of intentos) {
      const r = await api.pedir(metodo, ruta, { cookie: secretaria, cuerpo });
      assert.equal(r.status, 403, `${metodo} ${ruta}`);
    }
  });

  test('el coordinador sí tiene acceso a esas funciones', async () => {
    const r = await api.pedir('GET', '/api/docentes', { cookie: coordinador });
    assert.equal(r.status, 200);
  });

  test('una petición que modifica datos desde otro sitio se rechaza (CSRF)', async () => {
    const r = await api.pedir('POST', '/api/matriculas', {
      cookie: coordinador, origen: 'https://sitio-malicioso.com', cuerpo: { estudiante_id: 1, grupo_id: 1 },
    });
    assert.equal(r.status, 403);
    assert.equal(r.json.error.mensaje, 'Origen no permitido');
  });
});

describe('A02 Fallas criptográficas', () => {
  test('la contraseña se compara con bcrypt y nunca se devuelve su hash', async () => {
    const r = await api.iniciarSesion('coordinador');
    assert.equal(r.status, 200);
    assert.ok(!r.texto.includes('$2'), 'la respuesta no contiene el hash bcrypt');
    assert.ok(!r.texto.toLowerCase().includes('password'), 'la respuesta no contiene la contraseña');
  });

  test('la sesión viaja en una cookie httpOnly y SameSite=Strict, inaccesible desde JavaScript', async () => {
    const { headers } = await api.iniciarSesion('coordinador');
    const cookie = headers.get('set-cookie');
    assert.match(cookie, /HttpOnly/i);
    assert.match(cookie, /SameSite=Strict/i);
    assert.match(cookie, /Path=\/api/i);
    assert.match(cookie, /Max-Age=7200/i);
  });

  test('desde un origen que no es local la cookie exige HTTPS (Secure)', async () => {
    const r = await api.pedir('POST', '/api/auth/login', {
      origen: 'https://miguelperez80.github.io', cuerpo: { username: 'coordinador', password: CLAVES.coordinador },
    });
    assert.match(r.headers.get('set-cookie'), /Secure/i);
  });

  test('el token está firmado con HS256 y tiene vencimiento', async () => {
    const token = coordinador.split('=')[1];
    const { header, payload } = jwt.decode(token, { complete: true });
    assert.equal(header.alg, 'HS256');
    assert.equal(payload.exp - payload.iat, 120 * 60);
    assert.equal(payload.password_hash, undefined);
  });
});

describe('A03 Inyección', () => {
  test('una inyección SQL en la búsqueda viaja como dato (variable de enlace), nunca como código', async () => {
    const ataque = "' OR '1'='1' --";
    const r = await api.pedir('GET', `/api/estudiantes?q=${encodeURIComponent(ataque)}`, { cookie: coordinador });
    assert.equal(r.status, 200);
    const { sql, binds } = api.db.llamadas.at(-1);
    assert.ok(!sql.includes(ataque), 'el texto PL/SQL no contiene la entrada del usuario');
    assert.match(sql, /p_busqueda => :q/);
    assert.equal(binds.q, ataque.trim());
  });

  test('un nombre de tabla con código SQL se rechaza antes de llegar a Oracle (400)', async () => {
    const llamadasAntes = api.db.llamadas.length;
    const r = await api.pedir('GET', `/api/diccionario/tablas/${encodeURIComponent('ESTUDIANTE; DROP TABLE PAGO')}/columnas`, { cookie: coordinador });
    assert.equal(r.status, 400);
    assert.equal(api.db.llamadas.length, llamadasAntes);
  });

  test('campos que no están en el formulario (asignación masiva) se rechazan (400)', async () => {
    const r = await api.pedir('POST', '/api/matriculas', {
      cookie: secretaria, cuerpo: { estudiante_id: 1, grupo_id: 1, rol: 'COORDINADOR' },
    });
    assert.equal(r.status, 400);
  });

  test('ningún bloque enviado a Oracle concatena datos: todos usan variables de enlace', () => {
    for (const { sql, binds } of api.db.llamadas) {
      for (const valor of Object.values(binds)) {
        if (typeof valor === 'string' && valor.length > 2) assert.ok(!sql.includes(valor), `"${valor}" no aparece en ${sql}`);
      }
    }
  });
});

describe('A04 Diseño inseguro', () => {
  test('el servidor vuelve a validar aunque se salte el formulario (valor de pago inválido)', async () => {
    for (const valor of [-50000, 0, 999.5, 'mil pesos']) {
      const r = await api.pedir('POST', '/api/pagos', {
        cookie: secretaria, cuerpo: { matricula_id: 1, valor, medio_pago_id: 1 },
      });
      assert.equal(r.status, 400, `valor ${valor}`);
    }
  });

  test('las reglas del negocio las decide Oracle: un pago mayor al saldo se rechaza (422)', async () => {
    const r = await api.pedir('POST', '/api/pagos', {
      cookie: secretaria, cuerpo: { matricula_id: 1, valor: 900000, medio_pago_id: 1 },
    });
    assert.equal(r.status, 422);
    assert.match(r.json.error.mensaje, /supera el saldo pendiente/);
    assert.ok(!r.json.error.mensaje.includes('ORA-'), 'no se muestra el código interno de Oracle');
  });

  test('el tamaño de las peticiones y de las páginas está limitado', async () => {
    const grande = await api.pedir('POST', '/api/estudiantes', { cookie: secretaria, cuerpo: { relleno: 'x'.repeat(60 * 1024) } });
    assert.equal(grande.status, 413);
    const pagina = await api.pedir('GET', '/api/estudiantes?porPagina=100000', { cookie: secretaria });
    assert.equal(pagina.status, 400);
  });
});

describe('A05 Configuración de seguridad incorrecta', () => {
  test('cabeceras de seguridad activas y sin revelar la tecnología del servidor', async () => {
    const r = await api.pedir('GET', '/api/salud');
    assert.equal(r.headers.get('x-powered-by'), null);
    assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(r.headers.get('content-security-policy'));
    assert.ok(r.headers.get('strict-transport-security'));
    assert.equal(r.headers.get('x-frame-options'), 'SAMEORIGIN');
    assert.equal(r.headers.get('cache-control'), 'no-store');
  });

  test('CORS solo autoriza al frontend de la aplicación', async () => {
    const permitido = await api.pedir('OPTIONS', '/api/estudiantes', { cabeceras: { 'Access-Control-Request-Method': 'GET' } });
    assert.equal(permitido.headers.get('access-control-allow-origin'), 'http://localhost:5173');
    const ajeno = await api.pedir('OPTIONS', '/api/estudiantes', {
      origen: 'https://sitio-malicioso.com', cabeceras: { 'Access-Control-Request-Method': 'GET' },
    });
    assert.equal(ajeno.headers.get('access-control-allow-origin'), null);
  });

  test('un error inesperado no revela rutas, pila ni datos internos', async () => {
    const r = await api.pedir('GET', '/api/reportes/tablero', { cookie: coordinador });
    assert.equal(r.status, 500);
    assert.equal(r.json.error.codigo, 'ERROR_INTERNO');
    assert.match(r.json.error.referencia, /^[0-9a-f-]{36}$/);
    for (const secreto of ['C:\\servidor', 'repositorio.js', 'TypeError', 'Itecci2026#', 'at ']) {
      assert.ok(!r.texto.includes(secreto), `la respuesta no contiene "${secreto}"`);
    }
  });

  test('un JSON mal formado se responde con un mensaje controlado', async () => {
    const r = await api.pedir('POST', '/api/auth/login', { cuerpo: '{"username": "coordinador", ' });
    assert.equal(r.status, 400);
    assert.equal(r.json.error.codigo, 'JSON_INVALIDO');
  });
});

describe('A06 Componentes vulnerables y desactualizados', () => {
  test('las dependencias están fijadas en package-lock.json con su hash de integridad', () => {
    const lock = JSON.parse(readFileSync(new URL('../package-lock.json', import.meta.url), 'utf8'));
    const paquetes = Object.entries(lock.packages).filter(([ruta]) => ruta.startsWith('node_modules/'));
    assert.ok(paquetes.length > 0);
    for (const [ruta, datos] of paquetes) {
      assert.match(datos.version, /^\d+\.\d+\.\d+/, ruta);
      assert.match(datos.integrity ?? '', /^sha(512|256|1)-/, `${ruta} tiene hash de integridad`);
    }
  });

  test('se usan las versiones mayores vigentes de los componentes de seguridad', () => {
    const { dependencies } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
    const mayor = (nombre) => Number(dependencies[nombre].replace(/^\D*/, '').split('.')[0]);
    assert.ok(mayor('express') >= 5);
    assert.ok(mayor('helmet') >= 8);
    assert.ok(mayor('jsonwebtoken') >= 9);
    assert.ok(mayor('bcryptjs') >= 3);
  });
});

describe('A07 Fallas de identificación y autenticación', () => {
  test('mismo mensaje si el usuario no existe o si la clave es incorrecta (no revela usuarios)', async () => {
    const claveMala = await api.iniciarSesion('coordinador', 'ClaveIncorrecta1');
    const noExiste = await api.iniciarSesion('usuario_inventado', 'ClaveIncorrecta1');
    assert.equal(claveMala.status, 401);
    assert.equal(noExiste.status, 401);
    assert.deepEqual(claveMala.json, noExiste.json);
  });

  test('tras 10 intentos fallidos el inicio de sesión se bloquea 15 minutos (fuerza bruta)', async () => {
    const otro = await iniciarServidor();
    try {
      for (let i = 1; i <= 10; i += 1) {
        assert.equal((await otro.iniciarSesion('coordinador', `Intento${i}`)).status, 401, `intento ${i}`);
      }
      const bloqueado = await otro.iniciarSesion('coordinador', 'Intento11');
      assert.equal(bloqueado.status, 429);
      assert.equal(bloqueado.json.error.codigo, 'DEMASIADOS_INTENTOS');
      assert.equal((await otro.iniciarSesion('coordinador')).status, 429, 'ni siquiera la clave correcta entra');
    } finally {
      await otro.cerrar();
    }
  });

  test('una sesión vencida ya no sirve', async () => {
    const vencida = tokenCon(COORDINADOR, { expiresIn: -60 });
    const r = await api.pedir('GET', '/api/estudiantes', { cookie: vencida });
    assert.equal(r.status, 401);
  });

  test('cerrar sesión elimina la cookie', async () => {
    const r = await api.pedir('POST', '/api/auth/logout', { cookie: coordinador });
    assert.equal(r.status, 204);
    assert.match(r.headers.get('set-cookie'), /itecci_sesion=;/);
  });
});

describe('A08 Fallas en la integridad del software y de los datos', () => {
  test('un token alterado para cambiar el rol se rechaza (firma inválida)', async () => {
    const [cabecera, , firma] = secretaria.split('=')[1].split('.');
    const datos = { ...jwt.decode(secretaria.split('=')[1]), rol: 'COORDINADOR' };
    const alterado = `${COOKIE}=${cabecera}.${Buffer.from(JSON.stringify(datos)).toString('base64url')}.${firma}`;
    const r = await api.pedir('GET', '/api/docentes', { cookie: alterado });
    assert.equal(r.status, 401);
  });

  test('un token sin firma (alg "none") se rechaza', async () => {
    const sinFirma = `${COOKIE}=${jwt.sign(COORDINADOR, null, { algorithm: 'none', subject: '1', issuer: 'itecci-api' })}`;
    const r = await api.pedir('GET', '/api/docentes', { cookie: sinFirma });
    assert.equal(r.status, 401);
  });

  test('un token firmado con otra clave o por otro emisor se rechaza', async () => {
    const otraClave = tokenCon(COORDINADOR, {}, 'clave-de-un-atacante-con-mas-de-32-caracteres');
    const otroEmisor = tokenCon(COORDINADOR, { issuer: 'otro-sistema' });
    assert.equal((await api.pedir('GET', '/api/docentes', { cookie: otraClave })).status, 401);
    assert.equal((await api.pedir('GET', '/api/docentes', { cookie: otroEmisor })).status, 401);
  });
});

describe('A09 Fallas en el registro y la supervisión', () => {
  test('se registran los intentos de inicio de sesión fallidos, sin la contraseña', async () => {
    registro.length = 0;
    await api.iniciarSesion('coordinador', 'ClaveSecreta-NoDebeQuedar');
    const linea = registro.find((l) => l.includes('seguridad:login_fallido'));
    assert.ok(linea, 'hay un evento de seguridad');
    const evento = JSON.parse(linea);
    assert.equal(evento.username, 'coordinador');
    assert.ok(evento.ip && evento.t);
    assert.ok(!registro.join('\n').includes('ClaveSecreta-NoDebeQuedar'));
  });

  test('se registran los accesos denegados con usuario, rol y ruta', async () => {
    registro.length = 0;
    await api.pedir('GET', '/api/diccionario/tablas', { cookie: secretaria });
    const evento = JSON.parse(registro.find((l) => l.includes('seguridad:acceso_denegado')));
    assert.equal(evento.usuario, 'secretaria');
    assert.equal(evento.rol, 'SECRETARIA');
    assert.equal(evento.ruta, '/api/diccionario/tablas');
  });

  test('los errores internos quedan registrados con la misma referencia que ve el usuario', async () => {
    registro.length = 0;
    const r = await api.pedir('GET', '/api/reportes/tablero', { cookie: coordinador });
    const evento = JSON.parse(registro.find((l) => l.includes('error no controlado')));
    assert.equal(evento.referencia, r.json.error.referencia);
    assert.ok(!registro.join('\n').includes(coordinador.split('=')[1]), 'el token de sesión no queda en el registro');
  });
});

describe('A10 Falsificación de peticiones del lado del servidor (SSRF)', () => {
  const archivos = (carpeta) => readdirSync(carpeta).flatMap((nombre) => {
    const ruta = join(carpeta, nombre);
    return statSync(ruta).isDirectory() ? archivos(ruta) : [ruta];
  });

  test('el servidor no hace peticiones a URLs: no hay superficie para SSRF', () => {
    for (const archivo of archivos(fileURLToPath(new URL('../src', import.meta.url)))) {
      const codigo = readFileSync(archivo, 'utf8');
      assert.doesNotMatch(codigo, /\bfetch\(|https?\.(get|request)\(|from ['"](axios|got|undici|node-fetch|node:https?|https?)['"]/, archivo);
    }
  });

  test('una URL enviada como dato se trata como texto y no se consulta', async () => {
    const r = await api.pedir('GET', `/api/estudiantes?q=${encodeURIComponent('http://169.254.169.254/latest/meta-data')}`, { cookie: coordinador });
    assert.equal(r.status, 200);
    assert.equal(api.db.llamadas.at(-1).binds.q, 'http://169.254.169.254/latest/meta-data');
  });
});
