-- 03_SEGURIDAD/02_pruebas_roles.sql

USE BD_DataSalud_Atenciones;
GO

-- 8.7 Roles: cada prueba debe mostrar "OK bloqueado" donde corresponde
EXECUTE AS USER = 'u_analista_test';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.origen_atenciones_diagnostico;
    PRINT 'FALLO: el analista pudo leer la tabla de origen.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> origen): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.log_auditoria;
    PRINT 'FALLO: el analista pudo leer el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> log_auditoria): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.vw_evolucion_mensual;   -- esto SI debe funcionar
SELECT TOP 5 * FROM dw.Resumen_Ubicacion;       -- esto SI debe funcionar
REVERT;

EXECUTE AS USER = 'u_auditor_test';
BEGIN TRY
    DELETE FROM dbo.log_auditoria;
    PRINT 'FALLO: el auditor pudo borrar el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> borrar log): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.Atencion_Diagnostico;
    PRINT 'FALLO: el auditor pudo leer la tabla de hechos.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> tabla de hechos): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.log_auditoria ORDER BY id_log DESC;   -- esto SI debe funcionar
REVERT;
GO
