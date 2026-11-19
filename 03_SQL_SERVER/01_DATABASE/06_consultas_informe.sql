-- 01_DATABASE/06_consultas_informe.sql

USE BD_DataSalud_Atenciones;
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
