import 'dotenv/config';
import { z } from 'zod';

// La configuración se valida al arrancar: si falta algo, el servidor no inicia.
const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  HOST: z.string().default('127.0.0.1'),
  // Uno o varios orígenes separados por coma (el frontend local y, si se publica, el de GitHub Pages)
  FRONTEND_ORIGIN: z.string().default('http://localhost:5173')
    .transform((v) => v.split(',').map((o) => o.trim().replace(/\/$/, '')).filter(Boolean))
    .pipe(z.array(z.string().url()).min(1)),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string().min(1),
  DB_CONNECT_STRING: z.string().min(1),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET debe tener al menos 32 caracteres'),
  JWT_EXPIRES_MIN: z.coerce.number().int().min(5).max(720).default(120),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  const faltantes = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('\n  ');
  console.error(`Configuración inválida. Revise el archivo backend/.env\n  ${faltantes}`);
  process.exit(1);
}

export const env = Object.freeze(parsed.data);
