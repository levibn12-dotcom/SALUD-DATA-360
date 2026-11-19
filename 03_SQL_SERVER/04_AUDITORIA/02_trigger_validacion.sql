-- 04_AUDITORIA/02_trigger_validacion.sql

USE BD_DataSalud_Atenciones;
GO

-- 2.2 Validacion: bloquea mes fuera de 1-12 y numeros negativos
CREATE OR ALTER TRIGGER dbo.trg_validar_atencion_diagnostico
ON dbo.Atencion_Diagnostico
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted
               WHERE nro_mes NOT BETWEEN 1 AND 12
                  OR atendidos < 0
                  OR atenciones < 0)
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- cancela la operacion
        THROW 50001, 'Validacion: nro_mes debe estar entre 1 y 12 y atendidos/atenciones no pueden ser negativos. Operacion cancelada.', 1;
    END
END;
GO
