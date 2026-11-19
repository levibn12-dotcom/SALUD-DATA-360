-- 04_AUDITORIA/01_trigger_auditoria.sql

USE BD_DataSalud_Atenciones;
GO

-- 2. TRIGGERS (2.1 auditoria: quien, que, valor anterior y nuevo)
CREATE OR ALTER TRIGGER dbo.trg_audit_atencion_diagnostico
ON dbo.Atencion_Diagnostico
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.log_auditoria (tabla, operacion, registro_id, valor_anterior, valor_nuevo)
    SELECT
        'Atencion_Diagnostico',
        -- si solo esta en "inserted" es INSERT; en las dos es UPDATE; si solo en "deleted" es DELETE
        CASE WHEN i.id_atencion_diagnostico IS NOT NULL AND d.id_atencion_diagnostico IS NULL THEN 'INSERT'
             WHEN i.id_atencion_diagnostico IS NOT NULL AND d.id_atencion_diagnostico IS NOT NULL THEN 'UPDATE'
             ELSE 'DELETE' END,
        COALESCE(i.id_atencion_diagnostico, d.id_atencion_diagnostico),
        CASE WHEN d.id_atencion_diagnostico IS NULL THEN NULL ELSE
            CONCAT('anio=', d.anio, '; mes=', d.nro_mes, '; atendidos=', d.atendidos,
                   '; atenciones=', d.atenciones) END,
        CASE WHEN i.id_atencion_diagnostico IS NULL THEN NULL ELSE
            CONCAT('anio=', i.anio, '; mes=', i.nro_mes, '; atendidos=', i.atendidos,
                   '; atenciones=', i.atenciones) END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_atencion_diagnostico = d.id_atencion_diagnostico;
END;
GO
