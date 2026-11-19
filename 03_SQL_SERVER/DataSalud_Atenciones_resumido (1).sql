-- DataSalud

-- 0. BASE DE DATOS Y TABLAS
IF DB_ID('BD_DataSalud_Atenciones') IS NULL CREATE DATABASE BD_DataSalud_Atenciones;
GO
USE BD_DataSalud_Atenciones;   -- USE = pone en uso esa base de datos
GO

-- ---- TABLA DE APOYO 1: ORIGEN (sala de espera) ----
-- Recibe el CSV tal cual viene, todo como texto (VARCHAR), asi la carga nunca falla.
-- Luego usp_cargar_atenciones la revisa y pasa solo lo bueno al modelo.
-- Se vacia antes de cada archivo nuevo (usp_limpiar_origen).
IF OBJECT_ID('dbo.origen_atenciones_diagnostico','U') IS NULL
CREATE TABLE dbo.origen_atenciones_diagnostico (
    id_origen    INT IDENTITY(1,1) NOT NULL,   -- numero que SQL Server asigna solo (1, 2, 3...)
    Anio         VARCHAR(50),
    NroMes       VARCHAR(50),
    ubigeo       VARCHAR(50),
    Departamento VARCHAR(100),
    Provincia    VARCHAR(100),
    Distrito     VARCHAR(100),
    Sexo         VARCHAR(50),
    Etapa        VARCHAR(50),
    Diagnostico  VARCHAR(100),
    Atendidos    VARCHAR(50),
    Atenciones   VARCHAR(50),
    CONSTRAINT PK_Origen_Atenciones PRIMARY KEY (id_origen)   -- llave primaria
);
GO

-- ---- CATALOGO 1: donde ocurrio la atencion ----
IF OBJECT_ID('dbo.Ubicacion','U') IS NULL
CREATE TABLE dbo.Ubicacion (
    id_ubicacion INT IDENTITY(1,1) NOT NULL,
    ubigeo       VARCHAR(20)  NOT NULL,
    departamento VARCHAR(100) NOT NULL,
    provincia    VARCHAR(100) NOT NULL,
    distrito     VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Ubicacion PRIMARY KEY (id_ubicacion),
    CONSTRAINT UQ_Ubicacion UNIQUE (ubigeo, departamento, provincia, distrito)
);
GO

-- ---- CATALOGO 2: sexo ('F', 'M' o 'No registrado') ----
IF OBJECT_ID('dbo.Genero','U') IS NULL
CREATE TABLE dbo.Genero (
    id_genero INT IDENTITY(1,1) NOT NULL,
    sexo      VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Genero PRIMARY KEY (id_genero),
    CONSTRAINT UQ_Genero UNIQUE (sexo)
);
GO

-- ---- CATALOGO 3: etapa de vida ('1 - 4', '5 - 9', ...) ----
IF OBJECT_ID('dbo.Rango_Edad','U') IS NULL
CREATE TABLE dbo.Rango_Edad (
    id_rango_edad INT IDENTITY(1,1) NOT NULL,
    etapa         VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Rango_Edad PRIMARY KEY (id_rango_edad),
    CONSTRAINT UQ_Rango_Edad UNIQUE (etapa)
);
GO

-- ---- CATALOGO 4: tipo de diagnostico ----
IF OBJECT_ID('dbo.Diagnostico','U') IS NULL
CREATE TABLE dbo.Diagnostico (
    id_diagnostico INT IDENTITY(1,1) NOT NULL,
    diagnostico    VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Diagnostico PRIMARY KEY (id_diagnostico),
    CONSTRAINT UQ_Diagnostico UNIQUE (diagnostico)
);
GO

