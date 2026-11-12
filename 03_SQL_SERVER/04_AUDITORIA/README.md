# 04 - Auditoria (log y triggers)

Trazabilidad: tabla `log_auditoria` y triggers DML (auditoria de INSERT/UPDATE/DELETE e integridad). Los procedimientos de ingesta tambien escriben en este log.

## 1. Tabla de log de auditoria

```sql
-- Tabla de log de auditoria (la exige la rubrica). La escriben triggers y procedimientos.
IF OBJECT_ID('dbo.log_auditoria','U') IS NULL
CREATE TABLE dbo.log_auditoria (
    id_log INT IDENTITY(1,1) PRIMARY KEY,
    tabla VARCHAR(100) NOT NULL,
    operacion VARCHAR(20) NOT NULL,      -- INSERT, UPDATE, DELETE, INGESTA, ERROR
    registro_id INT NULL,
    usuario VARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    fecha_hora DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    valor_anterior VARCHAR(MAX) NULL,
    valor_nuevo VARCHAR(MAX) NULL,
    lote_id VARCHAR(50) NULL,
    detalle VARCHAR(1000) NULL
);
GO
```

## 2. Triggers

```sql
/* ---------------------------------------------------------------------
   2. TRIGGERS
   2.1 Auditoria DML: registra quien, cuando y los valores antes/despues.
       Si falla el log, falla la operacion (no se pierde trazabilidad).
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_audit_atenciones
ON dbo.tbl_atenciones_salud_mental
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.log_auditoria (tabla, operacion, registro_id, valor_anterior, valor_nuevo)
    SELECT
        'tbl_atenciones_salud_mental',
        CASE WHEN i.id_atencion IS NOT NULL AND d.id_atencion IS NULL THEN 'INSERT'
             WHEN i.id_atencion IS NOT NULL AND d.id_atencion IS NOT NULL THEN 'UPDATE'
             ELSE 'DELETE' END,
        COALESCE(i.id_atencion, d.id_atencion),
        CASE WHEN d.id_atencion IS NULL THEN NULL ELSE
            CONCAT('est=', d.co_establecimiento, '; fecha=', d.fecha_atencion, '; edad=', d.edad,
                   '; sexo=', d.sexo, '; diag=', d.diagnostico) END,
        CASE WHEN i.id_atencion IS NULL THEN NULL ELSE
            CONCAT('est=', i.co_establecimiento, '; fecha=', i.fecha_atencion, '; edad=', i.edad,
                   '; sexo=', i.sexo, '; diag=', i.diagnostico) END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_atencion = d.id_atencion;
END;
GO

-- 2.2 Integridad: rechaza edades fuera de rango, fechas futuras y diagnostico vacio
CREATE OR ALTER TRIGGER dbo.trg_integridad_atenciones
ON dbo.tbl_atenciones_salud_mental
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted
               WHERE edad < 0 OR edad > 120
                  OR fecha_atencion > CAST(GETDATE() AS DATE)
                  OR LTRIM(RTRIM(diagnostico)) = '')
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 50001, 'Integridad: edad fuera de 0-120, fecha futura o diagnostico vacio. Operacion revertida.', 1;
    END
END;
GO
```

## 3. Pruebas de triggers (evidencia)

```sql
-- 8.3 Trigger de auditoria: un UPDATE genera registro con valor anterior y nuevo
UPDATE dbo.tbl_atenciones_salud_mental SET diagnostico = 'F32.1 Depresion moderada' WHERE co_establecimiento = '0001';
SELECT TOP 10 * FROM dbo.log_auditoria ORDER BY id_log DESC;
GO

-- 8.4 Trigger de integridad: debe rechazar y revertir (edad 200)
BEGIN TRY
    INSERT INTO dbo.tbl_atenciones_salud_mental (co_establecimiento, fecha_atencion, edad, sexo, diagnostico)
    VALUES ('0009', '2024-01-01', 200, 'M', 'F41');
    PRINT 'FALLO: el trigger no rechazo la fila.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK, rechazado por el trigger: ', ERROR_MESSAGE());
END CATCH;
GO
```

