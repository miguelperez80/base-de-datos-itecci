const pesos = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });
const entero = new Intl.NumberFormat('es-CO');
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export const moneda = (valor) => pesos.format(valor ?? 0);
export const numero = (valor) => entero.format(valor ?? 0);

// Cifra corta para ejes y etiquetas: $12,4 M · $850 mil
export const monedaCorta = (valor) => {
  const v = valor ?? 0;
  if (v >= 1_000_000) return `$${(v / 1_000_000).toLocaleString('es-CO', { maximumFractionDigits: 1 })} M`;
  if (v >= 1_000) return `$${Math.round(v / 1_000)} mil`;
  return `$${v}`;
};

// La API entrega las fechas como AAAA-MM-DD; en pantalla se muestran DD/MM/AAAA
export const fecha = (iso) => {
  if (!iso) return '—';
  const [a, m, d] = iso.split('-');
  return `${d}/${m}/${a}`;
};

// "2026-09" -> "sep 2026"
export const mes = (iso) => {
  const [a, m] = iso.split('-');
  return `${MESES[Number(m) - 1]} ${a}`;
};

export const hoyIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// "Técnico Laboral por Competencias en Sistemas" -> "Sistemas"
export const programaCorto = (nombre) => {
  const corto = (nombre ?? '').replace(/^Técnico Laboral por Competencias (en |como )?/i, '');
  return corto.charAt(0).toUpperCase() + corto.slice(1);
};