-- ---- TABLA PRINCIPAL (hechos): une los 4 catalogos con FOREIGN KEY ----
-- lote_id dice de que carga viene cada fila (sirve para cuadrar sumas).
IF OBJECT_ID('dbo.Atencion_Diagnostico','U') IS NULL
CREATE TABLE dbo.Atencion_Diagnostico (
    id_atencion_diagnostico INT IDENTITY(1,1) NOT NULL,
    id_ubicacion   INT NOT NULL,
    id_genero      INT NOT NULL,
    id_rango_edad  INT NOT NULL,
    id_diagnostico INT NOT NULL,
    anio       SMALLINT NOT NULL,
    nro_mes    TINYINT  NOT NULL,
    atendidos  INT NOT NULL,
    atenciones INT NOT NULL,
    fecha_carga DATETIME NOT NULL DEFAULT GETDATE(),   -- fecha automatica
    lote_id    VARCHAR(50) NULL,
    CONSTRAINT PK_Atencion_Diagnostico PRIMARY KEY (id_atencion_diagnostico),
    CONSTRAINT FK_Atencion_Ubicacion   FOREIGN KEY (id_ubicacion)   REFERENCES dbo.Ubicacion(id_ubicacion),
    CONSTRAINT FK_Atencion_Genero      FOREIGN KEY (id_genero)      REFERENCES dbo.Genero(id_genero),
    CONSTRAINT FK_Atencion_RangoEdad   FOREIGN KEY (id_rango_edad)  REFERENCES dbo.Rango_Edad(id_rango_edad),
    CONSTRAINT FK_Atencion_Diagnostico FOREIGN KEY (id_diagnostico) REFERENCES dbo.Diagnostico(id_diagnostico),
    -- una misma combinacion no puede repetirse
    CONSTRAINT UQ_Atencion_Diagnostico UNIQUE
        (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes)
);
GO

-- ---- TABLA DE APOYO 2: CUARENTENA (filas rechazadas) ----
-- Aqui caen las filas con errores (mes 15, numeros negativos, vacios) o repetidas,
-- con el motivo escrito. Sirve para saber que corregir en el Excel. Todo en texto, tal como llego.
IF OBJECT_ID('dbo.tbl_cuarentena_atenciones','U') IS NULL
CREATE TABLE dbo.tbl_cuarentena_atenciones (
    id_cuarentena INT IDENTITY(1,1) NOT NULL,
    anio        VARCHAR(50),
    nro_mes     VARCHAR(50),
    ubigeo      VARCHAR(50),
    provincia   VARCHAR(100),
    diagnostico VARCHAR(100),
    atendidos   VARCHAR(50),
    atenciones  VARCHAR(50),
    motivo_error VARCHAR(255) NOT NULL,
    lote_id      VARCHAR(50),
    fecha_rechazo DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Cuarentena_Atenciones PRIMARY KEY (id_cuarentena)
);
GO

-- ---- TABLA DE APOYO 3: LOG DE AUDITORIA ----
-- Libro de registro: quien hizo que y cuando. Lo escriben los triggers y los procedimientos.
IF OBJECT_ID('dbo.log_auditoria','U') IS NULL
CREATE TABLE dbo.log_auditoria (
    id_log      INT IDENTITY(1,1) NOT NULL,
    tabla       VARCHAR(100) NOT NULL,
    operacion   VARCHAR(20)  NOT NULL,      -- INSERT, UPDATE, DELETE, INGESTA, CARGA_CSV, ERROR...
    registro_id INT NULL,
    usuario     VARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    fecha_hora  DATETIME2    NOT NULL DEFAULT SYSDATETIME(),
    valor_anterior VARCHAR(MAX) NULL,
    valor_nuevo    VARCHAR(MAX) NULL,
    lote_id     VARCHAR(50)  NULL,
    detalle     VARCHAR(1000) NULL,
    CONSTRAINT PK_Log_Auditoria PRIMARY KEY (id_log)
);
GO

-- ---- TABLA DE APOYO 4: LOG DEL ETL ----
-- Boleta del proceso: cuantas filas paso por cada paso (lectura, cuarentena, catalogos, hechos,
-- warehouse) y si las sumas cuadraron.
IF OBJECT_ID('dbo.etl_log','U') IS NULL
CREATE TABLE dbo.etl_log (
    id_etl         INT IDENTITY(1,1) NOT NULL,
    ejecucion_id   UNIQUEIDENTIFIER NOT NULL,
    etapa          VARCHAR(60) NOT NULL,
    tabla_destino  VARCHAR(100) NULL,
    filas_leidas   INT NULL,
    filas_cargadas INT NULL,
    estado         VARCHAR(20) NOT NULL DEFAULT 'OK',
    detalle        VARCHAR(1000) NULL,
    fecha_hora     DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Etl_Log PRIMARY KEY (id_etl)
);
GO

