import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { AppError } from '../utils/AppError.js';
import { logger } from '../utils/logger.js';

// Firma y verificación del token de sesión (HS256, con expiración)
export class TokenService {
  constructor({ secreto, minutos }) {
    this.secreto = secreto;
    this.minutos = minutos;
  }

  firmar(usuario) {
    return jwt.sign(
      { username: usuario.username, nombre: usuario.nombre, rol: usuario.rol },
      this.secreto,
      { algorithm: 'HS256', expiresIn: `${this.minutos}m`, subject: String(usuario.id), issuer: 'itecci-api' },
    );
  }

  verificar(token) {
    const datos = jwt.verify(token, this.secreto, { algorithms: ['HS256'], issuer: 'itecci-api' });
    return { id: Number(datos.sub), username: datos.username, nombre: datos.nombre, rol: datos.rol };
  }
}

// Hash de comparación para cuando el usuario no existe: el tiempo de respuesta es el mismo
// y no se revela si el nombre de usuario es válido.
const HASH_SENUELO = bcrypt.hashSync('usuario-inexistente', 12);
const CREDENCIALES_INVALIDAS = 'Usuario o contraseña incorrectos';

export class AuthService {
  constructor(usuarioRepository, tokenService) {
    this.usuarios = usuarioRepository;
    this.tokens = tokenService;
  }

  async iniciarSesion({ username, password }, ip) {
    const usuario = await this.usuarios.buscarPorUsername(username);
    const hash = usuario?.password_hash?.startsWith('$2') ? usuario.password_hash : HASH_SENUELO;
    const coincide = await bcrypt.compare(password, hash);

    if (!usuario || !coincide || usuario.activo !== 1 || hash === HASH_SENUELO) {
      logger.seguridad('login_fallido', { username, ip });
      throw AppError.noAutenticado(CREDENCIALES_INVALIDAS);
    }

    logger.info('login', { username, rol: usuario.rol, ip });
    const publico = { id: usuario.id, username: usuario.username, nombre: usuario.nombre, rol: usuario.rol };
    return { usuario: publico, token: this.tokens.firmar(publico) };
  }
}
