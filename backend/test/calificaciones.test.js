import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { iniciarServidor } from './apoyo.js';

let api;
let secretaria;
let coordinador;

before(async () => {
  api = await iniciarServidor();
  secretaria = (await api.iniciarSesion('secretaria')).cookie;
  coordinador = (await api.iniciarSesion('coordinador')).cookie;
});
after(() => api.cerrar());

describe('Calificaciones', () => {
  test('la planilla reúne por estudiante la nota ordinaria, el supletorio y la definitiva de cada competencia', async () => {
    const r = await api.pedir('GET', '/api/calificaciones/grupos/9', { cookie: secretaria });
    assert.equal(r.status, 200);
    const { grupo, competencias, estudiantes } = r.json;
    assert.equal(grupo.codigo, 'SIS-2026B-S2');
    assert.equal(competencias.length, 2);

    const [ana, luis] = estudiantes;
    assert.equal(ana.notas[5].definitiva, 4.5);
    assert.equal(ana.aprobadas, 2);
    assert.equal(ana.promedio, 4);

    assert.equal(luis.notas[5].ordinaria.nota, 2);
    assert.equal(luis.notas[5].supletorio.nota, 3.2);
    assert.equal(luis.notas[5].definitiva, 3.2, 'el supletorio reemplaza a la ordinaria');
    assert.equal(luis.notas[6].definitiva, null);
    assert.equal(luis.aprobadas, 1);
  });

  test('la secretaria registra una nota y queda como quien la registró', async () => {
    const r = await api.pedir('POST', '/api/calificaciones', {
      cookie: secretaria, cuerpo: { matricula_id: 101, competencia_id: 6, tipo: 'Ordinaria', nota: '3,5' },
    });
    assert.equal(r.status, 201);
    const { sql, binds } = api.db.llamadas.at(-1);
    assert.match(sql, /pkg_api_calificacion\.registrar/);
    assert.equal(binds.nota, 3.5, 'acepta la coma decimal');
    assert.equal(binds.usuario_id, 2);
  });

  test('una corrección guarda el nuevo valor y el usuario que corrigió', async () => {
    const r = await api.pedir('PUT', '/api/calificaciones/2', { cookie: coordinador, cuerpo: { nota: 4.1 } });
    assert.equal(r.status, 204);
    assert.deepEqual(api.db.llamadas.at(-1).binds, { id: 2, nota: 4.1, usuario_id: 1 });
  });

  test('las reglas de la base llegan al formulario: supletorio de una competencia aprobada (422)', async () => {
    const r = await api.pedir('POST', '/api/calificaciones', {
      cookie: secretaria, cuerpo: { matricula_id: 100, competencia_id: 5, tipo: 'Supletorio', nota: 4 },
    });
    assert.equal(r.status, 422);
    assert.match(r.json.error.mensaje, /Supletorio no permitido/);
  });

  test('solo coordinación elimina notas', async () => {
    assert.equal((await api.pedir('DELETE', '/api/calificaciones/4', { cookie: secretaria })).status, 403);
    assert.equal((await api.pedir('DELETE', '/api/calificaciones/4', { cookie: coordinador })).status, 204);
  });
});