-- 1. FUNCIONES
-- Promedio de atenciones por persona atendida (si atendidos = 0 no se divide: devuelve 0)
CREATE OR ALTER FUNCTION dbo.fn_promedio_atenciones (@atendidos INT, @atenciones INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN CASE
        WHEN @atendidos IS NULL OR @atenciones IS NULL THEN 0
        WHEN @atendidos = 0 THEN 0                       -- evita dividir entre cero
        ELSE CAST(@atenciones AS DECIMAL(10,2)) / @atendidos
    END;
END;
GO

-- Etiqueta clara segun si hubo seguimiento o no
CREATE OR ALTER FUNCTION dbo.fn_etiqueta_seguimiento (@atendidos INT, @atenciones INT)
RETURNS VARCHAR(40)
AS
BEGIN
    RETURN CASE
        WHEN @atendidos IS NULL OR @atenciones IS NULL THEN 'No registrado'
        WHEN @atendidos = 0 AND @atenciones = 0 THEN 'Sin actividad'
        WHEN @atendidos = 0 THEN 'Solo seguimiento'          -- hubo atencion, pero no hay atendidos nuevos
        WHEN @atenciones > @atendidos THEN 'Con seguimiento' -- mas de una atencion por persona
        ELSE 'Atencion unica'
    END;
END;
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

-- 4. VISTAS
-- 4.1 Totales por departamento, provincia y diagnostico
CREATE OR ALTER VIEW dbo.vw_total_por_ubicacion_diagnostico AS
SELECT u.departamento, u.provincia, d.diagnostico,
       SUM(f.atendidos)  AS total_atendidos,
       SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
GROUP BY u.departamento, u.provincia, d.diagnostico;
GO

-- 4.2 Evolucion por anio y mes
CREATE OR ALTER VIEW dbo.vw_evolucion_mensual AS
SELECT anio, nro_mes,
       SUM(atendidos)  AS total_atendidos,
       SUM(atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico
GROUP BY anio, nro_mes;
GO

-- 4.3 Por sexo, etapa y diagnostico (con el promedio de la funcion)
CREATE OR ALTER VIEW dbo.vw_por_sexo_etapa_diagnostico AS
SELECT g.sexo, e.etapa, d.diagnostico,
       SUM(f.atendidos)  AS total_atendidos,
       SUM(f.atenciones) AS total_atenciones,
       dbo.fn_promedio_atenciones(SUM(f.atendidos), SUM(f.atenciones)) AS promedio_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Genero g ON g.id_genero = f.id_genero
JOIN dbo.Rango_Edad e ON e.id_rango_edad = f.id_rango_edad
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
GROUP BY g.sexo, e.etapa, d.diagnostico;
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

-- 5.2 DATA WAREHOUSE (crear): 3 tablas resumen en el esquema dw para Power BI.
--     Aqui solo se crea la estructura; se llena al final con usp_cargar_warehouse (paso 10.5).
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
GO

-- ---- TABLA RESUMEN 1: Tiempo x Diagnostico ----
-- Para que sirve: responde "como evoluciona cada tipo de caso mes a mes?".
-- En Power BI: grafico de lineas o columnas por anio/mes con el diagnostico como filtro.
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

-- ---- TABLA RESUMEN 2: Ubicacion ----
-- Para que sirve: responde "donde se concentran los casos?". Llega hasta provincia (no distrito)
-- para que la tabla sea corta. En Power BI: mapa o barras por departamento/provincia.
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

-- ---- TABLA RESUMEN 3: Perfil (sexo y etapa) ----
-- Para que sirve: responde "a quienes afecta mas?". En Power BI: barras por sexo y etapa de vida.
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

-- 5.3 usp_reiniciar_datos: borra los datos de prueba (exige @confirmar = 'SI'). Usar solo antes de la primera carga real.
CREATE OR ALTER PROCEDURE dbo.usp_reiniciar_datos
    @confirmar   VARCHAR(2) = 'NO',
    @borrar_logs BIT        = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @confirmar <> 'SI'
        THROW 50040, 'Reinicio cancelado: este procedimiento BORRA datos. Para continuar usa @confirmar = ''SI''.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;

        DELETE FROM dw.Resumen_Perfil;
        DELETE FROM dw.Resumen_Ubicacion;
        DELETE FROM dw.Resumen_Tiempo_Diagnostico;
        DELETE FROM dbo.Atencion_Diagnostico;      -- primero los hechos (tienen las llaves foraneas)
        DELETE FROM dbo.Ubicacion;                 -- luego los catalogos
        DELETE FROM dbo.Genero;
        DELETE FROM dbo.Rango_Edad;
        DELETE FROM dbo.Diagnostico;
        DELETE FROM dbo.tbl_cuarentena_atenciones;
        DELETE FROM dbo.origen_atenciones_diagnostico;
        IF @borrar_logs = 1
        BEGIN
            DELETE FROM dbo.etl_log;
            DELETE FROM dbo.log_auditoria;
        END;   -- el punto y coma es obligatorio: ENABLE TRIGGER exige que la instruccion anterior este cerrada

        ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
        COMMIT TRANSACTION;

        INSERT INTO dbo.log_auditoria (tabla, operacion, detalle)
        VALUES ('(todas)', 'REINICIO', CONCAT('datos borrados; logs borrados=', @borrar_logs));
        PRINT 'Datos reiniciados. La estructura sigue intacta.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- tambien deja el trigger como estaba
        THROW;
    END CATCH
END;
GO

-- 6. SEGURIDAD (roles con el minimo de permisos)
IF DATABASE_PRINCIPAL_ID('Rol_Administrador') IS NULL CREATE ROLE Rol_Administrador;
IF DATABASE_PRINCIPAL_ID('Rol_Analista')      IS NULL CREATE ROLE Rol_Analista;
IF DATABASE_PRINCIPAL_ID('Rol_Auditor')       IS NULL CREATE ROLE Rol_Auditor;
GO

-- Administrador: usa todo, pero NO puede modificar ni borrar el log de auditoria
-- (los triggers siguen pudiendo escribir en el log porque son de dbo)
ALTER ROLE db_ddladmin ADD MEMBER Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dw TO Rol_Administrador;
DENY INSERT, UPDATE, DELETE ON dbo.log_auditoria TO Rol_Administrador;
GO

-- Analista: solo SELECT en vistas, warehouse y tablas del modelo final
GRANT SELECT ON dbo.vw_total_por_ubicacion_diagnostico TO Rol_Analista;
GRANT SELECT ON dbo.vw_evolucion_mensual TO Rol_Analista;
GRANT SELECT ON dbo.vw_por_sexo_etapa_diagnostico TO Rol_Analista;
GRANT SELECT ON SCHEMA::dw TO Rol_Analista;
GRANT SELECT ON dbo.Ubicacion TO Rol_Analista;
GRANT SELECT ON dbo.Genero TO Rol_Analista;
GRANT SELECT ON dbo.Rango_Edad TO Rol_Analista;
GRANT SELECT ON dbo.Diagnostico TO Rol_Analista;
GRANT SELECT ON dbo.Atencion_Diagnostico TO Rol_Analista;
DENY SELECT ON dbo.origen_atenciones_diagnostico TO Rol_Analista;
DENY SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Analista;
DENY SELECT ON dbo.log_auditoria TO Rol_Analista;
DENY SELECT ON dbo.etl_log TO Rol_Analista;
GO

-- Auditor: solo lee log, etl_log y cuarentena; no modifica nada
GRANT SELECT ON dbo.log_auditoria TO Rol_Auditor;
GRANT SELECT ON dbo.etl_log TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO Rol_Auditor;
GO

-- Usuarios de prueba sin login (sirven solo para demostrar los permisos)
IF DATABASE_PRINCIPAL_ID('u_analista_test') IS NULL CREATE USER u_analista_test WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('u_auditor_test')  IS NULL CREATE USER u_auditor_test WITHOUT LOGIN;
ALTER ROLE Rol_Analista ADD MEMBER u_analista_test;
ALTER ROLE Rol_Auditor  ADD MEMBER u_auditor_test;
GO

-- 7. INDICE Y PRUEBA DE VELOCIDAD (crea ~72 mil filas de prueba en provincia 'PRUEBA' y las borra al final;
--    CHECKPOINT y DBCC DROPCLEANBUFFERS requieren ser sysadmin)
-- 7.0 Datos de volumen temporales
DROP INDEX IF EXISTS IX_Atencion_Anio_Diagnostico ON dbo.Atencion_Diagnostico;
GO
-- Catalogos reales (solo si aun no existen)
INSERT INTO dbo.Genero (sexo)
SELECT v.x FROM (VALUES ('F'),('M')) v(x) WHERE NOT EXISTS (SELECT 1 FROM dbo.Genero WHERE sexo = v.x);
INSERT INTO dbo.Rango_Edad (etapa)
SELECT v.x FROM (VALUES ('1 - 4'),('5 - 9'),('10 - 11'),('12 - 14'),('15 - 17')) v(x)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Rango_Edad WHERE etapa = v.x);
INSERT INTO dbo.Diagnostico (diagnostico)
SELECT v.x FROM (VALUES ('ABUSO PSICOLOGICO'),('ABUSO FISICO'),('ABUSO SEXUAL'),('NEGLIGENCIA')) v(x)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Diagnostico WHERE diagnostico = v.x);

