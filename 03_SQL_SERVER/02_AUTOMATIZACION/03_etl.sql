-- 02_AUTOMATIZACION/03_etl.sql

USE BD_DataSalud_Atenciones;
GO

-- 5. ETL Y WAREHOUSE
-- 5.1 usp_etl_atenciones: ejecuta la carga paso a paso y deja huella en etl_log.
--     La tabla de origen debe tener solo el lote a cargar. Cuadre: origen = cargado + cuarentena.
CREATE OR ALTER PROCEDURE dbo.usp_etl_atenciones
    @lote_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id UNIQUEIDENTIFIER = NEWID(), @leidos INT, @n INT;
    DECLARE @src_aten BIGINT, @src_acion BIGINT;
    DECLARE @fact_aten BIGINT, @fact_acion BIGINT;
    DECLARE @cuar_aten BIGINT, @cuar_acion BIGINT;

    BEGIN TRY
        -- Paso 1: cuantas filas hay en el origen
        SELECT @leidos = COUNT(*) FROM dbo.origen_atenciones_diagnostico;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '1_LECTURA_ORIGEN', 'origen_atenciones_diagnostico', @leidos, @leidos, CONCAT('Lote ', @lote_id));

        -- Paso 2: limpiar y cargar (usa el procedimiento del bloque 3.1)
        EXEC dbo.usp_cargar_atenciones @lote_id = @lote_id;

        -- Paso 3: filas rechazadas
        SELECT @n = COUNT(*) FROM dbo.tbl_cuarentena_atenciones WHERE lote_id = @lote_id;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '2_CUARENTENA', 'tbl_cuarentena_atenciones', @leidos, @n, 'Filas rechazadas en este lote');

        -- Paso 4: catalogos (total de filas que hay en cada uno)
        SELECT @n = COUNT(*) FROM dbo.Ubicacion;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '3_CATALOGO', 'Ubicacion', @leidos, @n, 'Total de filas en el catalogo');
        SELECT @n = COUNT(*) FROM dbo.Genero;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '3_CATALOGO', 'Genero', @leidos, @n, 'Total de filas en el catalogo');
        SELECT @n = COUNT(*) FROM dbo.Rango_Edad;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '3_CATALOGO', 'Rango_Edad', @leidos, @n, 'Total de filas en el catalogo');
        SELECT @n = COUNT(*) FROM dbo.Diagnostico;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '3_CATALOGO', 'Diagnostico', @leidos, @n, 'Total de filas en el catalogo');

        -- Paso 5: filas cargadas en la tabla principal
        SELECT @n = COUNT(*) FROM dbo.Atencion_Diagnostico WHERE lote_id = @lote_id;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '4_CARGA_HECHOS', 'Atencion_Diagnostico', @leidos, @n, 'Filas cargadas en este lote');

        -- Paso 6: cuadre de sumas (origen = cargado + cuarentena)
        SELECT @src_aten  = SUM(TRY_CAST(LTRIM(RTRIM(Atendidos)) AS BIGINT)),
               @src_acion = SUM(TRY_CAST(LTRIM(RTRIM(Atenciones)) AS BIGINT))
        FROM dbo.origen_atenciones_diagnostico;

        SELECT @fact_aten  = SUM(CAST(atendidos AS BIGINT)),
               @fact_acion = SUM(CAST(atenciones AS BIGINT))
        FROM dbo.Atencion_Diagnostico WHERE lote_id = @lote_id;

        SELECT @cuar_aten  = SUM(TRY_CAST(LTRIM(RTRIM(atendidos)) AS BIGINT)),
               @cuar_acion = SUM(TRY_CAST(LTRIM(RTRIM(atenciones)) AS BIGINT))
        FROM dbo.tbl_cuarentena_atenciones WHERE lote_id = @lote_id;

        IF ISNULL(@src_aten,0)  <> ISNULL(@fact_aten,0)  + ISNULL(@cuar_aten,0)
        OR ISNULL(@src_acion,0) <> ISNULL(@fact_acion,0) + ISNULL(@cuar_acion,0)
            THROW 50010, 'Cuadre fallido: la suma del origen no coincide con lo cargado + cuarentena. Revisa que el lote_id no se haya usado antes.', 1;

        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, '5_CUADRE', 'Atencion_Diagnostico', @leidos, @n,
                CONCAT('OK. Atendidos origen=', ISNULL(@src_aten,0), ' = final ', ISNULL(@fact_aten,0), ' + cuarentena ', ISNULL(@cuar_aten,0),
                       ' | Atenciones origen=', ISNULL(@src_acion,0), ' = final ', ISNULL(@fact_acion,0), ' + cuarentena ', ISNULL(@cuar_acion,0)));

        PRINT CONCAT('ETL OK. Ejecucion: ', CAST(@id AS VARCHAR(36)));
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, estado, detalle)
        VALUES (@id, 'ERROR', NULL, 'ERROR', LEFT(ERROR_MESSAGE(), 1000));
        THROW;
    END CATCH
END;
GO
