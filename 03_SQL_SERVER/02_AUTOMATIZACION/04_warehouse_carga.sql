-- 02_AUTOMATIZACION/04_warehouse_carga.sql

USE BD_DataSalud_Atenciones;
GO

-- ---- Procedimiento que llena las 3 tablas resumen (se ejecuta en el paso 10.5) ----
-- Pasos: 1) avisa si todavia no hay datos  2) borra el resumen anterior  3) recalcula las 3 tablas
--        4) deja huella en etl_log  5) comprueba que cada tabla suma lo mismo que la tabla de hechos.
CREATE OR ALTER PROCEDURE dbo.usp_cargar_warehouse
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id UNIQUEIDENTIFIER = NEWID(), @leidos INT, @n INT;
    DECLARE @h_aten BIGINT, @h_acion BIGINT;
    DECLARE @t1 BIGINT, @a1 BIGINT, @t2 BIGINT, @a2 BIGINT, @t3 BIGINT, @a3 BIGINT;

    BEGIN TRY
        -- 1) Aviso: si no hay datos, todavia no toca ejecutar el warehouse
        SELECT @leidos = COUNT(*) FROM dbo.Atencion_Diagnostico;
        IF @leidos = 0
            THROW 50030, 'Todavia no hay datos en Atencion_Diagnostico. Primero importa tus archivos (bloque 10, pasos 10.2 a 10.4) y luego ejecuta el warehouse.', 1;

        BEGIN TRANSACTION;

        -- 2) Se borra el resumen anterior (se reconstruye completo cada vez)
        DELETE FROM dw.Resumen_Tiempo_Diagnostico;
        DELETE FROM dw.Resumen_Ubicacion;
        DELETE FROM dw.Resumen_Perfil;

        -- 3a) Resumen por tiempo y diagnostico
        INSERT INTO dw.Resumen_Tiempo_Diagnostico (anio, nro_mes, diagnostico, total_atendidos, total_atenciones, promedio_atenciones)
        SELECT f.anio, f.nro_mes, d.diagnostico,
               SUM(f.atendidos), SUM(f.atenciones),
               dbo.fn_promedio_atenciones(SUM(f.atendidos), SUM(f.atenciones))
        FROM dbo.Atencion_Diagnostico f
        JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
        GROUP BY f.anio, f.nro_mes, d.diagnostico;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'WAREHOUSE', 'dw.Resumen_Tiempo_Diagnostico', @leidos, @n, 'Reconstruida completa');

        -- 3b) Resumen por ubicacion (departamento y provincia)
        INSERT INTO dw.Resumen_Ubicacion (anio, departamento, provincia, diagnostico, total_atendidos, total_atenciones, promedio_atenciones)
        SELECT f.anio, u.departamento, u.provincia, d.diagnostico,
               SUM(f.atendidos), SUM(f.atenciones),
               dbo.fn_promedio_atenciones(SUM(f.atendidos), SUM(f.atenciones))
        FROM dbo.Atencion_Diagnostico f
        JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
        JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
        GROUP BY f.anio, u.departamento, u.provincia, d.diagnostico;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'WAREHOUSE', 'dw.Resumen_Ubicacion', @leidos, @n, 'Reconstruida completa');

        -- 3c) Resumen por perfil (sexo y etapa)
        INSERT INTO dw.Resumen_Perfil (anio, sexo, etapa, diagnostico, total_atendidos, total_atenciones, promedio_atenciones)
        SELECT f.anio, g.sexo, e.etapa, d.diagnostico,
               SUM(f.atendidos), SUM(f.atenciones),
               dbo.fn_promedio_atenciones(SUM(f.atendidos), SUM(f.atenciones))
        FROM dbo.Atencion_Diagnostico f
        JOIN dbo.Genero g ON g.id_genero = f.id_genero
        JOIN dbo.Rango_Edad e ON e.id_rango_edad = f.id_rango_edad
        JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
        GROUP BY f.anio, g.sexo, e.etapa, d.diagnostico;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'WAREHOUSE', 'dw.Resumen_Perfil', @leidos, @n, 'Reconstruida completa');

        -- 5) Cuadre: cada tabla resumen debe sumar lo mismo que la tabla de hechos
        SELECT @h_aten = SUM(CAST(atendidos AS BIGINT)), @h_acion = SUM(CAST(atenciones AS BIGINT)) FROM dbo.Atencion_Diagnostico;
        SELECT @t1 = SUM(CAST(total_atendidos AS BIGINT)), @a1 = SUM(CAST(total_atenciones AS BIGINT)) FROM dw.Resumen_Tiempo_Diagnostico;
        SELECT @t2 = SUM(CAST(total_atendidos AS BIGINT)), @a2 = SUM(CAST(total_atenciones AS BIGINT)) FROM dw.Resumen_Ubicacion;
        SELECT @t3 = SUM(CAST(total_atendidos AS BIGINT)), @a3 = SUM(CAST(total_atenciones AS BIGINT)) FROM dw.Resumen_Perfil;

        IF @h_aten  <> ISNULL(@t1,0) OR @h_aten  <> ISNULL(@t2,0) OR @h_aten  <> ISNULL(@t3,0)
        OR @h_acion <> ISNULL(@a1,0) OR @h_acion <> ISNULL(@a2,0) OR @h_acion <> ISNULL(@a3,0)
            THROW 50031, 'Cuadre fallido: una tabla resumen no suma lo mismo que Atencion_Diagnostico. Se deshizo el warehouse.', 1;

        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'WAREHOUSE_CUADRE', 'dw.*', @leidos, @leidos,
                CONCAT('OK. Atendidos hechos=', @h_aten, ' = cada resumen | Atenciones hechos=', @h_acion, ' = cada resumen'));

        COMMIT TRANSACTION;
        PRINT CONCAT('Warehouse OK. Ejecucion: ', CAST(@id AS VARCHAR(36)));
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, estado, detalle)
        VALUES (@id, 'WAREHOUSE', NULL, 'ERROR', LEFT(@msg, 1000));
        THROW;
    END CATCH
END;
GO
