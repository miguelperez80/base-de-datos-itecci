// Registro sencillo en consola. Nunca se registran contraseñas, tokens ni cuerpos de petición.
const escribir = (nivel, mensaje, datos) => {
  const linea = { t: new Date().toISOString(), nivel, mensaje, ...datos };
  (nivel === 'error' ? console.error : console.log)(JSON.stringify(linea));
};

export const logger = {
  info: (mensaje, datos) => escribir('info', mensaje, datos),
  warn: (mensaje, datos) => escribir('warn', mensaje, datos),
  error: (mensaje, datos) => escribir('error', mensaje, datos),
  seguridad: (evento, datos) => escribir('warn', `seguridad:${evento}`, datos),
};
