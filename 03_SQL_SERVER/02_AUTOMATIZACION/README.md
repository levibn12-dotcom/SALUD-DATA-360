# 02_AUTOMATIZACION - Carga, limpieza y ETL

Procedimientos que automatizan el camino del dato: **CSV -> tabla de origen -> limpieza -> catalogos y hechos -> warehouse**. Lo que viene mal se manda a cuarentena con el motivo y nada se borra en silencio.

## Archivos

| Archivo | Que hace |
|---|---|
| `01_carga_atenciones.sql` | `usp_cargar_atenciones`: limpia la tabla de origen (espacios, conversiones, vacios), manda filas malas o repetidas a cuarentena, completa los catalogos y llena la tabla de hechos. Clave de fila: anio + mes + ubicacion + sexo + etapa + diagnostico. |
| `02_carga_csv.sql` | `usp_limpiar_origen` (vacia el origen), la vista `vw_carga_origen` y `usp_cargar_csv`, que revisa que el archivo exista y ejecuta el `BULK INSERT`. |
| `03_etl.sql` | `usp_etl_atenciones`: ejecuta la carga paso a paso, deja huella en `etl_log` y verifica que **origen = cargado + cuarentena**. |
| `04_warehouse_carga.sql` | `usp_cargar_warehouse`: reconstruye las 3 tablas resumen y comprueba que sumen lo mismo que la tabla de hechos. Se ejecuta **al final**, despues de importar los datos. |
| `05_reiniciar_datos.sql` | `usp_reiniciar_datos`: borra los datos de prueba para empezar limpio (exige `@confirmar = 'SI'`). |
| `06_pruebas_carga.sql` | Pruebas con datos de ejemplo: carga con filas validas, duplicada, negativa y mes 15; ETL completo; y warehouse. |
| `07_importar_datos_reales.sql` | **Importacion de los CSV reales** paso a paso (borrar pruebas, cargar CSV, revisar, ETL, warehouse). Incluye el comando `BULK INSERT` directo como opcion B. |

## Antes de importar un Excel

1. El Excel debe tener 11 columnas, en este orden: `Anio, NroMes, ubigeo, Departamento, Provincia, Distrito, Sexo, Etapa, Diagnostico, Atendidos, Atenciones` (fila 1 = encabezados).
2. Guardarlo como **CSV UTF-8 (delimitado por comas)** en una carpeta del equipo donde corre SQL Server, con permiso de lectura para el servicio de SQL Server.
3. Revisarlo con el Bloc de notas (separador y que `Etapa` no se haya convertido en fecha).
4. Un archivo a la vez, cada uno con su lote (`LOTE_REAL_01`, `LOTE_REAL_02`...).

Las rutas `C:\Public\` y `C:\DATOS\` de los archivos son de ejemplo: cambialas por las de tu equipo.

## Codigo

### `01_carga_atenciones.sql`

`usp_cargar_atenciones`: limpia la tabla de origen (espacios, conversiones, vacios), manda filas malas o repetidas a cuarentena, completa los catalogos y llena la tabla de hechos. Clave de fila: anio + mes + ubicacion + sexo + etapa + diagnostico.

```sql
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
```

### `02_carga_csv.sql`

`usp_limpiar_origen` (vacia el origen), la vista `vw_carga_origen` y `usp_cargar_csv`, que revisa que el archivo exista y ejecuta el `BULK INSERT`.

```sql
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
```

### `03_etl.sql`

`usp_etl_atenciones`: ejecuta la carga paso a paso, deja huella en `etl_log` y verifica que **origen = cargado + cuarentena**.

```sql
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
```

### `04_warehouse_carga.sql`

`usp_cargar_warehouse`: reconstruye las 3 tablas resumen y comprueba que sumen lo mismo que la tabla de hechos. Se ejecuta **al final**, despues de importar los datos.

```sql
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
```

### `05_reiniciar_datos.sql`

`usp_reiniciar_datos`: borra los datos de prueba para empezar limpio (exige `@confirmar = 'SI'`).

```sql
-- 02_AUTOMATIZACION/05_reiniciar_datos.sql

USE BD_DataSalud_Atenciones;
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
```

### `06_pruebas_carga.sql`

Pruebas con datos de ejemplo: carga con filas validas, duplicada, negativa y mes 15; ETL completo; y warehouse.

```sql
-- 02_AUTOMATIZACION/06_pruebas_carga.sql

USE BD_DataSalud_Atenciones;
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
```

### `07_importar_datos_reales.sql`

**Importacion de los CSV reales** paso a paso (borrar pruebas, cargar CSV, revisar, ETL, warehouse). Incluye el comando `BULK INSERT` directo como opcion B.

```sql
-- 02_AUTOMATIZACION/07_importar_datos_reales.sql

-- 10. IMPORTAR LOS DATOS REALES + WAREHOUSE (ejecutar al final, cuando toda la estructura ya este creada)
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
```
