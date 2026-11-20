# 06 · Power BI

Informe de las atenciones de salud mental del Minsa (2017), conectado a la base `BD_DataSalud_Atenciones` en SQL Server. Se trabajó con dos enfoques sobre los mismos datos: el **data warehouse** (tablas resumen) y el **modelo en estrella** (tabla de hechos y dimensiones).

## Archivos

| Archivo | Descripción |
|---|---|
| `Evidencias_PowerBI.pdf` | Capturas de la carga de tablas, el modelo en estrella, el orden de los datos y los gráficos del warehouse. |
| `DataSalud_Atenciones.pbix` | Informe de Power BI Desktop. |
| `medidas_dax.txt` | Medidas DAX de ambos enfoques, para leerlas sin abrir el `.pbix`. |

## Origen de los datos

- **Conexión:** Power BI Desktop > Obtener datos > SQL Server.
- **Servidor:** `localhost` · **Base de datos:** `BD_DataSalud_Atenciones`.
- **Modo:** Importar.
- **Datos:** dos archivos del Minsa (Mamis y Atendidos) cargados en SQL Server con el ETL descrito en `05_DATA_WAREHOUSE_ETL`. Cubren enero a septiembre de 2017.

## Enfoque 1: data warehouse

Se cargan las 3 tablas resumen del esquema `dw`:

| Tabla | Granularidad | Uso en el informe |
|---|---|---|
| `dw.Resumen_Tiempo_Diagnostico` | año, mes, diagnóstico | Evolución mensual y comparación por diagnóstico |
| `dw.Resumen_Ubicacion` | año, departamento, provincia, diagnóstico | Ranking por departamento |
| `dw.Resumen_Perfil` | año, sexo, etapa, diagnóstico | Perfil por sexo y etapa de vida |

Las tres tablas **no se relacionan entre sí**. Power BI las conectó por la columna `id_resumen`, pero ese número no significa lo mismo en cada tabla, así que las relaciones se eliminaron. Cada visual usa una sola tabla.

Como las tablas ya vienen sumadas, el informe carga rápido y no necesita las filas de detalle.

### Medidas DAX (warehouse)

```
-- dw Resumen_Perfil
Atendidos Perfil = SUM('dw Resumen_Perfil'[total_atendidos])
Atenciones Perfil = SUM('dw Resumen_Perfil'[total_atenciones])
Atenciones por persona Perfil = DIVIDE([Atenciones Perfil], [Atendidos Perfil])
% Atenciones Perfil = DIVIDE([Atenciones Perfil], CALCULATE([Atenciones Perfil], ALLSELECTED('dw Resumen_Perfil')))

-- dw Resumen_Tiempo_Diagnostico
Atendidos Tiempo = SUM('dw Resumen_Tiempo_Diagnostico'[total_atendidos])
Atenciones Tiempo = SUM('dw Resumen_Tiempo_Diagnostico'[total_atenciones])
Atenciones por persona Tiempo = DIVIDE([Atenciones Tiempo], [Atendidos Tiempo])

-- dw Resumen_Ubicacion
Atendidos Ubicación = SUM('dw Resumen_Ubicacion'[total_atendidos])
Atenciones Ubicación = SUM('dw Resumen_Ubicacion'[total_atenciones])
Atenciones por persona Ubicación = DIVIDE([Atenciones Ubicación], [Atendidos Ubicación])
```

La columna `promedio_atenciones` de cada tabla no se usa en los gráficos: es un promedio ya calculado por fila, y sumarlo o promediarlo en Power BI daría un resultado incorrecto. Se calcula con medidas.

### Visuales del warehouse

| Visual | Campos | Medida |
|---|---|---|
| Tarjetas: atenciones, atendidos y atenciones por persona | – | `Atenciones Tiempo`, `Atendidos Tiempo`, `Atenciones por persona Tiempo` |
| Barras: top 10 departamentos | `departamento` | `Atenciones Ubicación` |
| Barras: atenciones por diagnóstico | `diagnostico` | `Atenciones Tiempo` |
| Columnas: etapa de vida por sexo | `etapa`, leyenda `sexo` | `Atenciones Perfil` |
| Circular: distribución por sexo | `sexo` | `Atenciones Perfil` |

## Enfoque 2: modelo en estrella

Se cargan las 5 tablas principales del modelo relacional:

| Tabla | Rol |
|---|---|
| `Atencion_Diagnostico` | Tabla de hechos: `atendidos`, `atenciones`, año, mes y claves a las dimensiones |
| `Ubicacion` | Dimensión: departamento, provincia, distrito y ubigeo |
| `Genero` | Dimensión: sexo |
| `Rango_Edad` | Dimensión: etapa de vida |
| `Diagnostico` | Dimensión: diagnóstico |

```
        Ubicacion        Genero
              \            /
               \          /
          Atencion_Diagnostico
               /          \
              /            \
       Diagnostico       Rango_Edad
```

Cada dimensión se relaciona con la tabla de hechos con cardinalidad **uno a varios**, a través de `id_ubicacion`, `id_genero`, `id_rango_edad` e `id_diagnostico`. Gracias a eso, un filtro sobre cualquier dimensión se aplica a toda la tabla de hechos.

### Medidas DAX (estrella)

```
Total Atenciones = SUM(Atencion_Diagnostico[atenciones])
Total Atendidos = SUM(Atencion_Diagnostico[atendidos])
Atenciones por Persona = DIVIDE([Total Atenciones], [Total Atendidos])
```

### Visuales del modelo en estrella

| Visual | Campos | Medida |
|---|---|---|
| Barras: atenciones por diagnóstico | `Diagnostico[diagnostico]` | `Total Atenciones` |
| Barras: top 10 departamentos | `Ubicacion[departamento]`, filtro N superior 10 | `Total Atenciones` |
| Segmentador | `Genero[sexo]` | Filtra los dos gráficos |

## Resultados de referencia

- Sin filtros: unas **155 506 atenciones** y **81 815 atendidos** (acumulado) entre los dos archivos.
- **Lima** es el departamento con más atenciones (24 452 en el archivo de atendidos), seguido de Callao y Junín.
- **Violencia familiar / maltrato infantil** es el diagnóstico con más atenciones, seguido de ansiedad y trastorno depresivo.

## Notas

- Los atendidos son un acumulado: sumarlos entre meses, etapas o diagnósticos puede contar dos veces a la misma persona. No equivalen a personas únicas.
- Los datos cubren solo 2017 (hasta septiembre), así que no se incluyó un segmentador de año.
- Los dos enfoques deben dar el mismo total de atenciones. Esa coincidencia sirve para comprobar que el warehouse se cargó con todos los lotes.
