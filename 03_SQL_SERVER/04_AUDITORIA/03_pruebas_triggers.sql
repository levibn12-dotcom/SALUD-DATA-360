-- 04_AUDITORIA/03_pruebas_triggers.sql

USE BD_DataSalud_Atenciones;
GO

-- 8.3 Trigger de auditoria: un UPDATE deja registro con valor anterior y nuevo
UPDATE dbo.Atencion_Diagnostico
SET atenciones = 3
WHERE id_atencion_diagnostico = (SELECT MIN(id_atencion_diagnostico) FROM dbo.Atencion_Diagnostico);
SELECT TOP 10 * FROM dbo.log_auditoria ORDER BY id_log DESC;
GO

-- 8.4 Trigger de validacion: debe bloquear mes 15 y atendidos -5
DECLARE @u INT = (SELECT TOP 1 id_ubicacion FROM dbo.Ubicacion ORDER BY id_ubicacion);
DECLARE @g INT = (SELECT TOP 1 id_genero FROM dbo.Genero ORDER BY id_genero);
DECLARE @e INT = (SELECT TOP 1 id_rango_edad FROM dbo.Rango_Edad ORDER BY id_rango_edad);
DECLARE @d INT = (SELECT TOP 1 id_diagnostico FROM dbo.Diagnostico ORDER BY id_diagnostico);

BEGIN TRY
    INSERT INTO dbo.Atencion_Diagnostico (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes, atendidos, atenciones)
    VALUES (@u, @g, @e, @d, 2030, 15, 1, 1);
    PRINT 'FALLO: el trigger no bloqueo el mes 15.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK, bloqueado (mes 15): ', ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    INSERT INTO dbo.Atencion_Diagnostico (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes, atendidos, atenciones)
    VALUES (@u, @g, @e, @d, 2030, 1, -5, 1);
    PRINT 'FALLO: el trigger no bloqueo atendidos negativo.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK, bloqueado (atendidos -5): ', ERROR_MESSAGE());
END CATCH;
GO
