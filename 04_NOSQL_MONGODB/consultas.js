// Consultas MongoDB - base datasalud_mongo
// Ejecutar en mongosh (pestaña MONGOSH de Compass)
use datasalud_mongo

// --- Verificacion de la carga ---
db.mamis.countDocuments()          // esperado: 106
db.atendidos.countDocuments()      // esperado: 52611
db.mamis.aggregate([{$group:{_id:null, atendidos:{$sum:"$Atendidos"}, atenciones:{$sum:"$Atenciones"}}}])      // 19 / 203
db.atendidos.aggregate([{$group:{_id:null, atendidos:{$sum:"$Atendidos"}, atenciones:{$sum:"$Atenciones"}}}])  // 81796 / 155303

// A) Casos de Mamis en Cusco
db.mamis.find({Departamento:"CUSCO"}, {_id:0, Provincia:1, Distrito:1, Sexo:1, Etapa:1, Diagnostico:1, Atenciones:1}).sort({Atenciones:-1}).limit(10)

// B) Atenciones por diagnostico
db.atendidos.aggregate([
  {$group:{_id:"$Diagnostico", atenciones:{$sum:"$Atenciones"}}},
  {$sort:{atenciones:-1}}
])

// C) Top 10 departamentos con mas atenciones
db.atendidos.aggregate([
  {$group:{_id:"$Departamento", atenciones:{$sum:"$Atenciones"}}},
  {$sort:{atenciones:-1}}, {$limit:10}
])

// D) Evolucion mensual
db.atendidos.aggregate([
  {$group:{_id:"$NroMes", atendidos:{$sum:"$Atendidos"}, atenciones:{$sum:"$Atenciones"}}},
  {$sort:{_id:1}}
])

// E) Por sexo y etapa de vida (Mamis)
db.mamis.aggregate([
  {$group:{_id:{sexo:"$Sexo", etapa:"$Etapa"}, atenciones:{$sum:"$Atenciones"}}},
  {$sort:{atenciones:-1}}
])

// F) Atenciones por persona atendida, por diagnostico
db.atendidos.aggregate([
  {$group:{_id:"$Diagnostico", at:{$sum:"$Atendidos"}, ac:{$sum:"$Atenciones"}}},
  {$project:{atenciones_por_persona:{$round:[{$divide:["$ac","$at"]},2]}}},
  {$sort:{atenciones_por_persona:-1}}
])

// G) Indice y plan de ejecucion
db.atendidos.createIndex({Departamento:1, Diagnostico:1})
db.atendidos.find({Departamento:"LIMA", Diagnostico:"ANSIEDAD"}).explain("executionStats")
