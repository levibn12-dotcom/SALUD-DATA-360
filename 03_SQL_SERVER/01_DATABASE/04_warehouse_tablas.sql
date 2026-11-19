-- 01_DATABASE/04_warehouse_tablas.sql

USE BD_DataSalud_Atenciones;
GO

-- 5.2 DATA WAREHOUSE (crear): 3 tablas resumen en el esquema dw para Power BI.
--     Aqui solo se crea la estructura; se llena al final con usp_cargar_warehouse (paso 10.5).
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
GO

-- ---- TABLA RESUMEN 1: Tiempo x Diagnostico ----
-- Para que sirve: responde "como evoluciona cada tipo de caso mes a mes?".
-- En Power BI: grafico de lineas o columnas por anio/mes con el diagnostico como filtro.
IF OBJECT_ID('dw.Resumen_Tiempo_Diagnostico','U') IS NULL
CREATE TABLE dw.Resumen_Tiempo_Diagnostico (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    nro_mes             TINYINT  NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,   -- atenciones por persona atendida
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Tiempo_Diagnostico PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Tiempo_Diagnostico UNIQUE (anio, nro_mes, diagnostico)
);
GO

-- ---- TABLA RESUMEN 2: Ubicacion ----
-- Para que sirve: responde "donde se concentran los casos?". Llega hasta provincia (no distrito)
-- para que la tabla sea corta. En Power BI: mapa o barras por departamento/provincia.
IF OBJECT_ID('dw.Resumen_Ubicacion','U') IS NULL
CREATE TABLE dw.Resumen_Ubicacion (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    departamento        VARCHAR(100) NOT NULL,
    provincia           VARCHAR(100) NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Ubicacion PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Ubicacion UNIQUE (anio, departamento, provincia, diagnostico)
);
GO

-- ---- TABLA RESUMEN 3: Perfil (sexo y etapa) ----
-- Para que sirve: responde "a quienes afecta mas?". En Power BI: barras por sexo y etapa de vida.
IF OBJECT_ID('dw.Resumen_Perfil','U') IS NULL
CREATE TABLE dw.Resumen_Perfil (
    id_resumen          INT IDENTITY(1,1) NOT NULL,
    anio                SMALLINT NOT NULL,
    sexo                VARCHAR(20) NOT NULL,
    etapa               VARCHAR(50) NOT NULL,
    diagnostico         VARCHAR(100) NOT NULL,
    total_atendidos     INT NOT NULL,
    total_atenciones    INT NOT NULL,
    promedio_atenciones DECIMAL(10,2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Resumen_Perfil PRIMARY KEY (id_resumen),
    CONSTRAINT UQ_Resumen_Perfil UNIQUE (anio, sexo, etapa, diagnostico)
);
GO
