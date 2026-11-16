import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// El frontend corre en http://localhost:5173 y consume la API en http://localhost:3000/api.
// El puerto es fijo porque el backend solo acepta peticiones de ese origen (CORS).
export default defineConfig({
  // En GitHub Pages el sitio vive en /base-de-datos-itecci/ (npm run build:pages)
  base: process.env.VITE_BASE ?? '/',
  plugins: [react()],
  server: { host: 'localhost', port: 5173, strictPort: true },
  preview: { host: 'localhost', port: 5173, strictPort: true },
});
