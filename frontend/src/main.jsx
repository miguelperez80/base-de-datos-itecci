import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App.jsx';
import { AuthProvider } from './context/AuthContext.jsx';
import { AvisosProvider } from './context/AvisosContext.jsx';
import './styles/global.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter basename={import.meta.env.BASE_URL.replace(/\/$/, '')}>
      <AvisosProvider>
        <AuthProvider>
          <App />
        </AuthProvider>
      </AvisosProvider>
    </BrowserRouter>
  </StrictMode>,
);
