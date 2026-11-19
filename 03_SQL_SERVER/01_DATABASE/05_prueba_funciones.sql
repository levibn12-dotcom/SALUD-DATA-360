-- 01_DATABASE/05_prueba_funciones.sql

USE BD_DataSalud_Atenciones;
GO

-- 8.1 Funciones
SELECT dbo.fn_etiqueta_seguimiento(0, 1)  AS solo_seguimiento,
       dbo.fn_etiqueta_seguimiento(2, 7)  AS con_seguimiento,
       dbo.fn_etiqueta_seguimiento(3, 3)  AS atencion_unica,
       dbo.fn_etiqueta_seguimiento(NULL, 1) AS nulo,
       dbo.fn_promedio_atenciones(2, 7)   AS promedio,
       dbo.fn_promedio_atenciones(0, 5)   AS sin_dividir_entre_cero;
GO
