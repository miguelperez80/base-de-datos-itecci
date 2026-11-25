import { Navigate, Outlet, Route, Routes, useLocation } from 'react-router-dom';
import { ROLES, useAuth } from './context/AuthContext.jsx';
import MainLayout from './layouts/MainLayout.jsx';
import Login from './pages/Login.jsx';
import Tablero from './pages/Tablero.jsx';
import { Contratos, Docentes, Estudiantes, Grupos, Programas } from './pages/Catalogos.jsx';
import Matriculas from './pages/Matriculas.jsx';
import Pagos from './pages/Pagos.jsx';
import Cartera from './pages/Cartera.jsx';
import Calificaciones from './pages/Calificaciones.jsx';
import Diccionario from './pages/Diccionario.jsx';
import { Mensaje } from './pages/Mensaje.jsx';

/** Muestra la ruta solo con sesión iniciada y, si se indica, con el rol requerido. */
function RutaProtegida({ roles }) {
  const { usuario, cargando, tieneRol } = useAuth();
  const ubicacion = useLocation();

  if (cargando) return <div className="cargando-pagina" role="status">Cargando…</div>;
  if (!usuario) return <Navigate to="/ingresar" replace state={{ desde: ubicacion.pathname }} />;
  if (!tieneRol(roles)) {
    return <Mensaje titulo="Acceso restringido" texto="Su rol no tiene permiso para ver esta sección." />;
  }
  return <Outlet />;
}

/** Rutas de la aplicación. */
export default function App() {
  return (
    <Routes>
      <Route path="/ingresar" element={<Login />} />
      <Route element={<RutaProtegida />}>
        <Route element={<MainLayout />}>
          <Route index element={<Tablero />} />
          <Route path="estudiantes" element={<Estudiantes />} />
          <Route path="matriculas" element={<Matriculas />} />
          <Route path="pagos" element={<Pagos />} />
          <Route path="cartera" element={<Cartera />} />
          <Route path="calificaciones" element={<Calificaciones />} />
          <Route path="grupos" element={<Grupos />} />
          <Route path="programas" element={<Programas />} />
          <Route element={<RutaProtegida roles={[ROLES.COORDINADOR]} />}>
            <Route path="docentes" element={<Docentes />} />
            <Route path="contratos" element={<Contratos />} />
            <Route path="diccionario" element={<Diccionario />} />
          </Route>
          <Route path="*" element={<Mensaje titulo="Página no encontrada" texto="La dirección no corresponde a ninguna sección del sistema." />} />
        </Route>
      </Route>
    </Routes>
  );
}
