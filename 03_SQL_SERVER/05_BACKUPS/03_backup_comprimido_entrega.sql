-- 05_BACKUPS/03_backup_comprimido_entrega.sql

USE master;
GO

-- Backup completo y comprimido para entregar (un solo archivo .bak)
-- Cambia C:\Public\ por una carpeta con permiso de escritura para el servicio de SQL Server.
-- Si tu edicion no admite COMPRESSION, quita esa palabra.
BACKUP DATABASE BD_DataSalud_Atenciones
TO DISK = 'C:\Public\BD_DataSalud_Atenciones.bak'
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10, NAME = 'BD_DataSalud_Atenciones';
GO
-- Comprobar que el archivo no esta danado
RESTORE VERIFYONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones.bak' WITH CHECKSUM;
GO
