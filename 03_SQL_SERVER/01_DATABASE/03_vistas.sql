-- 01_DATABASE/03_vistas.sql

USE BD_DataSalud_Atenciones;
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
