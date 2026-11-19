-- ETL y Data Warehouse | Base: BD_DataSalud_Atenciones
-- Ejecutar una vez, despues de crear la estructura (03_SQL_SERVER).
-- Luego: cargar CSV -> EXEC usp_etl_atenciones -> EXEC usp_cargar_warehouse.
USE BD_DataSalud_Atenciones;
GO

-- ETL: carga un lote desde origen al modelo y deja el cuadre en etl_log.
-- Cuadre: origen = cargado + cuarentena. El origen debe tener solo el lote a cargar.
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

        -- Paso 2: limpiar y cargar
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

-- WAREHOUSE (esquema dw): 3 tablas resumen que lee Power BI.
-- Se reconstruyen completas con usp_cargar_warehouse, ejecutalo al final de cargar todos los archivos.
-- Ojo: sumar atendidos entre meses puede contar dos veces a la misma persona.
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
GO

-- Resumen 1: evolucion por mes y diagnostico (lineas/columnas)
IF OBJECT_ID('dw.Resumen_Tiempo_Diagnostico','U') IS NULL
CREATE TABLE dw.Resumen_Tiempo_Diagnostico (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    nro_mes             TINYINT  NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,   -- atenciones por persona atendida
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Tiempo_Diagnostico PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Tiempo_Diagnostico UNIQUE (anio, nro_mes, diagnostico)
);
GO

-- Resumen 2: ubicacion hasta provincia (mapa/barras)
IF OBJECT_ID('dw.Resumen_Ubicacion','U') IS NULL
CREATE TABLE dw.Resumen_Ubicacion (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    departamento        VARCHAR(100) NOT NULL,
    provincia           VARCHAR(100) NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Ubicacion PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Ubicacion UNIQUE (anio, departamento, provincia, diagnostico)
);
GO

-- Resumen 3: perfil por sexo y etapa de vida (barras)
IF OBJECT_ID('dw.Resumen_Perfil','U') IS NULL
CREATE TABLE dw.Resumen_Perfil (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    sexo                VARCHAR(20) NOT NULL,
    etapa               VARCHAR(50) NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Perfil PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Perfil UNIQUE (anio, sexo, etapa, diagnostico)
);
GO

-- Llena las 3 tablas, cuadra sumas contra la tabla de hechos y revierte si no coinciden.
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
