-- 05_BACKUPS/01_backup_y_verificacion.sql

-- 9. RESPALDO Y RESTAURACION (FULL + DIFFERENTIAL). La carpeta debe existir y ser escribible por el servicio de SQL Server.
USE master;
GO
BACKUP DATABASE BD_DataSalud_Atenciones
TO DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak'
WITH INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud Atenciones FULL';
GO
-- (aqui pueden hacerse cambios; el diferencial guarda solo lo cambiado desde el FULL)
BACKUP DATABASE BD_DataSalud_Atenciones
TO DISK = 'C:\Public\BD_DataSalud_Atenciones_DIFF.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 10, NAME = 'DataSalud Atenciones DIFF';
GO

-- Verificar que los archivos no estan danados
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak' WITH CHECKSUM;
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_DIFF.bak' WITH CHECKSUM;
GO

-- Ver los nombres internos de archivos (se usan en MOVE)
RESTORE FILELISTONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones_FULL.bak';
GO
