import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BookOpen, ClipboardList, Database, GraduationCap, LayoutDashboard, LogOut, Menu, Presentation, Receipt, Users, Wallet,
} from 'lucide-react';
import logo from '../assets/logo-itecci.png';
import { NOMBRE_ROL, ROLES, useAuth } from '../context/AuthContext.jsx';

// Menú de la aplicación. `roles` limita quién ve cada opción (el backend vuelve a comprobarlo).
export const MENU = [
  { grupo: 'General', opciones: [
    { ruta: '/', texto: 'Tablero', icono: LayoutDashboard },
  ] },
  { grupo: 'Secretaría', opciones: [
    { ruta: '/estudiantes', texto: 'Estudiantes', icono: Users },
    { ruta: '/matriculas', texto: 'Matrículas', icono: ClipboardList },
    { ruta: '/pagos', texto: 'Recibos de caja', icono: Receipt },
    { ruta: '/cartera', texto: 'Cartera', icono: Wallet },
  ] },
  { grupo: 'Oferta académica', opciones: [
    { ruta: '/grupos', texto: 'Grupos', icono: Presentation },
    { ruta: '/programas', texto: 'Programas técnicos', icono: BookOpen },
    { ruta: '/docentes', texto: 'Docentes', icono: GraduationCap, roles: [ROLES.COORDINADOR] },
  ] },
  { grupo: 'Administración', opciones: [
    { ruta: '/diccionario', texto: 'Diccionario de datos', icono: Database, roles: [ROLES.COORDINADOR] },
  ] },
];

/**
 * Página maestra: barra lateral, barra superior y el área donde se dibuja cada pantalla (<Outlet />).
 * Todas las pantallas internas comparten esta estructura.
 */
export default function MainLayout() {
  const { usuario, cerrarSesion, tieneRol } = useAuth();
  const [abierto, setAbierto] = useState(false);
  const { pathname } = useLocation();

  useEffect(() => { setAbierto(false); }, [pathname]);

  const actual = MENU.flatMap((g) => g.opciones).find((o) => o.ruta === pathname)?.texto ?? 'ITECCI';
  useEffect(() => { document.title = `${actual} · ITECCI`; }, [actual]);

  return (
    <div className="app">
      <aside className={`lateral ${abierto ? 'abierto' : ''}`} aria-label="Menú principal">
        <div className="lateral-logo">
          <img src={logo} alt="ITECCI - Instituto Técnico Empresarial Cámara de Comercio de Ipiales" width="596" height="335" />
        </div>
        <nav>
          {MENU.map((g) => {
            const visibles = g.opciones.filter((o) => tieneRol(o.roles));
            if (visibles.length === 0) return null;
            return (
              <div key={g.grupo}>
                <div className="lateral-grupo">{g.grupo}</div>
                {visibles.map(({ ruta, texto, icono: Icono }) => (
                  <NavLink key={ruta} to={ruta} end={ruta === '/'} className={({ isActive }) => (isActive ? 'activo' : undefined)}>
                    <Icono aria-hidden="true" /> {texto}
                  </NavLink>
                ))}
              </div>
            );
          })}
        </nav>
        <div className="lateral-pie">Técnicos Laborales por Competencias<br />Cámara de Comercio de Ipiales</div>
      </aside>
      <button type="button" className={`velo ${abierto ? 'abierto' : ''}`} onClick={() => setAbierto(false)} aria-label="Cerrar menú" />

      <div className="principal">
        <header className="superior">
          <button type="button" className="btn btn-icono menu-movil" onClick={() => setAbierto(true)} aria-label="Abrir menú">
            <Menu aria-hidden="true" />
          </button>
          <div className="superior-titulo">{actual}</div>
          <div className="superior-usuario">
            <strong>{usuario.nombre}</strong>
            <span>{NOMBRE_ROL[usuario.rol] ?? usuario.rol}</span>
          </div>
          <button type="button" className="btn btn-secundario" onClick={cerrarSesion}>
            <LogOut aria-hidden="true" /> Salir
          </button>
        </header>
        <main className="contenido">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
