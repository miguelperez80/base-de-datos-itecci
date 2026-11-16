import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { api, EVENTO_SESION_EXPIRADA } from '../api/http.js';

export const ROLES = { COORDINADOR: 'COORDINADOR', SECRETARIA: 'SECRETARIA' };
export const NOMBRE_ROL = { COORDINADOR: 'Coordinador General', SECRETARIA: 'Secretaría' };

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [usuario, setUsuario] = useState(null);
  const [cargando, setCargando] = useState(true);

  // Al abrir la aplicación se pregunta al backend si la cookie de sesión sigue vigente
  useEffect(() => {
    api.get('/auth/yo')
      .then((r) => setUsuario(r.usuario))
      .catch(() => setUsuario(null))
      .finally(() => setCargando(false));
  }, []);

  useEffect(() => {
    const expirar = () => setUsuario(null);
    window.addEventListener(EVENTO_SESION_EXPIRADA, expirar);
    return () => window.removeEventListener(EVENTO_SESION_EXPIRADA, expirar);
  }, []);

  const iniciarSesion = useCallback(async (username, password) => {
    const r = await api.post('/auth/login', { username, password });
    setUsuario(r.usuario);
  }, []);

  const cerrarSesion = useCallback(async () => {
    await api.post('/auth/logout').catch(() => {});
    setUsuario(null);
  }, []);

  const valor = useMemo(() => ({
    usuario, cargando, iniciarSesion, cerrarSesion,
    esCoordinador: usuario?.rol === ROLES.COORDINADOR,
    tieneRol: (roles) => !!usuario && (!roles || roles.includes(usuario.rol)),
  }), [usuario, cargando, iniciarSesion, cerrarSesion]);

  return <AuthContext.Provider value={valor}>{children}</AuthContext.Provider>;
}

export const useAuth = () => useContext(AuthContext);
