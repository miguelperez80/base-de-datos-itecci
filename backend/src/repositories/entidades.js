import { CrudRepository } from './CrudRepository.js';

// Repositorios CRUD: cada uno apunta a su paquete PL/SQL y declara los parámetros que este recibe.

export class EstudianteRepository extends CrudRepository {
  constructor(db) {
    super(db, {
      paquete: 'pkg_api_estudiante',
      camposCrear: [
        'tipo_documento', 'cedula', 'nombres', 'apellidos', 'fecha_nacimiento', 'telefono', 'email', 'direccion',
        'ocupacion', 'regimen_salud', 'condicion_medica', 'estrato', 'estado_civil', 'nivel_formacion',
        'autoriza_centrales', 'doc_cedula', 'doc_diploma', 'doc_foto',
      ],
    });
  }
}

export class DocenteRepository extends CrudRepository {
  constructor(db) {
    super(db, {
      paquete: 'pkg_api_docente',
      camposCrear: ['cedula', 'nombres', 'apellidos', 'email', 'telefono', 'nivel_formacion', 'anios_experiencia', 'activo'],
    });
  }
}

export class TecnicoRepository extends CrudRepository {
  constructor(db) {
    super(db, { paquete: 'pkg_api_tecnico', camposCrear: ['codigo', 'nombre', 'activo'] });
  }
}

export class GrupoRepository extends CrudRepository {
  constructor(db) {
    const editables = ['docente_id', 'aula_id', 'cupo_min', 'cupo_max', 'estado', 'dia1', 'dia2'];
    super(db, {
      paquete: 'pkg_api_grupo',
      camposCrear: ['tecnico_id', 'periodo_id', 'semestre', ...editables],
      camposEditar: editables,
    });
  }
}
