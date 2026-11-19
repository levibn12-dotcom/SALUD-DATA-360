# 05 · Data Warehouse y ETL

Proceso que limpia los datos cargados desde los CSV del Minsa (salud mental, 2017) y los resume en un data warehouse para Power BI.

**Motor:** SQL Server · **Base:** `BD_DataSalud_Atenciones`

## Archivos

| Archivo | Qué hace |
|---|---|
| `01_etl_y_warehouse_crear.sql` | Crea el procedimiento `usp_etl_atenciones`, el esquema `dw` con sus 3 tablas y el procedimiento `usp_cargar_warehouse`. Se ejecuta una sola vez. |
| `02_ejecutar_warehouse.sql` | Llena el warehouse y muestra los conteos. Se ejecuta después de cargar todos los CSV. |

## Flujo

```
CSV (Mamis_Minsa, Atendidos_Minsa)
   │  usp_cargar_csv   (separador ';')
   ▼
origen_atenciones_diagnostico      ← tabla de paso ("sala de espera")
   │  usp_etl_atenciones @lote_id
   ▼
Atencion_Diagnostico + catálogos   ← modelo limpio (Ubicacion, Genero, Rango_Edad, Diagnostico)
   │  filas inválidas → tbl_cuarentena_atenciones
   │  pasos y cuadre   → etl_log
   ▼
usp_cargar_warehouse
   ▼
dw.Resumen_Tiempo_Diagnostico · dw.Resumen_Ubicacion · dw.Resumen_Perfil   → Power BI
```

## ETL (`usp_etl_atenciones`)

Se ejecuta un archivo a la vez, con un lote propio (`LOTE_REAL_01`, `LOTE_REAL_02`, ...). Pasos:

1. Limpieza de textos y validación de campos.
2. Carga de catálogos (ubicación, sexo, etapa de vida, diagnóstico).
3. Inserción en `Atencion_Diagnostico` con el `lote_id`.
4. Filas rechazadas a `tbl_cuarentena_atenciones` con su motivo.
5. Cuadre: leídas = cargadas + rechazadas, registrado en `etl_log` (paso `5_CUADRE`, estado `OK`).

## Warehouse (esquema `dw`)

| Tabla | Granularidad | Uso |
|---|---|---|
| `dw.Resumen_Tiempo_Diagnostico` | año, mes, diagnóstico | Evolución en el tiempo |
| `dw.Resumen_Ubicacion` | año, departamento, provincia, diagnóstico | Mapas y rankings |
| `dw.Resumen_Perfil` | año, sexo, etapa, diagnóstico | Perfil de las personas atendidas |

Cada tabla trae `total_atendidos`, `total_atenciones` y `promedio_atenciones`. Hay que volver a ejecutar `usp_cargar_warehouse` cada vez que se cargue un archivo nuevo.

## Cómo ejecutarlo

1. Tener creada la estructura de la base (carpeta `03_SQL_SERVER`).
2. Ejecutar `01_etl_y_warehouse_crear.sql`.
3. Por cada CSV: vaciar el origen (`EXEC dbo.usp_limpiar_origen;`), cargarlo (`EXEC dbo.usp_cargar_csv @ruta = N'...', @separador = ';';`) y correr `EXEC dbo.usp_etl_atenciones @lote_id = 'LOTE_REAL_0X';`.
4. Ejecutar `02_ejecutar_warehouse.sql`.

## Resultado verificado

- Carga de los dos archivos con cuadre `OK` en `etl_log`.
- Warehouse poblado: 113 filas de tiempo/diagnóstico, 988 de ubicación y 230 de perfil.
- Respaldo `.bak` y restore de prueba con conteos iguales (ver `08_TESTING_EVIDENCIAS`).

## Notas

- Los atendidos son un acumulado: una misma persona puede contarse más de una vez entre meses, etapas o diagnósticos.
- Los datos cubren de enero a septiembre de 2017.
