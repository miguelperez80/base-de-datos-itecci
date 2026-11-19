/** Guarda con hash bcrypt la contraseña de los usuarios de la aplicación. */
import bcrypt from 'bcryptjs';
import { iniciarPool, cerrarPool, db } from '../src/config/db.js';
import { UsuarioRepository } from '../src/repositories/procesos.js';

const DEMO = [['coordinador', 'Coord2026#'], ['secretaria', 'Secre2026#']];
const [usuario, clave] = process.argv.slice(2);
const cambios = usuario && clave ? [[usuario, clave]] : DEMO;

await iniciarPool();
try {
  const usuarios = new UsuarioRepository(db);
  for (const [username, password] of cambios) {
    await usuarios.cambiarClave(username, await bcrypt.hash(password, 12));
    console.log(`Clave actualizada: ${username}`);
  }
} catch (err) {
  console.error(`No se pudo actualizar: ${err.message.split('\n')[0]}`);
  process.exitCode = 1;
} finally {
  await cerrarPool();
}