-- 50 ubicaciones de prueba
INSERT INTO dbo.Ubicacion (ubigeo, departamento, provincia, distrito)
SELECT CONCAT('9', RIGHT(CONCAT('00000', n), 5)), 'PRUEBA', 'PRUEBA', CONCAT('PRUEBA ', n)
FROM (SELECT TOP 50 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) t;

-- Se apaga el trigger de auditoria solo durante esta carga masiva
DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;

INSERT INTO dbo.Atencion_Diagnostico
       (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes, atendidos, atenciones, lote_id)
SELECT u.id_ubicacion, g.id_genero, e.id_rango_edad, d.id_diagnostico, a.anio, m.mes,
       (u.id_ubicacion + m.mes) % 5, (u.id_ubicacion + m.mes) % 5 + 1, 'LOTE_VOLUMEN'
FROM dbo.Ubicacion u
CROSS JOIN dbo.Genero g
CROSS JOIN dbo.Rango_Edad e
CROSS JOIN dbo.Diagnostico d
CROSS JOIN (VALUES (2017),(2018),(2019)) a(anio)
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) m(mes)
WHERE u.provincia = 'PRUEBA';

ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
GO

-- 7.1 Medicion ANTES y DESPUES del indice
-- (activa tambien el plan de ejecucion real con Ctrl+M y guarda ambos planes)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @anio SMALLINT = 2018;
DECLARE @diag VARCHAR(100) = 'ABUSO PSICOLOGICO';

