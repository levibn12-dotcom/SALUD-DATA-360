-- 02_AUTOMATIZACION/05_reiniciar_datos.sql

USE BD_DataSalud_Atenciones;
GO

-- 5.3 usp_reiniciar_datos: borra los datos de prueba (exige @confirmar = 'SI'). Usar solo antes de la primera carga real.
CREATE OR ALTER PROCEDURE dbo.usp_reiniciar_datos
    @confirmar   VARCHAR(2) = 'NO',
    @borrar_logs BIT        = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @confirmar <> 'SI'
        THROW 50040, 'Reinicio cancelado: este procedimiento BORRA datos. Para continuar usa @confirmar = ''SI''.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;

        DELETE FROM dw.Resumen_Perfil;
        DELETE FROM dw.Resumen_Ubicacion;
        DELETE FROM dw.Resumen_Tiempo_Diagnostico;
        DELETE FROM dbo.Atencion_Diagnostico;      -- primero los hechos (tienen las llaves foraneas)
        DELETE FROM dbo.Ubicacion;                 -- luego los catalogos
        DELETE FROM dbo.Genero;
        DELETE FROM dbo.Rango_Edad;
        DELETE FROM dbo.Diagnostico;
        DELETE FROM dbo.tbl_cuarentena_atenciones;
        DELETE FROM dbo.origen_atenciones_diagnostico;
        IF @borrar_logs = 1
        BEGIN
            DELETE FROM dbo.etl_log;
            DELETE FROM dbo.log_auditoria;
        END;   -- el punto y coma es obligatorio: ENABLE TRIGGER exige que la instruccion anterior este cerrada

        ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
        COMMIT TRANSACTION;

        INSERT INTO dbo.log_auditoria (tabla, operacion, detalle)
        VALUES ('(todas)', 'REINICIO', CONCAT('datos borrados; logs borrados=', @borrar_logs));
        PRINT 'Datos reiniciados. La estructura sigue intacta.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- tambien deja el trigger como estaba
        THROW;
    END CATCH
END;
GO
