-- 01_DATABASE/01_crear_base_y_tablas.sql

-- 0. BASE DE DATOS Y TABLAS
IF DB_ID('BD_DataSalud_Atenciones') IS NULL CREATE DATABASE BD_DataSalud_Atenciones;
GO
USE BD_DataSalud_Atenciones;   -- USE = pone en uso esa base de datos
GO

-- ---- TABLA DE APOYO 1: ORIGEN (sala de espera) ----
-- Recibe el CSV tal cual viene, todo como texto (VARCHAR), asi la carga nunca falla.
-- Luego usp_cargar_atenciones la revisa y pasa solo lo bueno al modelo.
-- Se vacia antes de cada archivo nuevo (usp_limpiar_origen).
IF OBJECT_ID('dbo.origen_atenciones_diagnostico','U') IS NULL
CREATE TABLE dbo.origen_atenciones_diagnostico (
    id_origen    INT IDENTITY(1,1) NOT NULL,   -- numero que SQL Server asigna solo (1, 2, 3...)
    Anio         VARCHAR(50),
    NroMes       VARCHAR(50),
    ubigeo       VARCHAR(50),
    Departamento VARCHAR(100),
    Provincia    VARCHAR(100),
    Distrito     VARCHAR(100),
    Sexo         VARCHAR(50),
    Etapa        VARCHAR(50),
    Diagnostico  VARCHAR(100),
    Atendidos    VARCHAR(50),
    Atenciones   VARCHAR(50),
    CONSTRAINT PK_Origen_Atenciones PRIMARY KEY (id_origen)   -- llave primaria
);
GO

-- ---- CATALOGO 1: donde ocurrio la atencion ----
IF OBJECT_ID('dbo.Ubicacion','U') IS NULL
CREATE TABLE dbo.Ubicacion (
    id_ubicacion INT IDENTITY(1,1) NOT NULL,
    ubigeo       VARCHAR(20)  NOT NULL,
    departamento VARCHAR(100) NOT NULL,
    provincia    VARCHAR(100) NOT NULL,
    distrito     VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Ubicacion PRIMARY KEY (id_ubicacion),
    CONSTRAINT UQ_Ubicacion UNIQUE (ubigeo, departamento, provincia, distrito)
);
GO

-- ---- CATALOGO 2: sexo ('F', 'M' o 'No registrado') ----
IF OBJECT_ID('dbo.Genero','U') IS NULL
CREATE TABLE dbo.Genero (
    id_genero INT IDENTITY(1,1) NOT NULL,
    sexo      VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Genero PRIMARY KEY (id_genero),
    CONSTRAINT UQ_Genero UNIQUE (sexo)
);
GO

-- ---- CATALOGO 3: etapa de vida ('1 - 4', '5 - 9', ...) ----
IF OBJECT_ID('dbo.Rango_Edad','U') IS NULL
CREATE TABLE dbo.Rango_Edad (
    id_rango_edad INT IDENTITY(1,1) NOT NULL,
    etapa         VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Rango_Edad PRIMARY KEY (id_rango_edad),
    CONSTRAINT UQ_Rango_Edad UNIQUE (etapa)
);
GO

-- ---- CATALOGO 4: tipo de diagnostico ----
IF OBJECT_ID('dbo.Diagnostico','U') IS NULL
CREATE TABLE dbo.Diagnostico (
    id_diagnostico INT IDENTITY(1,1) NOT NULL,
    diagnostico    VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Diagnostico PRIMARY KEY (id_diagnostico),
    CONSTRAINT UQ_Diagnostico UNIQUE (diagnostico)
);
GO

