const escribir = (nivel, mensaje, datos) => {
  const linea = { t: new Date().toISOString(), nivel, mensaje, ...datos };
  (nivel === 'error' ? console.error : console.log)(JSON.stringify(linea));
};

/** Registro en consola en formato JSON. */
export const logger = {
  info: (mensaje, datos) => escribir('info', mensaje, datos),
  warn: (mensaje, datos) => escribir('warn', mensaje, datos),
  error: (mensaje, datos) => escribir('error', mensaje, datos),
  seguridad: (evento, datos) => escribir('warn', `seguridad:${evento}`, datos),
};
