@echo off
setlocal
cd /d "%~dp0"

echo [1/3] Verificando Oracle...
sc query OracleServiceFREE | find "RUNNING" >nul
if errorlevel 1 (
  echo       El servicio OracleServiceFREE esta detenido. Se pedira permiso de administrador para iniciarlo.
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Service OracleServiceFREE'"
)
sc query OracleOraDB23Home1TNSListener | find "RUNNING" >nul
if errorlevel 1 (
  echo       El listener de Oracle esta detenido. Se pedira permiso de administrador para iniciarlo.
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Service OracleOraDB23Home1TNSListener'"
  echo       Esperando a que la base de datos se registre en el listener...
  timeout /t 25 /nobreak >nul
)

if not exist backend\node_modules  (echo       Instalando dependencias del backend...  & pushd backend  & call npm install & popd)
if not exist frontend\node_modules (echo       Instalando dependencias del frontend... & pushd frontend & call npm install & popd)
if not exist backend\.env (
  echo.
  echo  FALTA backend\.env  ^(copie backend\.env.example como backend\.env y complete los valores^)
  pause
  exit /b 1
)

echo [2/3] Iniciando backend...
start "ITECCI - Backend (API)" cmd /k "cd /d "%~dp0backend" && npm start"
timeout /t 4 /nobreak >nul

echo [3/3] Iniciando frontend...
start "ITECCI - Frontend" cmd /k "cd /d "%~dp0frontend" && npm run dev"
timeout /t 4 /nobreak >nul

start "" http://localhost:5173
echo.
echo  Listo. La aplicacion se abre en http://localhost:5173
echo  Para detenerla, cierre las dos ventanas "ITECCI - Backend" e "ITECCI - Frontend".
endlocal
