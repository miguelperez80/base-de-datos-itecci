import { env } from './config/env.js';
import { iniciarPool, cerrarPool } from './config/db.js';
import { crearContenedor } from './container.js';
import { crearApp } from './app.js';
import { logger } from './utils/logger.js';

/** Abre el pool de Oracle e inicia el servidor HTTP. */
async function iniciar() {
  try {
    await iniciarPool();
  } catch (err) {
    logger.error('No se pudo conectar a Oracle. Verifique que el servicio y el listener estén iniciados y los datos de backend/.env', { error: err.message });
    process.exit(1);
  }

  const app = crearApp(crearContenedor());
  const servidor = app.listen(env.PORT, env.HOST, () => {
    logger.info(`API de ITECCI en http://localhost:${env.PORT}/api  (frontend permitido: ${env.FRONTEND_ORIGIN.join(", ")})`);
  });
  servidor.on('error', (err) => {
    logger.error(err.code === 'EADDRINUSE' ? `El puerto ${env.PORT} ya está en uso` : 'No se pudo iniciar el servidor', { error: err.message });
    process.exit(1);
  });

  const apagar = (senal) => {
    logger.info(`${senal}: cerrando servidor`);
    servidor.close(async () => {
      await cerrarPool().catch(() => {});
      process.exit(0);
    });
  };
  process.on('SIGINT', () => apagar('SIGINT'));
  process.on('SIGTERM', () => apagar('SIGTERM'));
}

process.on('unhandledRejection', (razon) => logger.error('promesa rechazada sin manejar', { error: String(razon) }));

iniciar();
