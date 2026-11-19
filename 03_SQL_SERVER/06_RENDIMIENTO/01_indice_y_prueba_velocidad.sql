-- 06_RENDIMIENTO/01_indice_y_prueba_velocidad.sql

USE BD_DataSalud_Atenciones;
GO

-- 7. INDICE Y PRUEBA DE VELOCIDAD (crea ~72 mil filas de prueba en provincia 'PRUEBA' y las borra al final;
--    CHECKPOINT y DBCC DROPCLEANBUFFERS requieren ser sysadmin)
-- 7.0 Datos de volumen temporales
DROP INDEX IF EXISTS IX_Atencion_Anio_Diagnostico ON dbo.Atencion_Diagnostico;
GO
-- Catalogos reales (solo si aun no existen)
INSERT INTO dbo.Genero (sexo)
SELECT v.x FROM (VALUES ('F'),('M')) v(x) WHERE NOT EXISTS (SELECT 1 FROM dbo.Genero WHERE sexo = v.x);
INSERT INTO dbo.Rango_Edad (etapa)
SELECT v.x FROM (VALUES ('1 - 4'),('5 - 9'),('10 - 11'),('12 - 14'),('15 - 17')) v(x)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Rango_Edad WHERE etapa = v.x);
INSERT INTO dbo.Diagnostico (diagnostico)
SELECT v.x FROM (VALUES ('ABUSO PSICOLOGICO'),('ABUSO FISICO'),('ABUSO SEXUAL'),('NEGLIGENCIA')) v(x)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Diagnostico WHERE diagnostico = v.x);

-- 50 ubicaciones de prueba
INSERT INTO dbo.Ubicacion (ubigeo, departamento, provincia, distrito)
SELECT CONCAT('9', RIGHT(CONCAT('00000', n), 5)), 'PRUEBA', 'PRUEBA', CONCAT('PRUEBA ', n)
FROM (SELECT TOP 50 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) t;

-- Se apaga el trigger de auditoria solo durante esta carga masiva
DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;

INSERT INTO dbo.Atencion_Diagnostico
       (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes, atendidos, atenciones, lote_id)
SELECT u.id_ubicacion, g.id_genero, e.id_rango_edad, d.id_diagnostico, a.anio, m.mes,
       (u.id_ubicacion + m.mes) % 5, (u.id_ubicacion + m.mes) % 5 + 1, 'LOTE_VOLUMEN'
FROM dbo.Ubicacion u
CROSS JOIN dbo.Genero g
CROSS JOIN dbo.Rango_Edad e
CROSS JOIN dbo.Diagnostico d
CROSS JOIN (VALUES (2017),(2018),(2019)) a(anio)
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) m(mes)
WHERE u.provincia = 'PRUEBA';

ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
GO

-- 7.1 Medicion ANTES y DESPUES del indice
-- (activa tambien el plan de ejecucion real con Ctrl+M y guarda ambos planes)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @anio SMALLINT = 2018;
DECLARE @diag VARCHAR(100) = 'ABUSO PSICOLOGICO';

PRINT '=== ANTES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT d.diagnostico, SUM(f.atendidos) AS total_atendidos, SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
WHERE f.anio = @anio AND d.diagnostico = @diag
GROUP BY d.diagnostico;

CREATE NONCLUSTERED INDEX IX_Atencion_Anio_Diagnostico
ON dbo.Atencion_Diagnostico (anio, id_diagnostico) INCLUDE (atendidos, atenciones);

PRINT '=== DESPUES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT d.diagnostico, SUM(f.atendidos) AS total_atendidos, SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
WHERE f.anio = @anio AND d.diagnostico = @diag
GROUP BY d.diagnostico;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
-- Copia de la pestana Messages: "logical reads" y "CPU time / elapsed time", antes vs despues.

-- 7.2 Limpieza: se borran los datos de prueba (el indice se queda)
DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
DELETE f FROM dbo.Atencion_Diagnostico f
JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
WHERE u.provincia = 'PRUEBA';
ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
DELETE FROM dbo.Ubicacion WHERE provincia = 'PRUEBA';
GO