PRINT '=== ANTES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT d.diagnostico, SUM(f.atendidos) AS total_atendidos, SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
WHERE f.anio = @anio AND d.diagnostico = @diag
GROUP BY d.diagnostico;

CREATE NONCLUSTERED INDEX IX_Atencion_Anio_Diagnostico
ON dbo.Atencion_Diagnostico (anio, id_diagnostico) INCLUDE (atendidos, atenciones);

PRINT '=== DESPUES DEL INDICE ===';
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SELECT d.diagnostico, SUM(f.atendidos) AS total_atendidos, SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
WHERE f.anio = @anio AND d.diagnostico = @diag
GROUP BY d.diagnostico;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
-- Copia de la pestana Messages: "logical reads" y "CPU time / elapsed time", antes vs despues.

-- 7.2 Limpieza: se borran los datos de prueba (el indice se queda)
DISABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
DELETE f FROM dbo.Atencion_Diagnostico f
JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
WHERE u.provincia = 'PRUEBA';
ENABLE TRIGGER dbo.trg_audit_atencion_diagnostico ON dbo.Atencion_Diagnostico;
DELETE FROM dbo.Ubicacion WHERE provincia = 'PRUEBA';
GO

-- 8. PRUEBAS
-- 8.1 Funciones
SELECT dbo.fn_etiqueta_seguimiento(0, 1)  AS solo_seguimiento,
       dbo.fn_etiqueta_seguimiento(2, 7)  AS con_seguimiento,
       dbo.fn_etiqueta_seguimiento(3, 3)  AS atencion_unica,
       dbo.fn_etiqueta_seguimiento(NULL, 1) AS nulo,
       dbo.fn_promedio_atenciones(2, 7)   AS promedio,
       dbo.fn_promedio_atenciones(0, 5)   AS sin_dividir_entre_cero;
GO

