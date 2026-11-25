import { OracleRepository, salida } from './OracleRepository.js';

/** Usuarios de la aplicación (pkg_api_seguridad). */
export class UsuarioRepository extends OracleRepository {
  buscarPorUsername(username) {
    return this.fila('pkg_api_seguridad.obtener_usuario(:username)', { username });
  }

  async cambiarClave(username, hash) {
    await this.llamar('BEGIN pkg_api_seguridad.cambiar_clave(:username, :hash); END;', { username, hash });
  }
}

/** Listas desplegables (pkg_api_catalogo). */
export class CatalogoRepository extends OracleRepository {
  listar(nombre) {
    return this.filas('pkg_api_catalogo.listar(:nombre)', { nombre });
  }
}

/** Matrículas, plan de pagos y recibos (pkg_api_matricula). */
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

/** Recibos de caja (pkg_api_pago). */
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

/** Indicadores, recaudo y cartera (pkg_api_reportes). */
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

/** Diccionario de datos de Oracle (pkg_api_diccionario). */
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

/** Planilla de notas de un grupo y registro, corrección y eliminación de notas (pkg_api_calificacion). */
export class CalificacionRepository extends OracleRepository {
  async planilla(grupoId) {
    const { grupo, competencias, estudiantes, notas } = await this.llamar(
      'BEGIN pkg_api_calificacion.planilla(:grupo_id, :grupo, :competencias, :estudiantes, :notas); END;',
      {
        grupo_id: grupoId, grupo: salida.cursor(), competencias: salida.cursor(),
        estudiantes: salida.cursor(), notas: salida.cursor(),
      },
    );
    return { grupo: grupo[0] ?? null, competencias, estudiantes, notas };
  }

  async registrar({ matricula_id, competencia_id, tipo, nota }, usuarioId) {
    const { id } = await this.llamar(
      'BEGIN pkg_api_calificacion.registrar(:matricula_id, :competencia_id, :tipo, :nota, :usuario_id, :id); END;',
      { matricula_id, competencia_id, tipo, nota, usuario_id: usuarioId, id: salida.numero() },
    );
    return id;
  }

  async corregir(id, nota, usuarioId) {
    await this.llamar('BEGIN pkg_api_calificacion.corregir(:id, :nota, :usuario_id); END;', { id, nota, usuario_id: usuarioId });
  }

  async eliminar(id) {
    await this.llamar('BEGIN pkg_api_calificacion.eliminar(:id); END;', { id });
  }
}
