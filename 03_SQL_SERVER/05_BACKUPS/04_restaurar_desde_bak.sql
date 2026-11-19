-- 05_BACKUPS/04_restaurar_desde_bak.sql

USE master;
GO

-- Restaurar la base desde el .bak entregado (en otro equipo)
-- 1) Ver los nombres internos de los archivos de la copia
RESTORE FILELISTONLY FROM DISK = 'C:\Public\BD_DataSalud_Atenciones.bak';
GO
-- 2) Restaurar. Si los nombres del paso 1 son distintos, cambialos en MOVE. Cambia las rutas por las de tu equipo.
RESTORE DATABASE BD_DataSalud_Atenciones
FROM DISK = 'C:\Public\BD_DataSalud_Atenciones.bak'
WITH MOVE 'BD_DataSalud_Atenciones'     TO 'C:\Public\BD_DataSalud_Atenciones.mdf',
     MOVE 'BD_DataSalud_Atenciones_log' TO 'C:\Public\BD_DataSalud_Atenciones_log.ldf',
     REPLACE, RECOVERY;
GO
-- 3) Comprobar que hay datos
SELECT (SELECT COUNT(*) FROM BD_DataSalud_Atenciones.dbo.Atencion_Diagnostico) AS hechos,
       (SELECT COUNT(*) FROM BD_DataSalud_Atenciones.dbo.Ubicacion)            AS ubicaciones,
       (SELECT COUNT(*) FROM BD_DataSalud_Atenciones.dw.Resumen_Perfil)        AS resumen_perfil;
GO
