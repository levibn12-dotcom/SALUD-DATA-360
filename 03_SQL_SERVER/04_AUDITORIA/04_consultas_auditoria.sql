-- 04_AUDITORIA/04_consultas_auditoria.sql

USE BD_DataSalud_Atenciones;
GO

-- Consultas para revisar la auditoria, el ETL y la cuarentena
SELECT TOP 20 * FROM dbo.log_auditoria ORDER BY id_log DESC;

-- Cuantas operaciones de cada tipo hay y quien las hizo
SELECT usuario, operacion, COUNT(*) AS veces
FROM dbo.log_auditoria
GROUP BY usuario, operacion
ORDER BY veces DESC;

-- Resultado de cada paso del ETL (lectura, cuarentena, catalogos, hechos, cuadre, warehouse)
SELECT TOP 20 * FROM dbo.etl_log ORDER BY id_etl DESC;

-- Filas rechazadas por motivo
SELECT motivo_error, COUNT(*) AS filas
FROM dbo.tbl_cuarentena_atenciones
GROUP BY motivo_error
ORDER BY filas DESC;

-- Filas y totales cargados por lote
SELECT lote_id, COUNT(*) AS filas, SUM(atendidos) AS atendidos, SUM(atenciones) AS atenciones
FROM dbo.Atencion_Diagnostico
GROUP BY lote_id
ORDER BY lote_id;
GO
