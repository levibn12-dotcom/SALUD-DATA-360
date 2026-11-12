# 02 - Automatizacion (funcion, procedimientos y ETL)

Logica reutilizable y automatizable: funcion de grupo etario, procedimientos de ingesta/validacion con cuarentena y savepoint, y el ETL del Data Warehouse. Requiere haber ejecutado antes `01_DATABASE` (tablas) e importado la tabla `[DAT SALUD MENTAL - TAMIZAJE]`.

## 1. Funcion reutilizable

```sql
/* ---------------------------------------------------------------------
   1. FUNCION REUTILIZABLE: grupo etario (etapas de vida MINSA)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_grupo_etario (@edad INT)
RETURNS VARCHAR(20)
AS
BEGIN
    RETURN CASE
        WHEN @edad IS NULL OR @edad < 0 OR @edad > 120 THEN 'No registrado'
        WHEN @edad <= 11 THEN 'Nino'
        WHEN @edad <= 17 THEN 'Adolescente'
        WHEN @edad <= 29 THEN 'Joven'
        WHEN @edad <= 59 THEN 'Adulto'
        ELSE 'Adulto mayor'
    END;
END;
GO
```

## 2. Procedimientos almacenados (ingesta y tamizajes)

```sql
/* ---------------------------------------------------------------------
   3. PROCEDIMIENTOS ALMACENADOS
   3.1 Ingesta y validacion de atenciones (staging -> tabla final)
       - Clasifica cada fila UNA vez en #clasif con su motivo de rechazo.
       - Rechazadas y duplicadas van a cuarentena (nada se pierde en silencio).
       - SAVEPOINT despues de la cuarentena: si falla la carga final se
         revierte solo la carga y se conserva la cuarentena.
       - Idempotente: no vuelve a cargar lo que ya existe.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ingesta_y_validar_atenciones
    @lote_id VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sp_creado BIT = 0, @leidos INT = 0, @cuarentena INT = 0, @cargados INT = 0;
    IF OBJECT_ID('tempdb..#clasif') IS NOT NULL DROP TABLE #clasif;

    BEGIN TRY
        BEGIN TRANSACTION;

        ;WITH s AS (
            SELECT id_staging,
                   LTRIM(RTRIM(Co_Establecimiento)) AS co_est,
                   Nom_Establecimiento AS nom_est,
                   Fecha_Atencion AS fecha_txt,
                   TRY_CAST(Fecha_Atencion AS DATE) AS fecha,
                   Edad AS edad_txt,
                   TRY_CAST(Edad AS INT) AS edad,
                   CASE WHEN UPPER(LEFT(LTRIM(Sexo),1)) IN ('M','F') THEN UPPER(LEFT(LTRIM(Sexo),1)) END AS sexo,
                   LTRIM(RTRIM(Diagnostico)) AS diag,
                   Ubigeo AS ubigeo
            FROM dbo.staging_atenciones_mental
        ), r AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY co_est, fecha, edad, sexo, diag ORDER BY id_staging) AS rn
            FROM s
        )
        SELECT r.*,
               CASE
                 WHEN NULLIF(diag,'') IS NULL THEN 'Diagnostico nulo o vacio'
                 WHEN NULLIF(LTRIM(RTRIM(fecha_txt)),'') IS NULL THEN 'Fecha nula o vacia'
                 WHEN fecha IS NULL THEN 'Fecha con formato invalido'
                 WHEN fecha > CAST(GETDATE() AS DATE) THEN 'Fecha futura'
                 WHEN edad IS NULL OR edad NOT BETWEEN 0 AND 120 THEN 'Edad invalida o fuera de rango'
                 WHEN NULLIF(co_est,'') IS NULL THEN 'Establecimiento nulo o vacio'
                 WHEN rn > 1 THEN 'Duplicado dentro del lote'
                 WHEN EXISTS (SELECT 1 FROM dbo.tbl_atenciones_salud_mental a
                              WHERE a.co_establecimiento = r.co_est AND a.fecha_atencion = r.fecha
                                AND a.edad = r.edad AND ISNULL(a.sexo,'?') = ISNULL(r.sexo,'?')
                                AND a.diagnostico = r.diag) THEN 'Ya existe en tabla final'
               END AS motivo
        INTO #clasif
        FROM r;

        SELECT @leidos = COUNT(*) FROM #clasif;

        INSERT INTO dbo.tbl_cuarentena_atenciones (co_establecimiento, fecha_atencion, edad, diagnostico, motivo_error, lote_id)
        SELECT co_est, fecha_txt, edad_txt, diag, motivo, @lote_id
        FROM #clasif WHERE motivo IS NOT NULL;
        SET @cuarentena = @@ROWCOUNT;

        SAVE TRANSACTION sp_post_cuarentena;
        SET @sp_creado = 1;

        INSERT INTO dbo.tbl_atenciones_salud_mental (co_establecimiento, nom_establecimiento, fecha_atencion, edad, sexo, diagnostico, ubigeo)
        SELECT co_est, nom_est, fecha, edad, sexo, diag, ubigeo
        FROM #clasif WHERE motivo IS NULL;
        SET @cargados = @@ROWCOUNT;

        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('tbl_atenciones_salud_mental', 'INGESTA', @lote_id,
                CONCAT('leidos=', @leidos, '; cargados=', @cargados, '; cuarentena=', @cuarentena));

        COMMIT TRANSACTION;
        PRINT CONCAT('Ingesta OK. Leidos: ', @leidos, ' | Cargados: ', @cargados, ' | Cuarentena: ', @cuarentena);
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
            ROLLBACK TRANSACTION;                      -- rollback total
            SET @alcance = 'total';
        END

        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('tbl_atenciones_salud_mental', 'ERROR', @lote_id,
                CONCAT('Error ', @num, ': ', @msg, ' | rollback ', @alcance));
        THROW;
    END CATCH
END;
GO

/* 3.2 Procesamiento de tamizajes (fuente importada -> tabla limpia) con cuarentena */
CREATE OR ALTER PROCEDURE dbo.usp_procesar_tamizajes_salud_mental
    @lote_id VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sp_creado BIT = 0, @leidos INT = 0, @cuarentena INT = 0, @cargados INT = 0;
    SET @lote_id = ISNULL(@lote_id, CONCAT('TAM_', FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss')));
    IF OBJECT_ID('tempdb..#clasif_t') IS NOT NULL DROP TABLE #clasif_t;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- SUPUESTO: la clave de negocio es anio+mes+ubigeo+sexo+etapa+grupo+detalle.
        -- Si la fuente repite la clave, se conserva la primera fila y las demas van a cuarentena.
        ;WITH s AS (
            SELECT TRY_CAST(Anio AS SMALLINT) AS anio, Anio AS anio_txt,
                   TRY_CAST(NroMes AS TINYINT) AS nro_mes, NroMes AS mes_txt,
                   ubigeo, Departamento AS departamento, Provincia AS provincia, Distrito AS distrito,
                   Sexo AS sexo, Etapa AS etapa, GrupoTamizaje AS grupo_tamizaje, DetalleTamizaje AS detalle_tamizaje,
                   TRY_CAST(Casos AS INT) AS casos, Casos AS casos_txt
            FROM dbo.[DAT SALUD MENTAL - TAMIZAJE]
        ), r AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY anio, nro_mes, ubigeo, sexo, etapa, grupo_tamizaje, detalle_tamizaje
                                         ORDER BY (SELECT NULL)) AS rn
            FROM s
        )
        SELECT r.*,
               CASE
                 WHEN anio IS NULL THEN 'Anio nulo o invalido'
                 WHEN nro_mes IS NULL OR nro_mes NOT BETWEEN 1 AND 12 THEN 'Mes nulo o fuera de 1-12'
                 WHEN casos IS NULL OR casos < 0 THEN 'Casos nulos o negativos'
                 WHEN NULLIF(LTRIM(RTRIM(provincia)),'') IS NULL THEN 'Provincia nula o vacia'
                 WHEN rn > 1 THEN 'Duplicado en la fuente'
                 WHEN EXISTS (SELECT 1 FROM dbo.tbl_tamizajes_salud_mental_limpio t
                              WHERE t.anio = r.anio AND t.nro_mes = r.nro_mes AND t.ubigeo = r.ubigeo
                                AND t.sexo = r.sexo AND t.etapa = r.etapa
                                AND t.grupo_tamizaje = r.grupo_tamizaje AND t.detalle_tamizaje = r.detalle_tamizaje)
                      THEN 'Ya existe en tabla final'
               END AS motivo
        INTO #clasif_t
        FROM r;

        SELECT @leidos = COUNT(*) FROM #clasif_t;

        INSERT INTO dbo.tbl_cuarentena_tamizajes (anio, nro_mes, ubigeo, provincia, casos, motivo_error, lote_id)
        SELECT anio_txt, mes_txt, ubigeo, provincia, casos_txt, motivo, @lote_id
        FROM #clasif_t WHERE motivo IS NOT NULL;
        SET @cuarentena = @@ROWCOUNT;

        SAVE TRANSACTION sp_post_cuarentena_t;
        SET @sp_creado = 1;

        INSERT INTO dbo.tbl_tamizajes_salud_mental_limpio
               (anio, nro_mes, ubigeo, departamento, provincia, distrito, sexo, etapa, grupo_tamizaje, detalle_tamizaje, casos)
        SELECT anio, nro_mes, ubigeo, departamento, provincia, distrito, sexo, etapa, grupo_tamizaje, detalle_tamizaje, casos
        FROM #clasif_t WHERE motivo IS NULL;
        SET @cargados = @@ROWCOUNT;

        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('tbl_tamizajes_salud_mental_limpio', 'INGESTA', @lote_id,
                CONCAT('leidos=', @leidos, '; cargados=', @cargados, '; cuarentena=', @cuarentena));

        COMMIT TRANSACTION;
        PRINT CONCAT('Tamizajes OK. Leidos: ', @leidos, ' | Cargados: ', @cargados, ' | Cuarentena: ', @cuarentena);
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE(), @num INT = ERROR_NUMBER();
        DECLARE @alcance VARCHAR(30) = 'ninguno';

        IF XACT_STATE() = 1 AND @sp_creado = 1
        BEGIN
            ROLLBACK TRANSACTION sp_post_cuarentena_t;
            COMMIT TRANSACTION;
            SET @alcance = 'parcial (savepoint)';
        END
        ELSE IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
            SET @alcance = 'total';
        END

        INSERT INTO dbo.log_auditoria (tabla, operacion, lote_id, detalle)
        VALUES ('tbl_tamizajes_salud_mental_limpio', 'ERROR', @lote_id,
                CONCAT('Error ', @num, ': ', @msg, ' | rollback ', @alcance));
        THROW;
    END CATCH
END;
GO
```

