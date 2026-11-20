# 04 · NoSQL con MongoDB

Carga de los datos de salud mental del Minsa (2017) en MongoDB y consultas de agregación para explorarlos.

**Motor:** MongoDB Community + MongoDB Compass · **Base:** `datasalud_mongo`

## Archivos

| Archivo | Descripción |
|---|---|
| `mamis_minsa_mongo.csv` | Atenciones del grupo Mamis. 106 registros, meses 1 a 8 de 2017. |
| `atendidos_minsa_mongo.csv` | Atenciones de salud mental. 52 611 registros, meses 1 a 9 de 2017. |
| `consultas.js` | Consultas de verificación y análisis, listas para pegar en mongosh. |
| `Evidencias_Mongo.pdf` | Capturas de la importación y de cada consulta. |

Los CSV están en UTF-8 sin BOM, separados por coma. Los diagnósticos que contienen una coma van entre comillas.

## Estructura de los datos

Cada fila del CSV es un documento. Campos:

| Campo | Tipo | Ejemplo |
|---|---|---|
| `Anio` | Int32 | 2017 |
| `NroMes` | Int32 | 1 |
| `ubigeo` | String | "20101" |
| `Departamento`, `Provincia`, `Distrito` | String | "ANCASH", "HUARAZ", "HUARAZ" |
| `Sexo` | String | "F" |
| `Etapa` | String | "15 - 17" |
| `Diagnostico` | String | "TRASTORNO DEPRESIVO" |
| `Atendidos` | Int32 | 2 |
| `Atenciones` | Int32 | 2 |

`ubigeo` se guarda como texto para no perder ceros ni tratarlo como número.

## Por qué MongoDB

- Cada registro se guarda como un documento, sin necesidad de definir tablas y claves antes de cargar.
- Los datos llegan como archivos planos y se importan directamente, sin pasar por un ETL.
- Las consultas de agregación (`$group`, `$sort`, `$project`) resumen los datos de forma parecida a las vistas del modelo en SQL Server.
- Permite comparar un enfoque documental con el modelo relacional y el warehouse del proyecto.

## Cómo reproducirlo

1. Abrir MongoDB Compass y conectarse a `mongodb://localhost:27017`.
2. Crear la base `datasalud_mongo` con la colección `mamis`.
3. En la colección, **Add Data > Import JSON or CSV file** y elegir `mamis_minsa_mongo.csv`.
4. En la vista previa, delimitador **coma** y tipos de campo: `Anio`, `NroMes`, `Atendidos` y `Atenciones` como Int32; `ubigeo` y el resto como String.
5. Crear la colección `atendidos` en la misma base y repetir con `atendidos_minsa_mongo.csv`.
6. Abrir la pestaña **MONGOSH** y ejecutar las consultas de `consultas.js`.

## Verificación de la carga

| Colección | Documentos | Suma de atendidos | Suma de atenciones |
|---|---|---|---|
| `mamis` | 106 | 19 | 203 |
| `atendidos` | 52 611 | 81 796 | 155 303 |

Estos valores coinciden con los archivos de origen y con los datos cargados en SQL Server (155 506 atenciones entre ambos archivos).

## Consultas

| Id | Qué responde | Tipo |
|---|---|---|
| A | Casos de Mamis en Cusco, ordenados por atenciones | `find` con filtro, proyección y orden |
| B | Atenciones por diagnóstico | `aggregate` con `$group` y `$sort` |
| C | Top 10 departamentos con más atenciones | `aggregate` con `$group`, `$sort` y `$limit` |
| D | Evolución mensual de atendidos y atenciones | `aggregate` con `$group` por mes |
| E | Atenciones por sexo y etapa de vida (Mamis) | `aggregate` con clave compuesta |
| F | Atenciones por persona atendida, por diagnóstico | `aggregate` con `$project` y `$divide` |
| G | Índice compuesto y plan de ejecución | `createIndex` y `explain("executionStats")` |

El código completo está en `consultas.js`, y las capturas de cada resultado en `Evidencias_Mongo.pdf`.

## Resultados destacados

- El diagnóstico con más atenciones en `atendidos` es **violencia familiar / maltrato infantil** (59 297), seguido de **ansiedad** (39 807) y **trastorno depresivo** (35 430).
- El departamento con más atenciones es **Lima** (24 452), seguido de **Callao** (18 645) y **Junín** (17 918).
- En `mamis`, el departamento con más atenciones es **Cusco** (143) y el diagnóstico con más atenciones es **negligencia** (98).

## Notas

- Los datos cubren solo 2017: hasta septiembre en `atendidos` y hasta agosto en `mamis`.
- `Atendidos` es un acumulado por fila. Sumarlo entre meses, etapas o diagnósticos puede contar dos veces a la misma persona, así que no equivale a personas únicas.
- Las consultas que usan `Atenciones` y `Atendidos` se calculan sobre los mismos datos que usa el informe de Power BI (carpeta `06_POWER_BI`).
