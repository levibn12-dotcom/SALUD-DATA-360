# 03_SEGURIDAD - Roles y permisos

Tres roles con el minimo de permisos y dos usuarios de prueba (sin login) para demostrar que cada rol queda bloqueado donde corresponde.

## Archivos

| Archivo | Que hace |
|---|---|
| `01_roles_y_permisos.sql` | Crea `Rol_Administrador`, `Rol_Analista` y `Rol_Auditor`, asigna `GRANT`/`DENY` y crea los usuarios `u_analista_test` y `u_auditor_test`. |
| `02_pruebas_roles.sql` | Prueba con `EXECUTE AS USER` / `REVERT`: debe mostrar mensajes `OK bloqueado` donde el rol no tiene permiso. |

## Que puede hacer cada rol

| Rol | Puede | No puede |
|---|---|---|
| `Rol_Administrador` | Usar y modificar todo, ejecutar procedimientos | Modificar o borrar `log_auditoria` |
| `Rol_Analista` | `SELECT` en vistas, warehouse (`dw`) y tablas del modelo final | Ver la tabla de origen, cuarentena, `log_auditoria` ni `etl_log` |
| `Rol_Auditor` | `SELECT` en `log_auditoria`, `etl_log` y cuarentena | Modificar nada; leer la tabla de hechos |

## Codigo

### `01_roles_y_permisos.sql`

Crea `Rol_Administrador`, `Rol_Analista` y `Rol_Auditor`, asigna `GRANT`/`DENY` y crea los usuarios `u_analista_test` y `u_auditor_test`.

```sql
-- 03_SEGURIDAD/01_roles_y_permisos.sql

USE BD_DataSalud_Atenciones;
GO

-- 6. SEGURIDAD (roles con el minimo de permisos)
IF DATABASE_PRINCIPAL_ID('Rol_Administrador') IS NULL CREATE ROLE Rol_Administrador;
IF DATABASE_PRINCIPAL_ID('Rol_Analista')      IS NULL CREATE ROLE Rol_Analista;
IF DATABASE_PRINCIPAL_ID('Rol_Auditor')       IS NULL CREATE ROLE Rol_Auditor;
GO

-- Administrador: usa todo, pero NO puede modificar ni borrar el log de auditoria
-- (los triggers siguen pudiendo escribir en el log porque son de dbo)
ALTER ROLE db_ddladmin ADD MEMBER Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO Rol_Administrador;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dw TO Rol_Administrador;
DENY INSERT, UPDATE, DELETE ON dbo.log_auditoria TO Rol_Administrador;
GO

-- Analista: solo SELECT en vistas, warehouse y tablas del modelo final
GRANT SELECT ON dbo.vw_total_por_ubicacion_diagnostico TO Rol_Analista;
GRANT SELECT ON dbo.vw_evolucion_mensual TO Rol_Analista;
GRANT SELECT ON dbo.vw_por_sexo_etapa_diagnostico TO Rol_Analista;
GRANT SELECT ON SCHEMA::dw TO Rol_Analista;
GRANT SELECT ON dbo.Ubicacion TO Rol_Analista;
GRANT SELECT ON dbo.Genero TO Rol_Analista;
GRANT SELECT ON dbo.Rango_Edad TO Rol_Analista;
GRANT SELECT ON dbo.Diagnostico TO Rol_Analista;
GRANT SELECT ON dbo.Atencion_Diagnostico TO Rol_Analista;
DENY SELECT ON dbo.origen_atenciones_diagnostico TO Rol_Analista;
DENY SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Analista;
DENY SELECT ON dbo.log_auditoria TO Rol_Analista;
DENY SELECT ON dbo.etl_log TO Rol_Analista;
GO

-- Auditor: solo lee log, etl_log y cuarentena; no modifica nada
GRANT SELECT ON dbo.log_auditoria TO Rol_Auditor;
GRANT SELECT ON dbo.etl_log TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO Rol_Auditor;
GO

-- Usuarios de prueba sin login (sirven solo para demostrar los permisos)
IF DATABASE_PRINCIPAL_ID('u_analista_test') IS NULL CREATE USER u_analista_test WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('u_auditor_test')  IS NULL CREATE USER u_auditor_test WITHOUT LOGIN;
ALTER ROLE Rol_Analista ADD MEMBER u_analista_test;
ALTER ROLE Rol_Auditor  ADD MEMBER u_auditor_test;
GO
```

### `02_pruebas_roles.sql`

Prueba con `EXECUTE AS USER` / `REVERT`: debe mostrar mensajes `OK bloqueado` donde el rol no tiene permiso.

```sql
-- 03_SEGURIDAD/02_pruebas_roles.sql

USE BD_DataSalud_Atenciones;
GO

-- 8.7 Roles: cada prueba debe mostrar "OK bloqueado" donde corresponde
EXECUTE AS USER = 'u_analista_test';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.origen_atenciones_diagnostico;
    PRINT 'FALLO: el analista pudo leer la tabla de origen.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> origen): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.log_auditoria;
    PRINT 'FALLO: el analista pudo leer el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> log_auditoria): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.vw_evolucion_mensual;   -- esto SI debe funcionar
SELECT TOP 5 * FROM dw.Resumen_Ubicacion;       -- esto SI debe funcionar
REVERT;

EXECUTE AS USER = 'u_auditor_test';
BEGIN TRY
    DELETE FROM dbo.log_auditoria;
    PRINT 'FALLO: el auditor pudo borrar el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> borrar log): ', ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    SELECT TOP 1 * FROM dbo.Atencion_Diagnostico;
    PRINT 'FALLO: el auditor pudo leer la tabla de hechos.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> tabla de hechos): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.log_auditoria ORDER BY id_log DESC;   -- esto SI debe funcionar
REVERT;
GO
```

