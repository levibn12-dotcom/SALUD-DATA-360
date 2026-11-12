# 04 - NoSQL (MongoDB)

Modelo documental de los **tamizajes de salud mental** (fuente: `DAT SALUD UTF8.csv`, MINSA/DIRESA).
Se pasa de una tabla plana de 11 columnas a **un documento por distrito y mes**, con los tamizajes anidados.

## Archivos de esta carpeta

| Archivo | Contenido |
|---|---|
| `tamizajes_la_libertad_2017.json` | Solo La Libertad: 157 documentos (3 287 filas del CSV). Arreglo JSON, se ve bien en GitHub |
| `tamizajes_peru_2017.jsonl.gz` | Todo el pais: 6 753 documentos (236 527 filas). Un documento por linea, comprimido |

## Por que documentos y no tablas

- Cada documento agrupa todo lo ocurrido en un distrito en un mes: una sola lectura trae el cuadro completo.
- `sexo`, `etapa`, `grupo` y `detalle` viajan juntos dentro de `tamizajes`, sin joins.
- Se agregan `total_tamizajes` y `total_positivos` ya calculados. Se separan a proposito: los positivos son un
  subconjunto de los tamizajes totales, por lo que **no deben sumarse entre si**.

## Estructura de un documento

```json
{
  "_id": "2017-01-130108",
  "anio": 2017,
  "nro_mes": 1,
  "ubicacion": { "ubigeo": "130108", "departamento": "LA LIBERTAD", "provincia": "TRUJILLO", "distrito": "POROTO" },
  "total_tamizajes": 120,
  "total_positivos": 0,
  "tamizajes": [
    { "sexo": "F", "etapa": "10 - 11", "grupo": "TOTAL DE TAMIZAJES",
      "detalle": "VIOLENCIA FAMILIAR/MALTRATO INFANTIL", "casos": 2 }
  ]
}
```

## Notas de calidad de datos

- El CSV cubre **solo 2017, de enero a septiembre** (septiembre casi vacio: 871 filas).
- Viene el **pais completo** (23 departamentos). Para el proyecto de La Libertad se genero el archivo filtrado.
- El ubigeo `120135` (Santo Domingo de Acobamba) aparecia con dos provincias, HUANCAYO y CONCEPCION. Se unifico a
  HUANCAYO en 52 filas. Sin esa correccion, esas filas se consideran duplicados por clave.
- Verificacion: la suma de `casos` y el numero de tamizajes anidados coinciden exactamente con el CSV original.

## Importar en MongoDB

```bash
# La Libertad (arreglo JSON)
mongoimport --db bd_datasalud --collection tamizajes_salud_mental \
  --file tamizajes_la_libertad_2017.json --jsonArray

# Pais completo (descomprimir primero)
gunzip -k tamizajes_peru_2017.jsonl.gz
mongoimport --db bd_datasalud --collection tamizajes_peru \
  --file tamizajes_peru_2017.jsonl
```

Si usas MongoDB Compass: *Add Data > Import JSON* y elige el archivo.

## Indices recomendados

```javascript
use bd_datasalud
db.tamizajes_salud_mental.createIndex({ "ubicacion.provincia": 1, "anio": 1, "nro_mes": 1 })
db.tamizajes_salud_mental.createIndex({ "ubicacion.ubigeo": 1 })
```

## Consultas de ejemplo

```javascript
// 1. Tamizajes totales por provincia
db.tamizajes_salud_mental.aggregate([
  { $group: { _id: "$ubicacion.provincia", total: { $sum: "$total_tamizajes" } } },
  { $sort: { total: -1 } }
])

// 2. Tendencia mensual
db.tamizajes_salud_mental.aggregate([
  { $group: { _id: "$nro_mes", total: { $sum: "$total_tamizajes" }, positivos: { $sum: "$total_positivos" } } },
  { $sort: { _id: 1 } }
])

// 3. Casos por tipo de tamizaje (solo tamizajes totales)
db.tamizajes_salud_mental.aggregate([
  { $unwind: "$tamizajes" },
  { $match: { "tamizajes.grupo": "TOTAL DE TAMIZAJES" } },
  { $group: { _id: "$tamizajes.detalle", casos: { $sum: "$tamizajes.casos" } } },
  { $sort: { casos: -1 } }
])

// 4. Depresion en mujeres adultas (40-59) por distrito
db.tamizajes_salud_mental.aggregate([
  { $unwind: "$tamizajes" },
  { $match: { "tamizajes.detalle": "TRASTORNO DEPRESIVO", "tamizajes.sexo": "F",
              "tamizajes.etapa": "40 - 59", "tamizajes.grupo": "TOTAL DE TAMIZAJES" } },
  { $group: { _id: "$ubicacion.distrito", casos: { $sum: "$tamizajes.casos" } } },
  { $sort: { casos: -1 } }
])
```
