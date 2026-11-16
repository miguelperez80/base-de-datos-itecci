import { OracleRepository, salida } from './OracleRepository.js';

// Repositorios de los procesos que no son un CRUD simple.

export class UsuarioRepository extends OracleRepository {
  buscarPorUsername(username) {
    return this.fila('pkg_api_seguridad.obtener_usuario(:username)', { username });
  }

  async cambiarClave(username, hash) {
    await this.llamar('BEGIN pkg_api_seguridad.cambiar_clave(:username, :hash); END;', { username, hash });
  }
}

export class CatalogoRepository extends OracleRepository {
  listar(nombre) {
    return this.filas('pkg_api_catalogo.listar(:nombre)', { nombre });
  }
}

export class MatriculaRepository extends OracleRepository {
  listar({ estado, ...filtro }) {
    return this.pagina('pkg_api_matricula.listar', filtro, { estado: estado ?? null });
  }

  obtener(id) {
    return this.fila('pkg_api_matricula.obtener(:id)', { id });
  }

  cuotas(id) {
    return this.filas('pkg_api_matricula.cuotas(:id)', { id });
  }

  pagos(id) {
    return this.filas('pkg_api_matricula.pagos(:id)', { id });
  }

  async matricular({ estudiante_id, grupo_id, usuario_id }) {
    const { id } = await this.llamar(
      'BEGIN pkg_api_matricula.matricular(:estudiante_id, :grupo_id, :usuario_id, :id); END;',
      { estudiante_id, grupo_id, usuario_id, id: salida.numero() },
    );
    return id;
  }

  async retirar(id, observacion) {
    await this.llamar('BEGIN pkg_api_matricula.retirar(:id, :observacion); END;', { id, observacion });
  }
}

export class PagoRepository extends OracleRepository {
  listar(filtro) {
    return this.pagina('pkg_api_pago.listar', filtro);
  }

  async registrar({ matricula_id, valor, medio_pago_id, referencia, usuario_id }) {
    const { id, recibo } = await this.llamar(
      'BEGIN pkg_api_pago.registrar(:matricula_id, :valor, :medio_pago_id, :referencia, :usuario_id, :id, :recibo); END;',
      { matricula_id, valor, medio_pago_id, referencia: referencia ?? null, usuario_id, id: salida.numero(), recibo: salida.texto(20) },
    );
    return { id, numero_recibo: recibo };
  }

  async anular(id, motivo) {
    await this.llamar('BEGIN pkg_api_pago.anular(:id, :motivo); END;', { id, motivo });
  }
}

export class ReporteRepository extends OracleRepository {
  indicadores() {
    return this.fila('pkg_api_reportes.indicadores');
  }

  carteraResumen() {
    return this.filas('pkg_api_reportes.cartera_resumen');
  }

  recaudoMensual() {
    return this.filas('pkg_api_reportes.recaudo_mensual');
  }

  matriculasPorTecnico() {
    return this.filas('pkg_api_reportes.matriculas_por_tecnico');
  }

  cartera({ estado, ...filtro }) {
    return this.pagina('pkg_api_reportes.cartera', filtro, { estado: estado ?? null });
  }
}

export class DiccionarioRepository extends OracleRepository {
  tablas() {
    return this.filas('pkg_api_diccionario.tablas');
  }

  columnas(tabla) {
    return this.filas('pkg_api_diccionario.columnas(:tabla)', { tabla });
  }

  objetos() {
    return this.filas('pkg_api_diccionario.objetos');
  }

  subprogramas() {
    return this.filas('pkg_api_diccionario.subprogramas');
  }

  async ping() {
    await this.llamar('BEGIN NULL; END;');
  }
}