-- 8.2 Carga con datos de prueba
-- Esperado: 8 leidos, 5 cargados, 3 rechazados (duplicado, atendidos negativo, mes 15)
TRUNCATE TABLE dbo.origen_atenciones_diagnostico;
INSERT INTO dbo.origen_atenciones_diagnostico
 (Anio, NroMes, ubigeo, Departamento, Provincia, Distrito, Sexo, Etapa, Diagnostico, Atendidos, Atenciones) VALUES
 ('2017','1','30401','APURIMAC','AYMARAES','CHALHUANCA','F','1 - 4','ABUSO PSICOLOGICO','0','1'),   -- valida
 ('2017','1','30401','APURIMAC','AYMARAES','CHALHUANCA','F','1 - 4','ABUSO PSICOLOGICO','0','1'),   -- duplicado
 ('2017','1','30401','APURIMAC','AYMARAES','CHALHUANCA','M','1 - 4','NEGLIGENCIA','0','1'),         -- valida
 ('2017','1','110101','ICA','ICA','ICA','M','5 - 9','NEGLIGENCIA','1','1'),                          -- valida
 ('2017','1','210101','PUNO','PUNO','PUNO','F','15 - 17','ABUSO SEXUAL','1','2'),                    -- valida
 ('2017','2','210101','PUNO','PUNO','PUNO','F','15 - 17','ABUSO FISICO','-5','1'),                   -- dato negativo
 ('2017','15','210101','PUNO','PUNO','PUNO','M','15 - 17','ABUSO PSICOLOGICO','1','1'),             -- mes invalido
 ('2017','2','30401','APURIMAC','AYMARAES','','','12 - 14','ABUSO PSICOLOGICO','0','1');            -- valida (vacios -> No registrado)
GO
EXEC dbo.usp_cargar_atenciones @lote_id = 'LOTE_PRUEBA_01';
SELECT * FROM dbo.Atencion_Diagnostico;
SELECT * FROM dbo.tbl_cuarentena_atenciones WHERE lote_id = 'LOTE_PRUEBA_01';
SELECT * FROM dbo.vw_por_sexo_etapa_diagnostico;
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

-- 8.5 ETL completo con un lote nuevo (en la tabla de origen solo debe estar ese lote)
-- Esperado: 3 leidos, 2 cargados, 1 rechazado (mes 0) y cuadre OK
TRUNCATE TABLE dbo.origen_atenciones_diagnostico;
INSERT INTO dbo.origen_atenciones_diagnostico
 (Anio, NroMes, ubigeo, Departamento, Provincia, Distrito, Sexo, Etapa, Diagnostico, Atendidos, Atenciones) VALUES
 ('2017','3','30401','APURIMAC','AYMARAES','CHALHUANCA','F','1 - 4','ABUSO PSICOLOGICO','2','7'),
 ('2017','3','210101','PUNO','PUNO','PUNO','F','15 - 17','ABUSO PSICOLOGICO','2','7'),
 ('2017','0','210101','PUNO','PUNO','PUNO','M','15 - 17','ABUSO FISICO','1','1');   -- mes invalido
GO
EXEC dbo.usp_etl_atenciones @lote_id = 'LOTE_ETL_01';
SELECT * FROM dbo.etl_log ORDER BY id_etl DESC;
SELECT * FROM dbo.tbl_cuarentena_atenciones WHERE lote_id = 'LOTE_ETL_01';
GO

-- 8.6 Warehouse (probado con los datos de prueba; en el bloque 10 se vuelve a ejecutar con los reales)
-- Esperado: las 3 tablas con filas y la ultima linea de etl_log 'WAREHOUSE_CUADRE' con 'OK'
EXEC dbo.usp_cargar_warehouse;
SELECT * FROM dw.Resumen_Tiempo_Diagnostico ORDER BY anio, nro_mes, diagnostico;
SELECT * FROM dw.Resumen_Ubicacion ORDER BY departamento, provincia, diagnostico;
SELECT * FROM dw.Resumen_Perfil ORDER BY sexo, etapa, diagnostico;
SELECT TOP 5 * FROM dbo.etl_log ORDER BY id_etl DESC;
GO

-- 8.7 Roles: cada prueba debe mostrar "OK bloqueado" donde corresponde
EXECUTE AS USER = 'u_analista_test';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.origen_atenciones_diagnostico;
    PRINT 'FALLO: el analista pudo leer la tabla de origen.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> origen): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.log_auditoria;
    PRINT 'FALLO: el analista pudo leer el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> log_auditoria): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.vw_evolucion_mensual;   -- esto SI debe funcionar
SELECT TOP 5 * FROM dw.Resumen_Ubicacion;       -- esto SI debe funcionar
REVERT;

EXECUTE AS USER = 'u_auditor_test';
BEGIN TRY
    DELETE FROM dbo.log_auditoria;
    PRINT 'FALLO: el auditor pudo borrar el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> borrar log): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.Atencion_Diagnostico;
    PRINT 'FALLO: el auditor pudo leer la tabla de hechos.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> tabla de hechos): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.log_auditoria ORDER BY id_log DESC;   -- esto SI debe funcionar
