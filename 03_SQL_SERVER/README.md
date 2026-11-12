# 06 - Rendimiento (indice y metricas antes/despues)

Indice no agrupado sobre `(provincia, anio)` y comparacion de `logical reads` y tiempos con `STATISTICS IO/TIME`. Ejecutar con la tabla de tamizajes ya cargada.

```sql
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
```

