-- 05_BACKUPS/02_restore_prueba.sql

USE master;
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
