import { AppError } from '../utils/AppError.js';
import { aFiltro, aPagina } from './CrudService.js';

export class MatriculaService {
  constructor(matriculaRepository) {
    this.matriculas = matriculaRepository;
  }

  async listar(consulta) {
    return aPagina(await this.matriculas.listar(aFiltro(consulta)), consulta);
  }

  // Cabecera + plan de pagos + recibos de una matrícula
  async detalle(id) {
    const [matricula, cuotas, pagos] = await Promise.all([
      this.matriculas.obtener(id), this.matriculas.cuotas(id), this.matriculas.pagos(id),
    ]);
    if (!matricula) throw AppError.noEncontrado('La matrícula no existe');
    return { ...matricula, cuotas, pagos };
  }

  async matricular(datos, usuario) {
    const id = await this.matriculas.matricular({ ...datos, usuario_id: usuario.id });
    return this.detalle(id);
  }

  async retirar(id, observacion) {
    await this.matriculas.retirar(id, observacion);
    return this.detalle(id);
  }
}

export class PagoService {
  constructor(pagoRepository) {
    this.pagos = pagoRepository;
  }

  async listar(consulta) {
    return aPagina(await this.pagos.listar(aFiltro(consulta)), consulta);
  }

  registrar(datos, usuario) {
    return this.pagos.registrar({ ...datos, usuario_id: usuario.id });
  }

  anular(id, motivo, usuario) {
    return this.pagos.anular(id, `${motivo} (anulado por ${usuario.username})`.slice(0, 300));
  }
}

export class ReporteService {
  constructor(reporteRepository) {
    this.reportes = reporteRepository;
  }

  async tablero() {
    const [indicadores, cartera, recaudo, porTecnico] = await Promise.all([
      this.reportes.indicadores(), this.reportes.carteraResumen(),
      this.reportes.recaudoMensual(), this.reportes.matriculasPorTecnico(),
    ]);
    return { indicadores, cartera, recaudo, porTecnico };
  }

  async cartera(consulta) {
    return aPagina(await this.reportes.cartera(aFiltro(consulta)), consulta);
  }
}

export class DiccionarioService {
  constructor(diccionarioRepository) {
    this.diccionario = diccionarioRepository;
  }

  tablas() {
    return this.diccionario.tablas();
  }

  async columnas(tabla) {
    const columnas = await this.diccionario.columnas(tabla);
    if (columnas.length === 0) throw AppError.noEncontrado('La tabla no existe en el esquema');
    return columnas;
  }

  objetos() {
    return this.diccionario.objetos();
  }

  subprogramas() {
    return this.diccionario.subprogramas();
  }
}
