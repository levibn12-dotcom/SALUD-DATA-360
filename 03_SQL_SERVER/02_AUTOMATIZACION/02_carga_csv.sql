-- 02_AUTOMATIZACION/02_carga_csv.sql

USE BD_DataSalud_Atenciones;
GO

-- 3.2 usp_limpiar_origen: vacia la tabla de origen antes de cada archivo
CREATE OR ALTER PROCEDURE dbo.usp_limpiar_origen
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @filas INT = (SELECT COUNT(*) FROM dbo.origen_atenciones_diagnostico);
    TRUNCATE TABLE dbo.origen_atenciones_diagnostico;
    INSERT INTO dbo.log_auditoria (tabla, operacion, detalle)
    VALUES ('origen_atenciones_diagnostico', 'LIMPIAR', CONCAT('filas borradas=', @filas));
    PRINT CONCAT('Origen vaciado. Filas borradas: ', @filas);
END;
GO

-- 3.3 usp_cargar_csv: lee el CSV con BULK INSERT. Parametros: @ruta, @separador (',' o ';'),
--     @fin_linea ('\n' Excel/Windows), @con_comillas (1 si hay textos con comas; SQL Server 2017+).
--     Revisa que la ruta exista y que el origen este vacio.
CREATE OR ALTER VIEW dbo.vw_carga_origen AS
SELECT Anio, NroMes, ubigeo, Departamento, Provincia, Distrito, Sexo, Etapa, Diagnostico, Atendidos, Atenciones
FROM dbo.origen_atenciones_diagnostico;
GO

CREATE OR ALTER PROCEDURE dbo.usp_cargar_csv
    @ruta         NVARCHAR(500),
    @separador    CHAR(1)     = ',',
    @fin_linea    VARCHAR(10) = '\n',
    @con_comillas BIT         = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @existe INT = 0, @sql NVARCHAR(MAX), @filas INT;

    -- 1) Validaciones previas
    IF @separador NOT IN (',', ';')
        THROW 50020, 'El separador debe ser coma (,) o punto y coma (;).', 1;
    IF @fin_linea NOT IN ('\n', '0x0a')
        THROW 50021, 'El fin de linea debe ser \n (Excel en Windows) o 0x0a (Mac/Linux).', 1;
    IF EXISTS (SELECT 1 FROM dbo.origen_atenciones_diagnostico)
        THROW 50022, 'La tabla de origen ya tiene filas. Ejecuta primero: EXEC dbo.usp_limpiar_origen;', 1;

    EXEC master.dbo.xp_fileexist @ruta, @existe OUTPUT;
    IF ISNULL(@existe, 0) = 0
        THROW 50023, 'No se encontro el archivo. Revisa la ruta, el nombre y la extension .csv, y que el archivo este en el equipo donde corre SQL Server.', 1;

    BEGIN TRY
        -- 2) Se arma y ejecuta el BULK INSERT
        SET @sql = N'BULK INSERT dbo.vw_carga_origen FROM ''' + REPLACE(@ruta, '''', '''''') + N''''
                 + N' WITH (FIRSTROW = 2, FIELDTERMINATOR = ''' + @separador + N''''
                 + N', ROWTERMINATOR = ''' + @fin_linea + N''''
                 + N', CODEPAGE = ''65001'', TABLOCK'
                 + CASE WHEN @con_comillas = 1 THEN N', FORMAT = ''CSV''' ELSE N'' END
                 + N');';
        EXEC sys.sp_executesql @sql;

        -- 3) Limpieza de saltos de linea que a veces quedan pegados a la ultima columna
        UPDATE dbo.origen_atenciones_diagnostico
        SET Atenciones = REPLACE(REPLACE(Atenciones, CHAR(13), ''), CHAR(10), '')
        WHERE CHARINDEX(CHAR(13), Atenciones) > 0 OR CHARINDEX(CHAR(10), Atenciones) > 0;

        SELECT @filas = COUNT(*) FROM dbo.origen_atenciones_diagnostico;

        INSERT INTO dbo.log_auditoria (tabla, operacion, detalle)
        VALUES ('origen_atenciones_diagnostico', 'CARGA_CSV', CONCAT('archivo=', @ruta, '; filas=', @filas));

        PRINT CONCAT('CSV cargado en origen. Filas: ', @filas);
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.log_auditoria (tabla, operacion, detalle)
        VALUES ('origen_atenciones_diagnostico', 'ERROR', LEFT(CONCAT('Fallo al leer ', @ruta, ': ', ERROR_MESSAGE()), 1000));
        PRINT 'Pistas: 1) el CSV debe tener 11 columnas en el orden del Excel; 2) revisa el separador (coma o punto y coma);';
        PRINT '        3) la cuenta del servicio de SQL Server debe poder leer la carpeta; 4) guarda como CSV UTF-8.';
        THROW;
    END CATCH
END;
GO