-- ---- TABLA PRINCIPAL (hechos): une los 4 catalogos con FOREIGN KEY ----
-- lote_id dice de que carga viene cada fila (sirve para cuadrar sumas).
IF OBJECT_ID('dbo.Atencion_Diagnostico','U') IS NULL
CREATE TABLE dbo.Atencion_Diagnostico (
    id_atencion_diagnostico INT IDENTITY(1,1) NOT NULL,
    id_ubicacion   INT NOT NULL,
    id_genero      INT NOT NULL,
    id_rango_edad  INT NOT NULL,
    id_diagnostico INT NOT NULL,
    anio       SMALLINT NOT NULL,
    nro_mes    TINYINT  NOT NULL,
    atendidos  INT NOT NULL,
    atenciones INT NOT NULL,
    fecha_carga DATETIME NOT NULL DEFAULT GETDATE(),   -- fecha automatica
    lote_id    VARCHAR(50) NULL,
    CONSTRAINT PK_Atencion_Diagnostico PRIMARY KEY (id_atencion_diagnostico),
    CONSTRAINT FK_Atencion_Ubicacion   FOREIGN KEY (id_ubicacion)   REFERENCES dbo.Ubicacion(id_ubicacion),
    CONSTRAINT FK_Atencion_Genero      FOREIGN KEY (id_genero)      REFERENCES dbo.Genero(id_genero),
    CONSTRAINT FK_Atencion_RangoEdad   FOREIGN KEY (id_rango_edad)  REFERENCES dbo.Rango_Edad(id_rango_edad),
    CONSTRAINT FK_Atencion_Diagnostico FOREIGN KEY (id_diagnostico) REFERENCES dbo.Diagnostico(id_diagnostico),
    -- una misma combinacion no puede repetirse
    CONSTRAINT UQ_Atencion_Diagnostico UNIQUE
        (id_ubicacion, id_genero, id_rango_edad, id_diagnostico, anio, nro_mes)
);
GO

-- ---- TABLA DE APOYO 2: CUARENTENA (filas rechazadas) ----
-- Aqui caen las filas con errores (mes 15, numeros negativos, vacios) o repetidas,
-- con el motivo escrito. Sirve para saber que corregir en el Excel. Todo en texto, tal como llego.
IF OBJECT_ID('dbo.tbl_cuarentena_atenciones','U') IS NULL
CREATE TABLE dbo.tbl_cuarentena_atenciones (
    id_cuarentena INT IDENTITY(1,1) NOT NULL,
    anio        VARCHAR(50),
    nro_mes     VARCHAR(50),
    ubigeo      VARCHAR(50),
    provincia   VARCHAR(100),
    diagnostico VARCHAR(100),
    atendidos   VARCHAR(50),
    atenciones  VARCHAR(50),
    motivo_error VARCHAR(255) NOT NULL,
    lote_id      VARCHAR(50),
    fecha_rechazo DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_Cuarentena_Atenciones PRIMARY KEY (id_cuarentena)
);
GO

-- ---- TABLA DE APOYO 3: LOG DE AUDITORIA ----
-- Libro de registro: quien hizo que y cuando. Lo escriben los triggers y los procedimientos.
IF OBJECT_ID('dbo.log_auditoria','U') IS NULL
CREATE TABLE dbo.log_auditoria (
    id_log      INT IDENTITY(1,1) NOT NULL,
    tabla       VARCHAR(100) NOT NULL,
    operacion   VARCHAR(20)  NOT NULL,      -- INSERT, UPDATE, DELETE, INGESTA, CARGA_CSV, ERROR...
    registro_id INT NULL,
    usuario     VARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    fecha_hora  DATETIME2    NOT NULL DEFAULT SYSDATETIME(),
    valor_anterior VARCHAR(MAX) NULL,
    valor_nuevo    VARCHAR(MAX) NULL,
    lote_id     VARCHAR(50)  NULL,
    detalle     VARCHAR(1000) NULL,
    CONSTRAINT PK_Log_Auditoria PRIMARY KEY (id_log)
);
GO

-- ---- TABLA DE APOYO 4: LOG DEL ETL ----
-- Boleta del proceso: cuantas filas paso por cada paso (lectura, cuarentena, catalogos, hechos,
-- warehouse) y si las sumas cuadraron.
IF OBJECT_ID('dbo.etl_log','U') IS NULL
CREATE TABLE dbo.etl_log (
    id_etl         INT IDENTITY(1,1) NOT NULL,
    ejecucion_id   UNIQUEIDENTIFIER NOT NULL,
    etapa          VARCHAR(60) NOT NULL,
    tabla_destino  VARCHAR(100) NULL,
    filas_leidas   INT NULL,
    filas_cargadas INT NULL,
    estado         VARCHAR(20) NOT NULL DEFAULT 'OK',
    detalle        VARCHAR(1000) NULL,
    fecha_hora     DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Etl_Log PRIMARY KEY (id_etl)
);
GO
