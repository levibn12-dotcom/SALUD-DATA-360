# 03 - Seguridad (roles, permisos y vistas)

Roles con minimo privilegio y segregacion de funciones: Administrador, Analista y Auditor. El analista solo accede a las vistas y al modelo dimensional, nunca a las tablas con detalle.

## 1. Vistas analiticas

```sql
/* ---------------------------------------------------------------------
   4. VISTAS ANALITICAS (el analista solo vera estas, no las tablas base)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_tamizajes_por_provincia AS
SELECT provincia, etapa, SUM(casos) AS TotalCasos
FROM dbo.tbl_tamizajes_salud_mental_limpio
WHERE provincia IS NOT NULL AND provincia <> ''
GROUP BY provincia, etapa;
GO
CREATE OR ALTER VIEW dbo.vw_tamizajes_tendencia_temporal AS
SELECT anio, nro_mes, SUM(casos) AS TotalCasosMensuales
FROM dbo.tbl_tamizajes_salud_mental_limpio
GROUP BY anio, nro_mes;
GO
```

## 2. Roles, permisos y usuarios de prueba

```sql
/* ---------------------------------------------------------------------
   6. SEGURIDAD: roles con minimo privilegio y segregacion de funciones
   Las vistas y procedimientos pertenecen a dbo, por lo que el encadenamiento de propiedad
   permite al analista leer las vistas sin tener acceso a las tablas base.
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID('Rol_Administrador_Salud') IS NULL CREATE ROLE Rol_Administrador_Salud;
IF DATABASE_PRINCIPAL_ID('Rol_Analista_Datos') IS NULL CREATE ROLE Rol_Analista_Datos;
IF DATABASE_PRINCIPAL_ID('Rol_Auditor') IS NULL CREATE ROLE Rol_Auditor;
GO

-- Se retiran los permisos amplios del script original
REVOKE CONTROL ON DATABASE::BD_DataSalud_LaLibertad FROM Rol_Administrador_Salud;
REVOKE SELECT ON dbo.tbl_tamizajes_salud_mental_limpio FROM Rol_Analista_Datos;
REVOKE SELECT ON dbo.tbl_tamizajes_salud_mental_limpio FROM Rol_Auditor;
GO

-- Administrador: opera y mantiene, pero NO puede alterar el log de auditoria
ALTER ROLE db_ddladmin ADD MEMBER Rol_Administrador_Salud;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO Rol_Administrador_Salud;
DENY INSERT, UPDATE, DELETE ON dbo.log_auditoria TO Rol_Administrador_Salud;
GO

-- Analista: solo vistas y modelo dimensional; sin acceso a tablas con detalle ni a logs
GRANT SELECT ON dbo.vw_tamizajes_por_provincia TO Rol_Analista_Datos;
GRANT SELECT ON dbo.vw_tamizajes_tendencia_temporal TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Ubicacion TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Tiempo TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Dim_Perfil TO Rol_Analista_Datos;
GRANT SELECT ON dbo.Fact_Tamizajes TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_atenciones_salud_mental TO Rol_Analista_Datos;
DENY SELECT ON dbo.staging_atenciones_mental TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Analista_Datos;
DENY SELECT ON dbo.tbl_cuarentena_tamizajes TO Rol_Analista_Datos;
DENY SELECT ON dbo.log_auditoria TO Rol_Analista_Datos;
GO

-- Auditor: solo lectura de log, cuarentena y log del ETL; no modifica nada
GRANT SELECT ON dbo.log_auditoria TO Rol_Auditor;
GRANT SELECT ON dbo.etl_log TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_atenciones TO Rol_Auditor;
GRANT SELECT ON dbo.tbl_cuarentena_tamizajes TO Rol_Auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO Rol_Auditor;
GO

-- Usuarios de prueba (sin login) para demostrar que cada rol falla donde debe
IF DATABASE_PRINCIPAL_ID('u_analista_test') IS NULL CREATE USER u_analista_test WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('u_auditor_test') IS NULL CREATE USER u_auditor_test WITHOUT LOGIN;
ALTER ROLE Rol_Analista_Datos ADD MEMBER u_analista_test;
ALTER ROLE Rol_Auditor ADD MEMBER u_auditor_test;
GO
```

## 3. Pruebas de roles (evidencia)

```sql
-- 8.6 Roles: cada prueba debe mostrar "OK bloqueado" donde corresponde
EXECUTE AS USER = 'u_analista_test';
BEGIN TRY
    SELECT TOP 1 * FROM dbo.tbl_atenciones_salud_mental;
    PRINT 'FALLO: el analista pudo leer la tabla base.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (analista -> tabla base): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.vw_tamizajes_por_provincia;   -- esto SI debe funcionar
REVERT;

EXECUTE AS USER = 'u_auditor_test';
BEGIN TRY
    DELETE FROM dbo.log_auditoria;
    PRINT 'FALLO: el auditor pudo borrar el log.';
END TRY
BEGIN CATCH
    PRINT CONCAT('OK bloqueado (auditor -> borrar log): ', ERROR_MESSAGE());
END CATCH;
SELECT TOP 5 * FROM dbo.log_auditoria ORDER BY id_log DESC;   -- esto SI debe funcionar
REVERT;
GO
```

