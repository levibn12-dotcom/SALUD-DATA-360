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
