# 05 - Backups y restore

Politica: FULL semanal + DIFFERENTIAL diario, con CHECKSUM y verificacion. Restore probado en una base distinta (`_TEST`).

```sql
/* ---------------------------------------------------------------------
   9. POLITICA DE RESPALDO Y RESTORE PROBADO
   Politica: FULL semanal + DIFFERENTIAL diario, con CHECKSUM y verificacion.
   La carpeta debe existir y ser escribible por la cuenta del servicio de SQL Server.
   (SQL Server Express no tiene Agent: programa con Task Scheduler + sqlcmd.)
   --------------------------------------------------------------------- */
USE master;
GO
BACKUP DATABASE BD_DataSalud_LaLibertad
TO DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak'
WITH INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud FULL';
GO
-- (aqui pueden ocurrir cambios en la base; el diferencial solo guarda lo modificado desde el FULL)
BACKUP DATABASE BD_DataSalud_LaLibertad
TO DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud DIFF';
GO
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak' WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak' WITH CHECKSUM;
GO

-- Verifica los nombres logicos de archivos antes del restore:
RESTORE FILELISTONLY FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak';
GO

-- Restore PROBADO en una base distinta (no pisa la original): FULL + DIFFERENTIAL
RESTORE DATABASE BD_DataSalud_LaLibertad_TEST
FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_FULL.bak'
WITH MOVE 'BD_DataSalud_LaLibertad'     TO 'C:\Public\BD_DataSalud_LaLibertad_TEST.mdf',
     MOVE 'BD_DataSalud_LaLibertad_log' TO 'C:\Public\BD_DataSalud_LaLibertad_TEST.ldf',
     NORECOVERY, REPLACE;
RESTORE DATABASE BD_DataSalud_LaLibertad_TEST
FROM DISK = 'C:\Public\BD_DataSalud_LaLibertad_DIFF.bak'
WITH RECOVERY;
GO

-- Evidencia: los conteos deben ser iguales
SELECT
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad.dbo.tbl_tamizajes_salud_mental_limpio)      AS original_limpios,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad_TEST.dbo.tbl_tamizajes_salud_mental_limpio) AS restaurada_limpios,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad.dbo.Fact_Tamizajes)      AS original_hechos,
  (SELECT COUNT(*) FROM BD_DataSalud_LaLibertad_TEST.dbo.Fact_Tamizajes) AS restaurada_hechos;
GO
-- Cuando captures la evidencia: DROP DATABASE BD_DataSalud_LaLibertad_TEST;
-- Anota el RPO (perdida maxima aceptable = intervalo del DIFF) y el RTO (tiempo medido del restore).
```
