# 04_AUDITORIA - Triggers y registros

Dos triggers sobre `Atencion_Diagnostico`: uno **registra** quien cambio que (valor anterior y nuevo) y otro **bloquea** datos invalidos. Las tablas `log_auditoria` y `etl_log` se crean en `01_DATABASE`.

## Archivos

| Archivo | Que hace |
|---|---|
| `01_trigger_auditoria.sql` | `trg_audit_atencion_diagnostico`: despues de cada `INSERT`, `UPDATE` o `DELETE` guarda en `log_auditoria` el usuario, la operacion y los valores anterior y nuevo. |
| `02_trigger_validacion.sql` | `trg_validar_atencion_diagnostico`: cancela la operacion si `nro_mes` no esta entre 1 y 12 o si `atendidos`/`atenciones` son negativos. |
| `03_pruebas_triggers.sql` | Un `UPDATE` que debe dejar registro en el log, y dos `INSERT` (mes 15 y atendidos -5) que deben ser bloqueados. Ejecutar despues de `02_AUTOMATIZACION/06_pruebas_carga.sql` (necesita datos). |
| `04_consultas_auditoria.sql` | Consultas para revisar la auditoria, el log del ETL, la cuarentena y las cargas por lote. |

## Codigo

### `01_trigger_auditoria.sql`

`trg_audit_atencion_diagnostico`: despues de cada `INSERT`, `UPDATE` o `DELETE` guarda en `log_auditoria` el usuario, la operacion y los valores anterior y nuevo.

```sql
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
```

### `02_trigger_validacion.sql`

`trg_validar_atencion_diagnostico`: cancela la operacion si `nro_mes` no esta entre 1 y 12 o si `atendidos`/`atenciones` son negativos.

```sql
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
```

### `03_pruebas_triggers.sql`

Un `UPDATE` que debe dejar registro en el log, y dos `INSERT` (mes 15 y atendidos -5) que deben ser bloqueados. Ejecutar despues de `02_AUTOMATIZACION/06_pruebas_carga.sql` (necesita datos).

```sql
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
```

### `04_consultas_auditoria.sql`

Consultas para revisar la auditoria, el log del ETL, la cuarentena y las cargas por lote.

```sql
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
```
