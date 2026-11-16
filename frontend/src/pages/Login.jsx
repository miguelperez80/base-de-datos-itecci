import { useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { CircleAlert, LogIn } from 'lucide-react';
import logo from '../assets/logo-itecci.png';
import { useAuth } from '../context/AuthContext.jsx';

export default function Login() {
  const { usuario, cargando, iniciarSesion } = useAuth();
  const { state } = useLocation();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [enviando, setEnviando] = useState(false);

  if (!cargando && usuario) return <Navigate to={state?.desde ?? '/'} replace />;

  const enviar = async (e) => {
    e.preventDefault();
    if (!username.trim() || !password) {
      setError('Escriba su usuario y su contraseña.');
      return;
    }
    setEnviando(true);
    setError(null);
    try {
      await iniciarSesion(username.trim().toLowerCase(), password);
    } catch (err) {
      setError(err.status === 400 ? 'Usuario o contraseña incorrectos' : err.message);
      setPassword('');
      setEnviando(false);
    }
  };

  return (
    <div className="login">
      <section className="login-marca" aria-hidden="true">
        <small>Cámara de Comercio de Ipiales</small>
        <div>
          <div className="linea" />
          <h1>Gestión académica y de cartera</h1>
          <p>Matrículas, recibos de caja, estado de crédito y oferta de los Técnicos Laborales por Competencias, en un solo lugar.</p>
        </div>
        <small>Instituto Técnico Empresarial · ITECCI</small>
      </section>

      <main className="login-panel">
        <div className="login-caja">
          <img src={logo} alt="ITECCI - Instituto Técnico Empresarial Cámara de Comercio de Ipiales" width="596" height="335" />
          <h2>Iniciar sesión</h2>
          <p style={{ color: 'var(--texto-2)', fontSize: '0.9375rem' }}>Ingrese con el usuario asignado por la coordinación.</p>

          {!['localhost', '127.0.0.1'].includes(window.location.hostname) && (
            <div className="alerta info" style={{ marginTop: 16 }}>
              <span>Esta es la interfaz publicada. Los datos están en Oracle, en el equipo del proyecto: para ingresar, el backend debe estar encendido allí (<code>iniciar.bat</code>). Si el navegador pregunta si este sitio puede acceder a la red local o a otras aplicaciones de este equipo, elija <strong>Permitir</strong>.</span>
            </div>
          )}

          <form onSubmit={enviar} noValidate>
            {error && (
              <div className="alerta error" role="alert"><CircleAlert aria-hidden="true" /><span>{error}</span></div>
            )}
            <div className="campo">
              <label htmlFor="usuario">Usuario</label>
              <input id="usuario" className="entrada" value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" autoCapitalize="none" spellCheck="false" maxLength={40} autoFocus disabled={enviando} />
            </div>
            <div className="campo">
              <label htmlFor="clave">Contraseña</label>
              <input id="clave" type="password" className="entrada" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" maxLength={72} disabled={enviando} />
            </div>
            <button type="submit" className="btn btn-primario btn-bloque" disabled={enviando}>
              <LogIn aria-hidden="true" /> {enviando ? 'Verificando…' : 'Ingresar'}
            </button>
          </form>
        </div>
      </main>
    </div>
  );
}
