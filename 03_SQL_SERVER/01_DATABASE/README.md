# 01 - Base de datos (script completo)

Script completo y en orden de ejecucion de **DataSalud Peru - DIRESA La Libertad** (CIIN1021P). Incluye base, tablas, funcion, triggers, procedimientos, vistas, ETL, seguridad, indice, pruebas y backups. Tambien puedes descargar el archivo `BIG_DATA_corregido.sql` de esta misma carpeta.

## Script completo

```sql
/* =====================================================================
   DataSalud Peru - DIRESA La Libertad  |  CIIN1021P
   Script corregido y completo. Ejecutar de arriba hacia abajo, por bloques (GO).
   Orden: 0 Base y tablas -> 1 Funcion -> 2 Triggers -> 3 Procedimientos
          -> 4 Vistas -> 5 ETL del DW -> 6 Seguridad -> 7 Indice y metricas
          -> 8 Pruebas (evidencia) -> 9 Backup y restore

   NOTAS IMPORTANTES
   - Sin tildes a proposito, para evitar problemas de codificacion en SSMS.
   - Este script NO fue ejecutado por quien lo redacto: pruebalo en tu servidor
     y ajusta lo que tu motor indique (version, rutas, nombres de columnas).
   - Asume que la tabla importada dbo.[DAT SALUD MENTAL - TAMIZAJE] existe con
     las columnas que usaste (Anio, NroMes, ubigeo, Departamento, Provincia,
     Distrito, Sexo, Etapa, GrupoTamizaje, DetalleTamizaje, Casos).
   - La fecha se castea con TRY_CAST: formato recomendado AAAA-MM-DD.
   ===================================================================== */

/* ---------------------------------------------------------------------
   0. BASE DE DATOS Y TABLAS (idempotente: se puede ejecutar mas de una vez)
   --------------------------------------------------------------------- */
IF DB_ID('BD_DataSalud_LaLibertad') IS NULL CREATE DATABASE BD_DataSalud_LaLibertad;
GO
USE BD_DataSalud_LaLibertad;
GO

IF OBJECT_ID('dbo.staging_atenciones_mental','U') IS NULL
CREATE TABLE dbo.staging_atenciones_mental (
    id_staging INT IDENTITY(1,1) PRIMARY KEY,
    Co_Establecimiento VARCHAR(50),
    Nom_Establecimiento VARCHAR(255),
    Fecha_Atencion VARCHAR(50),
    Edad VARCHAR(50),
    Sexo VARCHAR(20),
    Diagnostico VARCHAR(100),
    Ubigeo VARCHAR(10)
);
GO
-- Si tu staging ya existia con Sexo VARCHAR(10), ampliarlo para valores como 'Femenino'
ALTER TABLE dbo.staging_atenciones_mental ALTER COLUMN Sexo VARCHAR(20);
GO

IF OBJECT_ID('dbo.tbl_atenciones_salud_mental','U') IS NULL
CREATE TABLE dbo.tbl_atenciones_salud_mental (
    id_atencion INT IDENTITY(1,1) PRIMARY KEY,
    co_establecimiento VARCHAR(50) NOT NULL,
    nom_establecimiento VARCHAR(255),
    fecha_atencion DATE NOT NULL,
    edad INT CHECK (edad >= 0 AND edad <= 120),
    sexo CHAR(1),
    diagnostico VARCHAR(100) NOT NULL,
    ubigeo VARCHAR(10),
    fecha_carga DATETIME DEFAULT GETDATE()
);
GO

IF OBJECT_ID('dbo.tbl_cuarentena_atenciones','U') IS NULL
CREATE TABLE dbo.tbl_cuarentena_atenciones (
    id_cuarentena INT IDENTITY(1,1) PRIMARY KEY,
    co_establecimiento VARCHAR(50),
    fecha_atencion VARCHAR(50),
    edad VARCHAR(50),
    diagnostico VARCHAR(100),
    motivo_error VARCHAR(255),
    fecha_rechazo DATETIME DEFAULT GETDATE()
);
GO
IF COL_LENGTH('dbo.tbl_cuarentena_atenciones','lote_id') IS NULL
    ALTER TABLE dbo.tbl_cuarentena_atenciones ADD lote_id VARCHAR(50) NULL;
GO

IF OBJECT_ID('dbo.tbl_tamizajes_salud_mental_limpio','U') IS NULL
CREATE TABLE dbo.tbl_tamizajes_salud_mental_limpio (
    id_tamizaje INT IDENTITY(1,1) PRIMARY KEY,
    anio SMALLINT,
    nro_mes TINYINT,
    ubigeo VARCHAR(10),
    departamento VARCHAR(50),
    provincia VARCHAR(50),
    distrito VARCHAR(50),
    sexo VARCHAR(50),
    etapa VARCHAR(50),
    grupo_tamizaje VARCHAR(50),
    detalle_tamizaje VARCHAR(50),
    casos INT,
    fecha_carga DATETIME DEFAULT GETDATE()
);
GO

IF OBJECT_ID('dbo.tbl_cuarentena_tamizajes','U') IS NULL
CREATE TABLE dbo.tbl_cuarentena_tamizajes (
    id_cuarentena INT IDENTITY(1,1) PRIMARY KEY,
    anio VARCHAR(20),
    nro_mes VARCHAR(20),
    ubigeo VARCHAR(20),
    provincia VARCHAR(100),
    casos VARCHAR(20),
    motivo_error VARCHAR(255),
    lote_id VARCHAR(50),
    fecha_rechazo DATETIME DEFAULT GETDATE()
);
GO

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

-- Tabla de log del ETL (la exige la rubrica para el Data Warehouse)
IF OBJECT_ID('dbo.etl_log','U') IS NULL
CREATE TABLE dbo.etl_log (
    id_etl INT IDENTITY(1,1) PRIMARY KEY,
    ejecucion_id UNIQUEIDENTIFIER NOT NULL,
    etapa VARCHAR(60) NOT NULL,
    tabla_destino VARCHAR(100) NULL,
    filas_leidas INT NULL,
    filas_cargadas INT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'OK',
    detalle VARCHAR(1000) NULL,
    fecha_hora DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- Data Warehouse (modelo estrella Kimball)
IF OBJECT_ID('dbo.Dim_Ubicacion','U') IS NULL
CREATE TABLE dbo.Dim_Ubicacion (
    id_ubicacion INT IDENTITY(1,1) PRIMARY KEY,
    ubigeo VARCHAR(10), departamento VARCHAR(50), provincia VARCHAR(50), distrito VARCHAR(50)
);
IF OBJECT_ID('dbo.Dim_Tiempo','U') IS NULL
CREATE TABLE dbo.Dim_Tiempo (
    id_tiempo INT IDENTITY(1,1) PRIMARY KEY,
    anio SMALLINT, nro_mes TINYINT
);
IF OBJECT_ID('dbo.Dim_Perfil','U') IS NULL
CREATE TABLE dbo.Dim_Perfil (
    id_perfil INT IDENTITY(1,1) PRIMARY KEY,
    sexo VARCHAR(50), etapa VARCHAR(50), grupo_tamizaje VARCHAR(50), detalle_tamizaje VARCHAR(50)
);
IF OBJECT_ID('dbo.Fact_Tamizajes','U') IS NULL
CREATE TABLE dbo.Fact_Tamizajes (
    id_fact INT IDENTITY(1,1) PRIMARY KEY,
    id_ubicacion INT FOREIGN KEY REFERENCES dbo.Dim_Ubicacion(id_ubicacion),
    id_tiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(id_tiempo),
    id_perfil INT FOREIGN KEY REFERENCES dbo.Dim_Perfil(id_perfil),
    casos INT
);
GO

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

/* ---------------------------------------------------------------------
   4. VISTAS ANALITICAS (el analista solo vera estas, no las tablas base)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_tamizajes_por_provincia AS
SELECT provincia, etapa, SUM(casos) AS TotalCasos
FROM dbo.tbl_tamizajes_salud_mental_limpio
WHERE provincia IS NOT NULL AND provincia <> ''
GROUP BY provincia, etapa;
GO
CREATE OR ALTER VIEW dbo.vw_tamizajes_tendencia_temporal AS
SELECT anio, nro_mes, SUM(casos) AS TotalCasosMensuales
FROM dbo.tbl_tamizajes_salud_mental_limpio
GROUP BY anio, nro_mes;
GO

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

/* ---------------------------------------------------------------------
   6. SEGURIDAD: roles con minimo privilegio y segregacion de funciones
   Las vistas y procedimientos pertenecen a dbo, por lo que el encadenamiento de propiedad
   permite al analista leer las vistas sin tener acceso a las tablas base.
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID('Rol_Administrador_Salud') IS NULL CREATE ROLE Rol_Administrador_Salud;
IF DATABASE_PRINCIPAL_ID('Rol_Analista_Datos') IS NULL CREATE ROLE Rol_Analista_Datos;
IF DATABASE_PRINCIPAL_ID('Rol_Auditor') IS NULL CREATE ROLE Rol_Auditor;
GO

-- Se retiran los permisos amplios del script original
REVOKE CONTROL ON DATABASE::BD_DataSalud_LaLibertad FROM Rol_Administrador_Salud;
REVOKE SELECT ON dbo.tbl_tamizajes_salud_mental_limpio FROM Rol_Analista_Datos;
REVOKE SELECT ON dbo.tbl_tamizajes_salud_mental_limpio FROM Rol_Auditor;
GO

-- Administrador: opera y mantiene, pero NO puede alterar el log de auditoria
ALTER ROLE db_ddladmin ADD MEMBER Rol_Administrador_Salud;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO Rol_Administrador_Salud;
DENY INSERT, UPDATE, DELETE ON dbo.log_auditoria TO Rol_Administrador_Salud;
GO

-- Analista: solo vistas y modelo dimensional; sin acceso a tablas con detalle ni a logs
GRANT SELECT ON dbo.vw_tamizajes_por_provincia TO Rol_Analista_Datos;
GRANT SELECT ON dbo.vw_tamizajes_tendencia_temporal TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Ubicacion TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Tiempo TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Perfil TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Fact_Tamizajes TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_atenciones_salud_mental TO Rol_Analista_Datos;
DENY SELECT ON dbo.staging_atenciones_mental TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_cuarentena_tamizajes TO Rol_Analista_Datos;
DENY SELECT ON dbo.log_auditoria TO Rol_Analista_Datos;
GO

-- Auditor: solo lectura de log, cuarentena y log del ETL; no modifica nada
GRANT SELECT ON dbo.log_auditoria TO Rol_Auditor;
GRANT SELECT ON dbo.etl_log TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_tamizajes TO Rol_Auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO Rol_Auditor;
GO

-- Usuarios de prueba (sin login) para demostrar que cada rol falla donde debe
IF DATABASE_PRINCIPAL_ID('u_analista_test') IS NULL CREATE USER u_analista_test WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('u_auditor_test') IS NULL CREATE USER u_auditor_test WITHOUT LOGIN;
ALTER ROLE Rol_Analista_Datos ADD MEMBER u_analista_test;
ALTER ROLE Rol_Auditor ADD MEMBER u_auditor_test;
GO

/* ---------------------------------------------------------------------
   7. INDICE Y METRICAS ANTES/DESPUES
   Activa tambien el plan de ejecucion real (Ctrl+M en SSMS) y captura ambos planes.
   --------------------------------------------------------------------- */
DROP INDEX IF EXISTS IX_Tamizajes_Provincia_Anio ON dbo.tbl_tamizajes_salud_mental_limpio;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @prov VARCHAR(50) = (SELECT TOP 1 provincia FROM dbo.tbl_tamizajes_salud_mental_limpio
                             WHERE provincia IS NOT NULL ORDER BY provincia);
DECLARE @anio SMALLINT = (SELECT MAX(anio) FROM dbo.tbl_tamizajes_salud_mental_limpio);

PRINT '=== ANTES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT provincia, etapa, SUM(casos) AS total
FROM dbo.tbl_tamizajes_salud_mental_limpio
WHERE provincia = @prov AND anio = @anio
GROUP BY provincia, etapa;

CREATE NONCLUSTERED INDEX IX_Tamizajes_Provincia_Anio
ON dbo.tbl_tamizajes_salud_mental_limpio (provincia, anio) INCLUDE (casos, etapa);

PRINT '=== DESPUES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT provincia, etapa, SUM(casos) AS total
FROM dbo.tbl_tamizajes_salud_mental_limpio
WHERE provincia = @prov AND anio = @anio
GROUP BY provincia, etapa;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
-- Copia de la pestana Messages: "logical reads" y "CPU time / elapsed time" antes vs despues.

/* ---------------------------------------------------------------------
   8. PRUEBAS Y EVIDENCIA (capturas para el informe y la sustentacion)
   --------------------------------------------------------------------- */
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

-- 8.6 Roles: cada prueba debe mostrar "OK bloqueado" donde corresponde
EXECUTE AS USER = 'u_analista_test';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.tbl_atenciones_salud_mental;
    PRINT 'FALLO: el analista pudo leer la tabla base.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> tabla base): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.vw_tamizajes_por_provincia;   -- esto SI debe funcionar
REVERT;

EXECUTE AS USER = 'u_auditor_test';
BEGIN TRY
    DELETE FROM dbo.log_auditoria;
    PRINT 'FALLO: el auditor pudo borrar el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> borrar log): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.log_auditoria ORDER BY id_log DESC;   -- esto SI debe funcionar
REVERT;
GO

/* ---------------------------------------------------------------------
   9. POLITICA DE RESPALDO Y RESTORE PROBADO
   Politica: FULL semanal + DIFFERENTIAL diario, con CHECKSUM y verificacion.
   La carpeta debe existir y ser escribible por la cuenta del servicio de SQL Server.
   (SQL Server Express no tiene Agent: programa con Task Scheduler + sqlcmd.)
   --------------------------------------------------------------------- */
USE master;
GO
BACKUP DATABASE BD_DataSalud_LaLibertad
TO DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak'
WITH INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud FULL';
GO
-- (aqui pueden ocurrir cambios en la base; el diferencial solo guarda lo modificado desde el FULL)
BACKUP DATABASE BD_DataSalud_LaLibertad
TO DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud DIFF';
GO
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak' WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak' WITH CHECKSUM;
GO

-- Verifica los nombres logicos de archivos antes del restore:
RESTORE FILELISTONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak';
GO

-- Restore PROBADO en una base distinta (no pisa la original): FULL + DIFFERENTIAL
RESTORE DATABASE BD_DataSalud_LaLibertad_TEST
FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak'
WITH MOVE 'BD_DataSalud_LaLibertad'     TO 'C:\Public\BD_DataSalud_LaLibertad_TEST.mdf',
     MOVE 'BD_DataSalud_LaLibertad_log' TO 'C:\Public\BD_DataSalud_LaLibertad_TEST.ldf',
     NORECOVERY, REPLACE;
RESTORE DATABASE BD_DataSalud_LaLibertad_TEST
FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak'
WITH RECOVERY;
GO

-- Evidencia: los conteos deben ser iguales
SELECT
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad.dbo.tbl_tamizajes_salud_mental_limpio)      AS original_limpios,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad_TEST.dbo.tbl_tamizajes_salud_mental_limpio) AS restaurada_limpios,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad.dbo.Fact_Tamizajes)      AS original_hechos,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad_TEST.dbo.Fact_Tamizajes) AS restaurada_hechos;
GO
-- Cuando captures la evidencia: DROP DATABASE BD_DataSalud_LaLibertad_TEST;
-- Anota el RPO (perdida maxima aceptable = intervalo del DIFF) y el RTO (tiempo medido del restore).
```