## 3. ETL del Data Warehouse

```sql
/* ---------------------------------------------------------------------
   5. ETL DEL DATA WAREHOUSE (idempotente, con log por etapa y reconciliacion)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_etl_dw_tamizajes
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id UNIQUEIDENTIFIER = NEWID(), @n INT = 0, @leidos INT = 0;
    DECLARE @suma_src BIGINT, @suma_fact BIGINT;
    IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- E + T: extraccion y limpieza. Vacios -> 'No registrado' para que los joins no pierdan filas con NULL.
        SELECT anio, nro_mes,
               ISNULL(NULLIF(LTRIM(RTRIM(ubigeo)),''),'SIN_UBIGEO') AS ubigeo,
               ISNULL(NULLIF(LTRIM(RTRIM(departamento)),''),'No registrado') AS departamento,
               ISNULL(NULLIF(LTRIM(RTRIM(provincia)),''),'No registrado') AS provincia,
               ISNULL(NULLIF(LTRIM(RTRIM(distrito)),''),'No registrado') AS distrito,
               ISNULL(NULLIF(LTRIM(RTRIM(sexo)),''),'No registrado') AS sexo,
               ISNULL(NULLIF(LTRIM(RTRIM(etapa)),''),'No registrado') AS etapa,
               ISNULL(NULLIF(LTRIM(RTRIM(grupo_tamizaje)),''),'No registrado') AS grupo_tamizaje,
               ISNULL(NULLIF(LTRIM(RTRIM(detalle_tamizaje)),''),'No registrado') AS detalle_tamizaje,
               casos
        INTO #src
        FROM dbo.tbl_tamizajes_salud_mental_limpio
        WHERE anio IS NOT NULL AND nro_mes IS NOT NULL AND casos IS NOT NULL;
        SET @leidos = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'EXTRACCION_Y_LIMPIEZA', '#src', @leidos, @leidos,
                'TRIM; vacios -> No registrado; ubigeo vacio -> SIN_UBIGEO; se excluyen filas sin anio, mes o casos');

        -- L: dimensiones (solo agrega miembros nuevos; EXCEPT trata NULL como igual)
        INSERT INTO dbo.Dim_Ubicacion (ubigeo, departamento, provincia, distrito)
        SELECT ubigeo, departamento, provincia, distrito FROM #src
        EXCEPT SELECT ubigeo, departamento, provincia, distrito FROM dbo.Dim_Ubicacion;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'CARGA_DIMENSION', 'Dim_Ubicacion', @leidos, @n, 'Solo miembros nuevos (EXCEPT)');

        INSERT INTO dbo.Dim_Tiempo (anio, nro_mes)
        SELECT anio, nro_mes FROM #src
        EXCEPT SELECT anio, nro_mes FROM dbo.Dim_Tiempo;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'CARGA_DIMENSION', 'Dim_Tiempo', @leidos, @n, 'Solo miembros nuevos (EXCEPT)');

        INSERT INTO dbo.Dim_Perfil (sexo, etapa, grupo_tamizaje, detalle_tamizaje)
        SELECT sexo, etapa, grupo_tamizaje, detalle_tamizaje FROM #src
        EXCEPT SELECT sexo, etapa, grupo_tamizaje, detalle_tamizaje FROM dbo.Dim_Perfil;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'CARGA_DIMENSION', 'Dim_Perfil', @leidos, @n, 'Solo miembros nuevos (EXCEPT)');

        -- L: hechos (recarga completa para ser idempotente)
        DELETE FROM dbo.Fact_Tamizajes;
        INSERT INTO dbo.Fact_Tamizajes (id_ubicacion, id_tiempo, id_perfil, casos)
        SELECT u.id_ubicacion, t.id_tiempo, p.id_perfil, s.casos
        FROM #src s
        JOIN dbo.Dim_Ubicacion u ON u.ubigeo = s.ubigeo AND u.departamento = s.departamento
                                 AND u.provincia = s.provincia AND u.distrito = s.distrito
        JOIN dbo.Dim_Tiempo t ON t.anio = s.anio AND t.nro_mes = s.nro_mes
        JOIN dbo.Dim_Perfil p ON p.sexo = s.sexo AND p.etapa = s.etapa
                              AND p.grupo_tamizaje = s.grupo_tamizaje AND p.detalle_tamizaje = s.detalle_tamizaje;
        SET @n = @@ROWCOUNT;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'CARGA_HECHOS', 'Fact_Tamizajes', @leidos, @n, 'Recarga completa; joins por todas las columnas de la dimension');

        -- Reconciliacion: la suma de casos debe coincidir entre origen y hechos
        SELECT @suma_src = SUM(CAST(casos AS BIGINT)) FROM #src;
        SELECT @suma_fact = SUM(CAST(casos AS BIGINT)) FROM dbo.Fact_Tamizajes;
        IF ISNULL(@suma_src,0) <> ISNULL(@suma_fact,0)
            THROW 50010, 'Reconciliacion fallida: la suma de casos del origen no coincide con Fact_Tamizajes.', 1;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, filas_leidas, filas_cargadas, detalle)
        VALUES (@id, 'RECONCILIACION', 'Fact_Tamizajes', @leidos, @n, CONCAT('Suma de casos origen = hechos = ', @suma_fact));

        COMMIT TRANSACTION;
        PRINT CONCAT('ETL OK. Ejecucion: ', CAST(@id AS VARCHAR(36)));
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2000) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.etl_log (ejecucion_id, etapa, tabla_destino, estado, detalle)
        VALUES (@id, 'ERROR', NULL, 'ERROR', LEFT(@msg, 1000));
        THROW;
    END CATCH
END;
GO

/* OPCIONAL (una sola vez): si ya corriste el ETL anterior y quedaron dimensiones duplicadas o con NULL, limpia asi:
   DELETE FROM dbo.Fact_Tamizajes;
   DELETE FROM dbo.Dim_Ubicacion; DELETE FROM dbo.Dim_Tiempo; DELETE FROM dbo.Dim_Perfil;
   DBCC CHECKIDENT ('dbo.Dim_Ubicacion', RESEED, 0); DBCC CHECKIDENT ('dbo.Dim_Tiempo', RESEED, 0);
   DBCC CHECKIDENT ('dbo.Dim_Perfil', RESEED, 0);
*/
```