REVERT;
GO

-- 9. RESPALDO Y RESTAURACION (FULL + DIFFERENTIAL). La carpeta debe existir y ser escribible por el servicio de SQL Server.
USE master;
GO
BACKUP DATABASE BD_DataSalud_Atenciones
TO DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak'
WITH INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud Atenciones FULL';
GO
-- (aqui pueden hacerse cambios; el diferencial guarda solo lo cambiado desde el FULL)
BACKUP DATABASE BD_DataSalud_Atenciones
TO DISK = 'C:\Public\BD_DataSalud_Atenciones_DIFF.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud Atenciones DIFF';
GO

-- Verificar que los archivos no estan danados
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak' WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_DIFF.bak' WITH CHECKSUM;
GO

-- Ver los nombres internos de archivos (se usan en MOVE)
RESTORE FILELISTONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak';
GO

-- Restaurar en una base distinta (_TEST) para no pisar la original: primero FULL, luego DIFF
RESTORE DATABASE BD_DataSalud_Atenciones_TEST
FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak'
WITH MOVE 'BD_DataSalud_Atenciones'     TO 'C:\Public\BD_DataSalud_Atenciones_TEST.mdf',
     MOVE 'BD_DataSalud_Atenciones_log' TO 'C:\Public\BD_DataSalud_Atenciones_TEST.ldf',
     NORECOVERY, REPLACE;
RESTORE DATABASE BD_DataSalud_Atenciones_TEST
FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_DIFF.bak'
WITH RECOVERY;
GO

-- Evidencia: los conteos deben ser iguales en la original y en la restaurada
SELECT
  (SELECT COUNT(*) FROM BD_DataSalud_Atenciones.dbo.Atencion_Diagnostico)      AS original_hechos,
  (SELECT COUNT(*) FROM BD_DataSalud_Atenciones_TEST.dbo.Atencion_Diagnostico) AS restaurada_hechos,
  (SELECT COUNT(*) FROM BD_DataSalud_Atenciones.dbo.Ubicacion)      AS original_ubicaciones,
  (SELECT COUNT(*) FROM BD_DataSalud_Atenciones_TEST.dbo.Ubicacion) AS restaurada_ubicaciones;
GO
-- Cuando captures la evidencia:  DROP DATABASE BD_DataSalud_Atenciones_TEST;
-- Anota el RPO (perdida maxima aceptable = cada cuanto haces el DIFF) y el RTO (tiempo que tardo el restore).

-- 10. IMPORTAR LOS DATOS REALES + WAREHOUSE (ejecutar aparte, despues de los bloques 0 al 9)
USE BD_DataSalud_Atenciones;
GO

-- Antes de importar: el Excel debe tener 11 columnas en este orden: Anio, NroMes, ubigeo, Departamento,
-- Provincia, Distrito, Sexo, Etapa, Diagnostico, Atendidos, Atenciones (fila 1 = encabezados). Guardalo como
-- CSV UTF-8 en una carpeta del equipo de SQL Server y revisalo con el Bloc de notas (separador y Etapa sin fechas).
-- Cada archivo se carga con su propio lote que empiece por LOTE_REAL (LOTE_REAL_01, LOTE_REAL_02...).

-- 10.1 Borrar los datos de PRUEBA (solo la primera vez; si ya hay datos reales no borra nada)
IF EXISTS (SELECT 1 FROM dbo.Atencion_Diagnostico WHERE lote_id LIKE 'LOTE_REAL%')
    PRINT 'Ya hay datos reales cargados. No se borra nada.';
ELSE
    EXEC dbo.usp_reiniciar_datos @confirmar = 'SI';
GO

-- 10.2 Vaciar la sala de espera y cargar el CSV  (CAMBIA SOLO LA RUTA)
EXEC dbo.usp_limpiar_origen;
GO
-- OPCION A (recomendada): el procedimiento revisa ruta y separador, y luego ejecuta el BULK INSERT por dentro.
EXEC dbo.usp_cargar_csv @ruta = N'C:\DATOS\DAT SALUD MENTAL - MAMIS.csv';
-- Si tu CSV usa punto y coma:   EXEC dbo.usp_cargar_csv @ruta = N'C:\DATOS\archivo.csv', @separador = ';';
-- Si hay textos con comas dentro (SQL Server 2017+):  agrega  , @con_comillas = 1
GO

