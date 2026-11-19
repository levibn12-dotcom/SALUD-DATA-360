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
