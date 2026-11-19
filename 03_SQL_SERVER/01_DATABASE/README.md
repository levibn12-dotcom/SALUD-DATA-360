# 01_DATABASE - Estructura de la base de datos

Crea la base `BD_DataSalud_Atenciones` con sus tablas, funciones, vistas y las tablas del warehouse. Es lo primero que se ejecuta.

## Archivos

| Archivo | Que hace |
|---|---|
| `01_crear_base_y_tablas.sql` | Crea la base y las 9 tablas: la de **hechos** (`Atencion_Diagnostico`), los 4 **catalogos** (`Ubicacion`, `Genero`, `Rango_Edad`, `Diagnostico`) y las de **apoyo** (`origen_atenciones_diagnostico`, `tbl_cuarentena_atenciones`, `log_auditoria`, `etl_log`). Todas con `PRIMARY KEY`; la de hechos tambien con `FOREIGN KEY` y `UNIQUE`. |
| `02_funciones.sql` | Dos funciones: `fn_promedio_atenciones` (atenciones por persona atendida, sin dividir entre cero) y `fn_etiqueta_seguimiento` (texto segun si hubo seguimiento). |
| `03_vistas.sql` | Tres vistas para el analista: totales por ubicacion y diagnostico, evolucion mensual, y por sexo/etapa/diagnostico. |
| `04_warehouse_tablas.sql` | Esquema `dw` y las 3 tablas resumen que se llevan a Power BI (se llenan con `02_AUTOMATIZACION/04_warehouse_carga.sql`). |
| `05_prueba_funciones.sql` | Prueba rapida de las dos funciones. |
| `06_consultas_informe.sql` | Consultas listas para el informe, sobre las tablas del warehouse. Ejecutar despues de importar los datos y cargar el warehouse. |

## Tablas del warehouse (esquema `dw`)

| Tabla | Para que sirve | En Power BI |
|---|---|---|
| `dw.Resumen_Tiempo_Diagnostico` | Como evoluciona cada tipo de caso mes a mes | Lineas o columnas por anio/mes |
| `dw.Resumen_Ubicacion` | Donde se concentran los casos (departamento y provincia) | Mapa o barras |
| `dw.Resumen_Perfil` | A quienes afecta (sexo y etapa de vida) | Barras |

## Llevar los datos a Power BI

Power BI Desktop > Obtener datos > SQL Server > servidor de SSMS (por ejemplo `localhost` o `.\SQLEXPRESS`) > base `BD_DataSalud_Atenciones` > marcar las 3 tablas del esquema `dw` > Cargar.

## Codigo

### `01_crear_base_y_tablas.sql`

Crea la base y las 9 tablas: la de **hechos** (`Atencion_Diagnostico`), los 4 **catalogos** (`Ubicacion`, `Genero`, `Rango_Edad`, `Diagnostico`) y las de **apoyo** (`origen_atenciones_diagnostico`, `tbl_cuarentena_atenciones`, `log_auditoria`, `etl_log`). Todas con `PRIMARY KEY`; la de hechos tambien con `FOREIGN KEY` y `UNIQUE`.

```sql
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
```

### `02_funciones.sql`

Dos funciones: `fn_promedio_atenciones` (atenciones por persona atendida, sin dividir entre cero) y `fn_etiqueta_seguimiento` (texto segun si hubo seguimiento).

```sql
-- 01_DATABASE/02_funciones.sql

USE BD_DataSalud_Atenciones;
GO

-- 1. FUNCIONES
-- Promedio de atenciones por persona atendida (si atendidos = 0 no se divide: devuelve 0)
CREATE OR ALTER FUNCTION dbo.fn_promedio_atenciones (@atendidos INT, @atenciones INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN CASE
        WHEN @atendidos IS NULL OR @atenciones IS NULL THEN 0
        WHEN @atendidos = 0 THEN 0                       -- evita dividir entre cero
        ELSE CAST(@atenciones AS DECIMAL(10,2)) / @atendidos
    END;
END;
GO

-- Etiqueta clara segun si hubo seguimiento o no
CREATE OR ALTER FUNCTION dbo.fn_etiqueta_seguimiento (@atendidos INT, @atenciones INT)
RETURNS VARCHAR(40)
AS
BEGIN
    RETURN CASE
        WHEN @atendidos IS NULL OR @atenciones IS NULL THEN 'No registrado'
        WHEN @atendidos = 0 AND @atenciones = 0 THEN 'Sin actividad'
        WHEN @atendidos = 0 THEN 'Solo seguimiento'          -- hubo atencion, pero no hay atendidos nuevos
        WHEN @atenciones > @atendidos THEN 'Con seguimiento' -- mas de una atencion por persona
        ELSE 'Atencion unica'
    END;
END;
GO
```

