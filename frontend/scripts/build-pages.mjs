/** Compila el frontend para GitHub Pages con la ruta base del repositorio. */
import { execSync } from 'node:child_process';
import { copyFileSync, writeFileSync } from 'node:fs';

const base = process.env.VITE_BASE ?? '/base-de-datos-itecci/';
execSync('npx vite build', { stdio: 'inherit', env: { ...process.env, VITE_BASE: base } });
copyFileSync('dist/index.html', 'dist/404.html');
writeFileSync('dist/.nojekyll', '');
console.log('Listo: dist/ preparado para GitHub Pages en ' + base);