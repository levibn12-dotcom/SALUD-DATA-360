-- 01_DATABASE/02_funciones.sql

USE BD_DataSalud_Atenciones;
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
