# 03_SQL_SERVER - DataSalud: atenciones por diagnostico (MAMIS)

Base de datos en **SQL Server (T-SQL)** que recibe los Excel de atenciones (abuso psicologico, fisico, sexual y negligencia), limpia y valida los datos, los guarda en un modelo en estrella y prepara 3 tablas resumen (warehouse) para **Power BI**.

## Estructura

```
03_SQL_SERVER/
  01_DATABASE/          tablas, funciones, vistas y tablas del warehouse
  02_AUTOMATIZACION/    carga de CSV, limpieza, ETL y carga del warehouse
  03_SEGURIDAD/         roles y permisos
  04_AUDITORIA/         triggers de auditoria y validacion, consultas de control
  05_BACKUPS/           respaldo, restauracion y el archivo .bak
  06_RENDIMIENTO/       indice y prueba de velocidad (antes y despues)
```

Cada carpeta tiene su `README.md` (con el codigo) y los archivos `.sql` para ejecutar esa parte en SQL Server Management Studio.

## Flujo de los datos

```
Excel -> CSV UTF-8 -> BULK INSERT -> origen_atenciones_diagnostico (todo texto)
      -> usp_cargar_atenciones (limpia y valida)
           |-- filas malas o repetidas -> tbl_cuarentena_atenciones (con el motivo)
           '-- filas buenas -> catalogos (Ubicacion, Genero, Rango_Edad, Diagnostico)
                            -> Atencion_Diagnostico (hechos)
      -> usp_cargar_warehouse -> dw.Resumen_* (3 tablas) -> Power BI
```

`log_auditoria` y `etl_log` registran cada paso y el cuadre de sumas (origen = cargado + cuarentena).

## Orden de ejecucion

| Paso | Archivos |
|---|---|
| 1. Estructura | `01_DATABASE`: `01`, `02`, `03`, `04` |
| 2. Procedimientos | `02_AUTOMATIZACION`: `01` a `05` |
| 3. Seguridad | `03_SEGURIDAD`: `01` |
| 4. Triggers | `04_AUDITORIA`: `01`, `02` |
| 5. Pruebas (opcional) | `01_DATABASE/05`, `02_AUTOMATIZACION/06`, `04_AUDITORIA/03`, `03_SEGURIDAD/02` |
| 6. Rendimiento (opcional) | `06_RENDIMIENTO`: `01` |
| 7. Datos reales | `02_AUTOMATIZACION/07_importar_datos_reales.sql` y luego `01_DATABASE/06_consultas_informe.sql` |
| 8. Respaldo | `05_BACKUPS`: `01` a `03` |

## Requisitos

- SQL Server Management Studio conectado como administrador.
- La base se creo en **SQL Server 2025 (version 17)**; el `.bak` solo se restaura en esa version o una mas nueva.
- Cambiar las rutas de ejemplo `C:\Public\` (backups) y `C:\DATOS\` (CSV) por carpetas del equipo donde corre SQL Server y a las que su servicio tenga acceso.

## Restaurar la base ya cargada

Ver `05_BACKUPS/README.md`: el archivo `.bak` trae la estructura y los datos.

## Mapa de tablas

| Tipo | Tabla | Para que sirve |
|---|---|---|
| Hechos | `Atencion_Diagnostico` | Numeros (atendidos, atenciones) y llaves a los catalogos |
| Catalogo | `Ubicacion`, `Genero`, `Rango_Edad`, `Diagnostico` | Cada valor una sola vez |
| Apoyo | `origen_atenciones_diagnostico` | Entrada del CSV, todo como texto |
| Apoyo | `tbl_cuarentena_atenciones` | Filas rechazadas con el motivo |
| Apoyo | `log_auditoria` | Quien hizo que y cuando |
| Apoyo | `etl_log` | Filas por paso del ETL y cuadre |
| Warehouse | `dw.Resumen_Tiempo_Diagnostico`, `dw.Resumen_Ubicacion`, `dw.Resumen_Perfil` | Resumenes para Power BI |