-- OPCION B: el comando BULK INSERT directo, a la vista (hace lo mismo que la opcion A, sin las revisiones).
-- Ejecuta SOLO UNA de las dos opciones. Para usar esta, quita los -- de las 3 lineas de abajo.
-- BULK INSERT dbo.vw_carga_origen
-- FROM 'C:\DATOS\DAT SALUD MENTAL - MAMIS.csv'
-- WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001', TABLOCK);
-- GO

-- 10.3 REVISAR que el archivo es el correcto antes de procesarlo: filas = ultima fila del Excel - 1 y solo los anios,
-- diagnosticos, sexos y etapas esperados. Si las columnas estan corridas: EXEC dbo.usp_limpiar_origen; y corrige el CSV.
SELECT COUNT(*) AS filas_en_origen FROM dbo.origen_atenciones_diagnostico;
SELECT TOP 10 * FROM dbo.origen_atenciones_diagnostico ORDER BY id_origen;
SELECT Anio, COUNT(*) AS filas FROM dbo.origen_atenciones_diagnostico GROUP BY Anio ORDER BY Anio;
SELECT Diagnostico, COUNT(*) AS filas FROM dbo.origen_atenciones_diagnostico GROUP BY Diagnostico ORDER BY Diagnostico;
SELECT Sexo, COUNT(*) AS filas FROM dbo.origen_atenciones_diagnostico GROUP BY Sexo ORDER BY Sexo;
SELECT Etapa, COUNT(*) AS filas FROM dbo.origen_atenciones_diagnostico GROUP BY Etapa ORDER BY Etapa;
GO

-- 10.4 Limpiar y cargar al modelo (ETL)  (cambia el lote en cada archivo: LOTE_REAL_01, LOTE_REAL_02...)
-- Nota: cada fila cargada deja un registro en log_auditoria (trigger), por eso con muchas filas puede tardar.
EXEC dbo.usp_etl_atenciones @lote_id = 'LOTE_REAL_01';
GO
-- Todo bien si la primera fila es etapa '5_CUADRE' con estado OK y detalle que empieza con 'OK.'
SELECT TOP 10 * FROM dbo.etl_log ORDER BY id_etl DESC;
-- Filas rechazadas por motivo (si "Duplicado dentro del lote" sale con muchas filas, revisa el Excel)
SELECT motivo_error, COUNT(*) AS filas
FROM dbo.tbl_cuarentena_atenciones
WHERE lote_id = 'LOTE_REAL_01'
GROUP BY motivo_error
ORDER BY filas DESC;
GO

-- 10.5 DATA WAREHOUSE (ejecutar): al final, despues de importar todos los archivos y con el cuadre del ETL en OK.
EXEC dbo.usp_cargar_warehouse;
GO
SELECT (SELECT COUNT(*) FROM dw.Resumen_Tiempo_Diagnostico) AS filas_tiempo_diagnostico,
       (SELECT COUNT(*) FROM dw.Resumen_Ubicacion)          AS filas_ubicacion,
       (SELECT COUNT(*) FROM dw.Resumen_Perfil)             AS filas_perfil;
SELECT TOP 10 * FROM dw.Resumen_Tiempo_Diagnostico ORDER BY anio, nro_mes, diagnostico;
GO

-- 10.6 CONSULTAS PARA EL INFORME
-- A) Total por anio y diagnostico
SELECT anio, diagnostico, SUM(total_atendidos) AS atendidos, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Tiempo_Diagnostico
GROUP BY anio, diagnostico
ORDER BY anio, diagnostico;

-- B) Los 10 departamentos con mas atenciones (todos los anios)
SELECT TOP 10 departamento, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Ubicacion
GROUP BY departamento
ORDER BY atenciones DESC;

-- C) Por sexo y etapa de vida
SELECT sexo, etapa, SUM(total_atendidos) AS atendidos, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Perfil
GROUP BY sexo, etapa
ORDER BY sexo, etapa;

-- D) Evolucion mensual total
SELECT * FROM dbo.vw_evolucion_mensual ORDER BY anio, nro_mes;
GO

-- 10.7 POWER BI: Obtener datos > SQL Server > base BD_DataSalud_Atenciones > tablas del esquema dw.