### `03_vistas.sql`

Tres vistas para el analista: totales por ubicacion y diagnostico, evolucion mensual, y por sexo/etapa/diagnostico.

```sql
-- 01_DATABASE/03_vistas.sql

USE BD_DataSalud_Atenciones;
GO

-- 4. VISTAS
-- 4.1 Totales por departamento, provincia y diagnostico
CREATE OR ALTER VIEW dbo.vw_total_por_ubicacion_diagnostico AS
SELECT u.departamento, u.provincia, d.diagnostico,
       SUM(f.atendidos)  AS total_atendidos,
       SUM(f.atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Ubicacion u ON u.id_ubicacion = f.id_ubicacion
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
GROUP BY u.departamento, u.provincia, d.diagnostico;
GO

-- 4.2 Evolucion por anio y mes
CREATE OR ALTER VIEW dbo.vw_evolucion_mensual AS
SELECT anio, nro_mes,
       SUM(atendidos)  AS total_atendidos,
       SUM(atenciones) AS total_atenciones
FROM dbo.Atencion_Diagnostico
GROUP BY anio, nro_mes;
GO

-- 4.3 Por sexo, etapa y diagnostico (con el promedio de la funcion)
CREATE OR ALTER VIEW dbo.vw_por_sexo_etapa_diagnostico AS
SELECT g.sexo, e.etapa, d.diagnostico,
       SUM(f.atendidos)  AS total_atendidos,
       SUM(f.atenciones) AS total_atenciones,
       dbo.fn_promedio_atenciones(SUM(f.atendidos), SUM(f.atenciones)) AS promedio_atenciones
FROM dbo.Atencion_Diagnostico f
JOIN dbo.Genero g ON g.id_genero = f.id_genero
JOIN dbo.Rango_Edad e ON e.id_rango_edad = f.id_rango_edad
JOIN dbo.Diagnostico d ON d.id_diagnostico = f.id_diagnostico
GROUP BY g.sexo, e.etapa, d.diagnostico;
GO
```

### `04_warehouse_tablas.sql`

Esquema `dw` y las 3 tablas resumen que se llevan a Power BI (se llenan con `02_AUTOMATIZACION/04_warehouse_carga.sql`).

```sql
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
```

### `05_prueba_funciones.sql`

Prueba rapida de las dos funciones.

```sql
-- 01_DATABASE/05_prueba_funciones.sql

USE BD_DataSalud_Atenciones;
GO

-- 8.1 Funciones
SELECT dbo.fn_etiqueta_seguimiento(0, 1)  AS solo_seguimiento,
       dbo.fn_etiqueta_seguimiento(2, 7)  AS con_seguimiento,
       dbo.fn_etiqueta_seguimiento(3, 3)  AS atencion_unica,
       dbo.fn_etiqueta_seguimiento(NULL, 1) AS nulo,
       dbo.fn_promedio_atenciones(2, 7)   AS promedio,
       dbo.fn_promedio_atenciones(0, 5)   AS sin_dividir_entre_cero;
GO
```

### `06_consultas_informe.sql`

Consultas listas para el informe, sobre las tablas del warehouse. Ejecutar despues de importar los datos y cargar el warehouse.

```sql
-- 01_DATABASE/06_consultas_informe.sql

USE BD_DataSalud_Atenciones;
GO

-- 10.6 CONSULTAS PARA EL INFORME
-- A) Total por anio y diagnostico
SELECT anio, diagnostico, SUM(total_atendidos) AS atendidos, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Tiempo_Diagnostico
GROUP BY anio, diagnostico
ORDER BY anio, diagnostico;

-- B) Los 10 departamentos con mas atenciones (todos los anios)
SELECT TOP 10 departamento, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Ubicacion
GROUP BY departamento
ORDER BY atenciones DESC;

-- C) Por sexo y etapa de vida
SELECT sexo, etapa, SUM(total_atendidos) AS atendidos, SUM(total_atenciones) AS atenciones
FROM dw.Resumen_Perfil
GROUP BY sexo, etapa
ORDER BY sexo, etapa;

-- D) Evolucion mensual total
SELECT * FROM dbo.vw_evolucion_mensual ORDER BY anio, nro_mes;
GO
```