## 4. Pruebas de la funcion, ingesta y ETL

```sql
-- 8.1 Funcion
SELECT dbo.fn_grupo_etario(5) AS nino, dbo.fn_grupo_etario(15) AS adolescente,
       dbo.fn_grupo_etario(40) AS adulto, dbo.fn_grupo_etario(NULL) AS nulo;
GO

-- 8.2 Ingesta de atenciones con datos de prueba (esperado: 2 cargados, 4 en cuarentena)
INSERT INTO dbo.staging_atenciones_mental (Co_Establecimiento, Nom_Establecimiento, Fecha_Atencion, Edad, Sexo, Diagnostico, Ubigeo) VALUES
 ('0001','HOSP A','2024-03-10','25','M','F32 Depresion','130101'),
 ('0001','HOSP A','2024-03-10','25','M','F32 Depresion','130101'),   -- duplicado
 ('0002','CS B','2024-03-11','34','F','','130201'),                   -- diagnostico vacio
 ('0002','CS B','2024-13-45','34','F','F41 Ansiedad','130201'),      -- fecha invalida
 ('0003','CS C','2024-03-12','150','F','F41 Ansiedad','130301'),     -- edad fuera de rango
 ('0003','CS C','2024-03-12','40','Femenino','F41 Ansiedad','130301'); -- valido
GO
EXEC dbo.usp_ingesta_y_validar_atenciones @lote_id = 'LOTE_PRUEBA_01';
SELECT * FROM dbo.tbl_atenciones_salud_mental;
SELECT * FROM dbo.tbl_cuarentena_atenciones WHERE lote_id = 'LOTE_PRUEBA_01';
GO

-- 8.5 Tamizajes y ETL
EXEC dbo.usp_procesar_tamizajes_salud_mental;
SELECT COUNT(*) AS limpios FROM dbo.tbl_tamizajes_salud_mental_limpio;
SELECT motivo_error, COUNT(*) AS filas FROM dbo.tbl_cuarentena_tamizajes GROUP BY motivo_error;  -- tabla de calidad del informe
EXEC dbo.usp_etl_dw_tamizajes;
SELECT * FROM dbo.etl_log ORDER BY id_etl DESC;
SELECT (SELECT COUNT(*) FROM dbo.Fact_Tamizajes) AS hechos,
       (SELECT COUNT(*) FROM dbo.Dim_Ubicacion) AS dim_ubicacion,
       (SELECT COUNT(*) FROM dbo.Dim_Tiempo) AS dim_tiempo,
       (SELECT COUNT(*) FROM dbo.Dim_Perfil) AS dim_perfil;
GO
```
