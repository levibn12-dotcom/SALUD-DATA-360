# 05_BACKUPS - Respaldo y restauracion

Politica: **FULL semanal + DIFFERENTIAL diario**, con `CHECKSUM` y verificacion. El restore se prueba en una base distinta (`_TEST`) comparando los conteos con la original.

## Archivos

| Archivo | Que hace |
|---|---|
| `01_backup_y_verificacion.sql` | Backup `FULL` y `DIFFERENTIAL`, y verificacion con `RESTORE VERIFYONLY` y `RESTORE FILELISTONLY`. |
| `02_restore_prueba.sql` | Restaura FULL + DIFFERENTIAL en `BD_DataSalud_Atenciones_TEST` y compara los conteos con la base original. |
| `03_backup_comprimido_entrega.sql` | Backup completo y comprimido en **un solo archivo** `.bak`, listo para entregar. |
| `04_restaurar_desde_bak.sql` | Como restaurar la base desde ese `.bak` en otro equipo. |

## Archivo `.bak` de la base

Coloca aqui el archivo `BD_DataSalud_Atenciones.bak` (unos 5 MB, comprimido). Contiene la estructura **y los datos**.

**Importante:** se creo en SQL Server 2025 (version 17). Un `.bak` solo se restaura en esa version o en una mas nueva; si tu SQL Server es anterior, usa los scripts y los CSV para reconstruir la base.

Restaurar desde SSMS: clic derecho en *Bases de datos > Restaurar base de datos > Dispositivo* > elegir el `.bak` > Aceptar.

Las rutas `C:\Public\` son de ejemplo: usa una carpeta con permiso de lectura/escritura para el servicio de SQL Server.

**RPO** (perdida maxima aceptable) = intervalo entre backups `DIFFERENTIAL`. **RTO** = tiempo medido del restore.

## Codigo

### `01_backup_y_verificacion.sql`

Backup `FULL` y `DIFFERENTIAL`, y verificacion con `RESTORE VERIFYONLY` y `RESTORE FILELISTONLY`.

```sql
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
```

### `02_restore_prueba.sql`

Restaura FULL + DIFFERENTIAL en `BD_DataSalud_Atenciones_TEST` y compara los conteos con la base original.

```sql
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
```

### `03_backup_comprimido_entrega.sql`

Backup completo y comprimido en **un solo archivo** `.bak`, listo para entregar.

```sql
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
```

### `04_restaurar_desde_bak.sql`

Como restaurar la base desde ese `.bak` en otro equipo.

```sql
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
```
