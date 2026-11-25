import { AppError } from '../utils/AppError.js';
import { aFiltro, aPagina } from './CrudService.js';

/** Matrículas: listado, detalle con plan de pagos, matrícula y retiro. */
export class MatriculaService {
  constructor(matriculaRepository) {
    this.matriculas = matriculaRepository;
  }

  async listar(consulta) {
    return aPagina(await this.matriculas.listar(aFiltro(consulta)), consulta);
  }

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

/** Recibos de caja: listado, registro y anulación. */
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

/** Tablero de indicadores y reporte de cartera. */
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

/** Consulta del diccionario de datos. */
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

const aOcupacion = (texto) => (texto ? texto.split(',').map((par) => {
  const [dia, grupo] = par.split(':');
  return { dia: Number(dia), grupo };
}) : []);

/** Disponibilidad de docentes y aulas de un periodo para programar un grupo. */
export class DisponibilidadService {
  constructor(grupoRepository) {
    this.repositorio = grupoRepository;
  }

  async consultar({ periodo_id: periodoId, grupo_id: grupoId }) {
    const { docentes, aulas } = await this.repositorio.disponibilidad(periodoId, grupoId);
    const conOcupacion = ({ ocupacion, ...fila }) => ({ ...fila, ocupacion: aOcupacion(ocupacion) });
    return { docentes: docentes.map(conOcupacion), aulas: aulas.map(conOcupacion) };
  }
}

/** Grupos de un docente con sus días de clase y sus estudiantes. */
export class CargaDocenteService {
  constructor(docenteRepository) {
    this.repositorio = docenteRepository;
  }

  async consultar(id) {
    const { grupos, estudiantes } = await this.repositorio.carga(id);
    return grupos.map((g) => ({ ...g, estudiantes: estudiantes.filter((e) => e.grupo_id === g.id) }));
  }
}

/** Planilla de notas: cada estudiante con su nota ordinaria, supletorio y nota definitiva por competencia. */
export class CalificacionService {
  constructor(calificacionRepository) {
    this.repositorio = calificacionRepository;
  }

  async planilla(grupoId) {
    const { grupo, competencias, estudiantes, notas } = await this.repositorio.planilla(grupoId);
    return {
      grupo,
      competencias,
      estudiantes: estudiantes.map((e) => {
        const propias = notas.filter((n) => n.matricula_id === e.matricula_id);
        const porCompetencia = Object.fromEntries(competencias.map((c) => {
          const ordinaria = propias.find((n) => n.competencia_id === c.id && n.tipo === 'Ordinaria') ?? null;
          const supletorio = propias.find((n) => n.competencia_id === c.id && n.tipo === 'Supletorio') ?? null;
          return [c.id, { ordinaria, supletorio, definitiva: supletorio?.nota ?? ordinaria?.nota ?? null }];
        }));
        const definitivas = Object.values(porCompetencia).map((n) => n.definitiva).filter((n) => n !== null);
        return {
          ...e,
          notas: porCompetencia,
          aprobadas: definitivas.filter((n) => n >= 3).length,
          promedio: definitivas.length ? Math.round((definitivas.reduce((a, b) => a + b, 0) / definitivas.length) * 10) / 10 : null,
        };
      }),
    };
  }

  registrar(datos, usuarioId) {
    return this.repositorio.registrar(datos, usuarioId);
  }

  corregir(id, nota, usuarioId) {
    return this.repositorio.corregir(id, nota, usuarioId);
  }

  eliminar(id) {
    return this.repositorio.eliminar(id);
  }
}
