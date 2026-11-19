-- 02_AUTOMATIZACION/01_carga_atenciones.sql

USE BD_DataSalud_Atenciones;
GO

-- 3. PROCEDIMIENTOS DE CARGA
-- 3.1 usp_cargar_atenciones: limpia el origen, manda filas malas o repetidas a cuarentena,
--     completa los catalogos y llena la tabla principal. Clave de fila: anio + mes + ubicacion + sexo + etapa + diagnostico.
CREATE OR ALTER PROCEDURE dbo.usp_cargar_atenciones
    @lote_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sp_creado BIT = 0, @leidos INT = 0, @cuarentena INT = 0, @cargados INT = 0;
    IF OBJECT_ID('tempdb..#clasif') IS NOT NULL DROP TABLE #clasif;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- a) Limpieza.
        ;WITH s AS (
            SELECT id_origen,
                   Anio AS anio_txt,
                   TRY_CAST(LTRIM(RTRIM(Anio)) AS SMALLINT) AS anio,
                   NroMes AS mes_txt,
                   TRY_CAST(LTRIM(RTRIM(NroMes)) AS TINYINT) AS nro_mes,
                   -- el Excel pierde el cero inicial (30401 -> 030401): se completa a 6 digitos
                   CASE WHEN NULLIF(LTRIM(RTRIM(ubigeo)),'') IS NULL THEN 'No registrado'
                        ELSE RIGHT(CONCAT('000000', LTRIM(RTRIM(ubigeo))), 6) END AS ubigeo,
                   ISNULL(NULLIF(UPPER(LTRIM(RTRIM(Departamento))),''),'No registrado') AS departamento,
                   ISNULL(NULLIF(UPPER(LTRIM(RTRIM(Provincia))),''),'No registrado')    AS provincia,
                   ISNULL(NULLIF(UPPER(LTRIM(RTRIM(Distrito))),''),'No registrado')     AS distrito,
                   -- sexo: solo F o M; cualquier otra cosa es 'No registrado'
                   CASE WHEN UPPER(LEFT(LTRIM(Sexo),1)) IN ('M','F') THEN UPPER(LEFT(LTRIM(Sexo),1))
                        ELSE 'No registrado' END AS sexo,
                   ISNULL(NULLIF(LTRIM(RTRIM(Etapa)),''),'No registrado') AS etapa,
                   ISNULL(NULLIF(UPPER(LTRIM(RTRIM(Diagnostico))),''),'No registrado') AS diagnostico,
                   Atendidos AS atendidos_txt,
                   TRY_CAST(LTRIM(RTRIM(Atendidos)) AS INT)  AS atendidos,
                   Atenciones AS atenciones_txt,
                   TRY_CAST(LTRIM(RTRIM(Atenciones)) AS INT) AS atenciones
            FROM dbo.origen_atenciones_diagnostico
        ), m AS (
            -- malo = 1 si la fila tiene un dato numerico invalido
            SELECT *,
                   CASE WHEN anio IS NULL OR nro_mes IS NULL OR nro_mes NOT BETWEEN 1 AND 12
                          OR atendidos IS NULL OR atendidos < 0
                          OR atenciones IS NULL OR atenciones < 0
                        THEN 1 ELSE 0 END AS malo
            FROM s
        ), r AS (
            SELECT *, ROW_NUMBER() OVER (
                       PARTITION BY anio, nro_mes, ubigeo, departamento, provincia, distrito, sexo, etapa, diagnostico
                       ORDER BY malo, id_origen) AS rn
            FROM m
        )
        -- b) Se marca el motivo de error (NULL = fila buena)
        SELECT r.*,
               CASE
                 WHEN anio IS NULL THEN 'Anio nulo o invalido'
                 WHEN nro_mes IS NULL OR nro_mes NOT BETWEEN 1 AND 12 THEN 'Mes nulo o fuera de 1-12'
                 WHEN atendidos IS NULL OR atendidos < 0 THEN 'Atendidos nulo, invalido o negativo'
                 WHEN atenciones IS NULL OR atenciones < 0 THEN 'Atenciones nulo, invalido o negativo'
                 WHEN rn > 1 THEN 'Duplicado dentro del lote'
                 WHEN EXISTS (SELECT 1
                              FROM dbo.Atencion_Diagnostico f
                              JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
                              JOIN dbo.Genero g ON g.id_genero = f.id_genero
                              JOIN dbo.Rango_Edad e ON e.id_rango_edad = f.id_rango_edad
                              JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
                              WHERE f.anio = r.anio AND f.nro_mes = r.nro_mes
                                AND u.ubigeo = r.ubigeo AND u.departamento = r.departamento
                                AND u.provincia = r.provincia AND u.distrito = r.distrito
                                AND g.sexo = r.sexo AND e.etapa = r.etapa AND d.diagnostico = r.diagnostico)
                      THEN 'Ya existe en tabla final'
               END AS motivo
        INTO #clasif
        FROM r;

        SELECT @leidos = COUNT(*) FROM #clasif;

        -- c) Filas malas o duplicadas -> cuarentena
        INSERT INTO dbo.tbl_cuarentena_atenciones
               (anio, nro_mes, ubigeo, provincia, diagnostico, atendidos, atenciones, motivo_error, lote_id)
        SELECT anio_txt, mes_txt, ubigeo, provincia, diagnostico, atendidos_txt, atenciones_txt, motivo, @lote_id
        FROM #clasif WHERE motivo IS NOT NULL;
        SET @cuarentena = @@ROWCOUNT;

        SAVE TRANSACTION sp_post_cuarentena;
        SET @sp_creado = 1;

        -- d) Catalogos: solo se agregan los valores que aun no existen
        INSERT INTO dbo.Ubicacion (ubigeo, departamento, provincia, distrito)
        SELECT ubigeo, departamento, provincia, distrito FROM #clasif WHERE motivo IS NULL
        EXCEPT
        SELECT ubigeo, departamento, provincia, distrito FROM dbo.Ubicacion;

        INSERT INTO dbo.Genero (sexo)
        SELECT sexo FROM #clasif WHERE motivo IS NULL
        EXCEPT SELECT sexo FROM dbo.Genero;

        INSERT INTO dbo.Rango_Edad (etapa)
        SELECT etapa FROM #clasif WHERE motivo IS NULL
        EXCEPT SELECT etapa FROM dbo.Rango_Edad;

        INSERT INTO dbo.Diagnostico (diagnostico)
        SELECT diagnostico FROM #clasif WHERE motivo IS NULL
        EXCEPT SELECT diagnostico FROM dbo.Diagnostico;

        -- e) Tabla principal: se buscan los IDs con JOIN (une tablas por el id)
        INSERT INTO dbo.Atencion_Diagnostico
               (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes, atendidos, atenciones, lote_id)
        SELECT u.id_ubicacion, g.id_genero, e.id_rango_edad, d.id_diagnostico,
               c.anio, c.nro_mes, c.atendidos, c.atenciones, @lote_id
        FROM #clasif c
        JOIN dbo.Ubicacion u ON u.ubigeo = c.ubigeo AND u.departamento = c.departamento
                            AND u.provincia = c.provincia AND u.distrito = c.distrito
        JOIN dbo.Genero g ON g.sexo = c.sexo
        JOIN dbo.Rango_Edad e ON e.etapa = c.etapa
        JOIN dbo.Diagnostico d ON d.diagnostico = c.diagnostico
        WHERE c.motivo IS NULL;
        SET @cargados = @@ROWCOUNT;

        -- f) Resumen del lote
        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('Atencion_Diagnostico', 'INGESTA', @lote_id,
                CONCAT('leidos=', @leidos, '; cargados=', @cargados, '; rechazados=', @cuarentena));

        COMMIT TRANSACTION;
        PRINT CONCAT('Carga OK. Leidos: ', @leidos, ' | Cargados: ', @cargados, ' | Rechazados: ', @cuarentena);
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE(), @num INT = ERROR_NUMBER();
        DECLARE @alcance VARCHAR(30) = 'ninguno';

        IF XACT_STATE() = 1 AND @sp_creado = 1
        BEGIN
            ROLLBACK TRANSACTION sp_post_cuarentena;  -- deshace solo la carga final
            COMMIT TRANSACTION;                        -- conserva la cuarentena
            SET @alcance = 'parcial (savepoint)';
        END
        ELSE IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;                      -- deshace todo
            SET @alcance = 'total';
        END

        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('Atencion_Diagnostico', 'ERROR', @lote_id,
                CONCAT('Error ', @num, ': ', @msg, ' | rollback ', @alcance));
        THROW;   -- vuelve a lanzar el error original para que se vea
    END CATCH
END;
GO
