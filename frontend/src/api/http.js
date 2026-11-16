// Cliente HTTP de la API. Es el único módulo que conoce la URL del backend y usa fetch.
const BASE = import.meta.env.VITE_API_URL ?? 'http://localhost:3000/api';

export const EVENTO_SESION_EXPIRADA = 'itecci:sesion-expirada';

export class ApiError extends Error {
  constructor(status, cuerpo) {
    super(cuerpo?.mensaje ?? 'Ocurrió un error inesperado');
    this.name = 'ApiError';
    this.status = status;
    this.codigo = cuerpo?.codigo;
    this.detalles = cuerpo?.detalles ?? [];
    this.referencia = cuerpo?.referencia;
  }

  // { campo: mensaje } para pintar los errores junto a cada campo del formulario
  get porCampo() {
    return Object.fromEntries(this.detalles.filter((d) => d.campo).map((d) => [d.campo, d.mensaje]));
  }
}

async function pedir(metodo, ruta, cuerpo) {
  let respuesta;
  try {
    respuesta = await fetch(BASE + ruta, {
      method: metodo,
      credentials: 'include', // la sesión viaja en una cookie httpOnly: JavaScript nunca ve el token
      headers: cuerpo ? { 'Content-Type': 'application/json' } : undefined,
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
  } catch {
    throw new ApiError(0, { codigo: 'SIN_CONEXION', mensaje: 'No hay conexión con el servidor. Verifique que el backend esté iniciado.' });
  }

  if (respuesta.status === 204) return null;
  const datos = await respuesta.json().catch(() => null);
  if (!respuesta.ok) {
    if (respuesta.status === 401 && !ruta.startsWith('/auth/')) {
      window.dispatchEvent(new Event(EVENTO_SESION_EXPIRADA));
    }
    throw new ApiError(respuesta.status, datos?.error);
  }
  return datos;
}

const conConsulta = (ruta, consulta) => {
  const limpia = Object.entries(consulta ?? {}).filter(([, v]) => v !== undefined && v !== null && v !== '');
  return limpia.length ? `${ruta}?${new URLSearchParams(limpia)}` : ruta;
};

export const api = {
  get: (ruta, consulta) => pedir('GET', conConsulta(ruta, consulta)),
  post: (ruta, cuerpo) => pedir('POST', ruta, cuerpo ?? {}),
  put: (ruta, cuerpo) => pedir('PUT', ruta, cuerpo),
  delete: (ruta) => pedir('DELETE', ruta),
};
