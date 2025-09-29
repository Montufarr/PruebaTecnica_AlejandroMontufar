--Alejandro Daniel Montufar Reyes

-- Script que crea la base de datos chn_dw (powerbi) con tablas relacionales (prefijo dbr_),
-- dimensiones (prefijo dim_) y hechos (prefijo fac_) usando nombres de tablas y
-- campos completamente en español.
--

/* Tablas del modelo relacional (normalizado) */
SELECT *
FROM dim_destino_fondos_s7;

-- Tabla de tipo de riesgo segun la SIB
IF OBJECT_ID('dbo.dbr_categoria_riesgo') IS NOT NULL DROP TABLE dbo.dbr_categoria_riesgo;
CREATE TABLE dbo.dbr_categoria_riesgo
(
    codigo_categoria CHAR(1)       NOT NULL PRIMARY KEY,
    descripcion      NVARCHAR(200) NOT NULL
);
ALTER TABLE dbo.dbr_evaluacion_riesgo
    ADD CONSTRAINT FK_dbr_evaluacion_riesgo_categoria FOREIGN KEY (categoria_riesgo)
        REFERENCES dbo.dbr_categoria_riesgo (codigo_categoria);

-- Tabla de direcciones
IF OBJECT_ID('dbo.dbr_direccion') IS NOT NULL DROP TABLE dbo.dbr_direccion;
CREATE TABLE dbo.dbr_direccion
(
    direccion_id INT IDENTITY (1,1) PRIMARY KEY,
    calle        NVARCHAR(200) NOT NULL,
    ciudad       NVARCHAR(100) NOT NULL,
    departamento NVARCHAR(100) NOT NULL,
    pais         NVARCHAR(100) NOT NULL,
);
GO

-- Tabla de clientes (personas y empresas)
IF OBJECT_ID('dbo.dbr_cliente') IS NOT NULL DROP TABLE dbo.dbr_cliente;
CREATE TABLE dbo.dbr_cliente
(
    cliente_id        INT IDENTITY (1,1) PRIMARY KEY,
    tipo_cliente      CHAR(1)       NOT NULL CHECK (tipo_cliente IN ('I', 'J')),
    nombre            NVARCHAR(100) NULL,
    apellido          NVARCHAR(100) NULL,
    razon_social      NVARCHAR(200) NULL,
    dpi               CHAR(13)      NULL,
    nit               NVARCHAR(20)  NULL,
    fecha_nacimiento  DATE          NULL,
    genero            CHAR(1)       NULL CHECK (genero IN ('M', 'F')),
    telefono_contacto NVARCHAR(20)  NULL,
    direccion_id      INT           NOT NULL,
    creado_en         DATETIME2     NOT NULL DEFAULT (SYSDATETIME()),
    actualizado_en    DATETIME2     NOT NULL DEFAULT (SYSDATETIME()),
    CONSTRAINT FK_dbr_cliente_direccion FOREIGN KEY (direccion_id) REFERENCES dbo.dbr_direccion (direccion_id),
    CONSTRAINT CK_dbr_cliente_nombre CHECK (
        (tipo_cliente = 'I' AND nombre IS NOT NULL AND apellido IS NOT NULL AND razon_social IS NULL)
            OR
        (tipo_cliente = 'J' AND razon_social IS NOT NULL AND nombre IS NULL AND apellido IS NULL)
        ),
    CONSTRAINT UX_dbr_cliente_nit UNIQUE (nit)
);
GO

-- Tabla de agencias
IF OBJECT_ID('dbo.dbr_agencia') IS NOT NULL DROP TABLE dbo.dbr_agencia;
CREATE TABLE dbo.dbr_agencia
(
    agencia_id        INT IDENTITY (1,1) PRIMARY KEY,
    nombre            NVARCHAR(200) NOT NULL,
    direccion_id      INT           NOT NULL,
    gerente           NVARCHAR(100) NULL,
    telefono_contacto NVARCHAR(20)  NULL,
    CONSTRAINT FK_dbr_agencia_direccion FOREIGN KEY (direccion_id) REFERENCES dbo.dbr_direccion (direccion_id)
);
GO

-- Tabla de productos financieros
IF OBJECT_ID('dbo.dbr_producto') IS NOT NULL DROP TABLE dbo.dbr_producto;
CREATE TABLE dbo.dbr_producto
(
    producto_id     INT IDENTITY (1,1) PRIMARY KEY,
    tipo_producto   VARCHAR(20)    NOT NULL CHECK (tipo_producto IN ('cuenta_monetaria', 'prestamo', 'remesa')),
    numero_producto NVARCHAR(50)   NOT NULL UNIQUE,
    cliente_id      INT            NOT NULL,
    fecha_apertura  DATE           NOT NULL,
    moneda          CHAR(3)        NOT NULL DEFAULT 'GTQ',
    estado          VARCHAR(10)    NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'cerrado', 'moroso')),
    saldo           DECIMAL(18, 2) NOT NULL DEFAULT 0,
    tasa_interes    DECIMAL(5, 2)  NULL,
    CONSTRAINT FK_dbr_producto_cliente FOREIGN KEY (cliente_id) REFERENCES dbo.dbr_cliente (cliente_id)
);

CREATE NONCLUSTERED INDEX IX_dbr_producto_cliente ON dbo.dbr_producto (cliente_id);
GO

-- Tabla de transacciones
IF OBJECT_ID('dbo.dbr_transaccion') IS NOT NULL DROP TABLE dbo.dbr_transaccion;
CREATE TABLE dbo.dbr_transaccion
(
    transaccion_id    INT IDENTITY (1,1) PRIMARY KEY,
    producto_id       INT            NOT NULL,
    fecha_transaccion DATETIME2      NOT NULL,
    tipo_transaccion  VARCHAR(20)    NOT NULL CHECK (tipo_transaccion IN
                                                     ('deposito', 'retiro', 'pago', 'interes', 'comision',
                                                      'remesa_envio', 'remesa_pago')),
    monto             DECIMAL(18, 2) NOT NULL,
    descripcion       NVARCHAR(200)  NULL,
    agencia_id        INT            NOT NULL,
    creado_en         DATETIME2      NOT NULL DEFAULT (SYSDATETIME()),
    CONSTRAINT FK_dbr_transaccion_producto FOREIGN KEY (producto_id) REFERENCES dbo.dbr_producto (producto_id),
    CONSTRAINT FK_dbr_transaccion_agencia FOREIGN KEY (agencia_id) REFERENCES dbo.dbr_agencia (agencia_id)
);

CREATE NONCLUSTERED INDEX IX_dbr_transaccion_producto ON dbo.dbr_transaccion (producto_id);
CREATE NONCLUSTERED INDEX IX_dbr_transaccion_fecha ON dbo.dbr_transaccion (fecha_transaccion);
CREATE NONCLUSTERED INDEX IX_dbr_transaccion_agencia ON dbo.dbr_transaccion (agencia_id);
GO

-- Tabla de evaluaciones de riesgo crediticio
IF OBJECT_ID('dbo.dbr_evaluacion_riesgo') IS NOT NULL DROP TABLE dbo.dbr_evaluacion_riesgo;
CREATE TABLE dbo.dbr_evaluacion_riesgo
(
    evaluacion_id    INT IDENTITY (1,1) PRIMARY KEY,
    cliente_id       INT           NOT NULL,
    fecha_evaluacion DATE          NOT NULL,
    categoria_riesgo CHAR(1)       NOT NULL CHECK (categoria_riesgo IN ('A', 'B', 'C', 'D', 'E')),
    puntaje          DECIMAL(5, 2) NULL,
    observaciones    NVARCHAR(500) NULL,
    CONSTRAINT FK_dbr_evaluacion_riesgo_cliente FOREIGN KEY (cliente_id) REFERENCES dbo.dbr_cliente (cliente_id)
);

CREATE NONCLUSTERED INDEX IX_dbr_evaluacion_riesgo_cliente_fecha ON dbo.dbr_evaluacion_riesgo (cliente_id, fecha_evaluacion DESC);
GO

/* Tablas del datamart: dimensiones y hechos */
-- Dimensión tiempo
IF OBJECT_ID('dbo.dim_tiempo') IS NOT NULL DROP TABLE dbo.dim_tiempo;
CREATE TABLE dbo.dim_tiempo
(
    fecha_key     INT          NOT NULL PRIMARY KEY,
    fecha         DATE         NOT NULL,
    dia           TINYINT      NOT NULL,
    mes           TINYINT      NOT NULL,
    anio          SMALLINT     NOT NULL,
    trimestre     TINYINT      NOT NULL,
    nombre_mes    NVARCHAR(30) NOT NULL DEFAULT '',
    es_fin_semana BIT          NOT NULL DEFAULT (0)

);
GO

-- Dimensión cliente
IF OBJECT_ID('dbo.dim_cliente') IS NOT NULL DROP TABLE dbo.dim_cliente;
CREATE TABLE dbo.dim_cliente
(
    cliente_key            INT IDENTITY (1,1) PRIMARY KEY,
    cliente_id             INT           NOT NULL,
    tipo_cliente           CHAR(1)       NOT NULL,
    nombre_completo        NVARCHAR(200) NOT NULL,
    razon_social           NVARCHAR(200) NULL,
    genero                 CHAR(1)       NULL,
    fecha_nacimiento       DATE          NULL,
    nit                    NVARCHAR(20)  NULL,
    dpi                    CHAR(13)      NULL,
    telefono               NVARCHAR(20)  NULL,
    direccion_calle        NVARCHAR(200),
    direccion_departamento NVARCHAR(100),
    direccion_ciudad       NVARCHAR(100),
    direccion_pais         NVARCHAR(100)
);
CREATE NONCLUSTERED INDEX IX_dim_cliente_cliente_id ON dbo.dim_cliente (cliente_id);
GO


-- Dimensión producto
IF OBJECT_ID('dbo.dim_producto') IS NOT NULL DROP TABLE dbo.dim_producto;
CREATE TABLE dbo.dim_producto
(
    producto_key   INT IDENTITY (1,1) PRIMARY KEY,
    producto_id    INT            NOT NULL,
    tipo_producto  VARCHAR(20)    NOT NULL,
    fecha_apertura DATE           NOT NULL,
    moneda         CHAR(3)        NOT NULL,
    estado         VARCHAR(10)    NOT NULL,
    saldo          DECIMAL(18, 2) NOT NULL,
    cliente_id     INT            NOT NULL
);
CREATE NONCLUSTERED INDEX IX_dim_producto_producto_id ON dbo.dim_producto (producto_id);
GO

-- Dimensión agencia
IF OBJECT_ID('dbo.dim_agencia') IS NOT NULL DROP TABLE dbo.dim_agencia;
CREATE TABLE dbo.dim_agencia
(
    agencia_key  INT IDENTITY (1,1) PRIMARY KEY,
    agencia_id   INT           NOT NULL,
    nombre       NVARCHAR(200) NOT NULL,
    ciudad       NVARCHAR(100) NOT NULL,
    departamento NVARCHAR(100) NOT NULL
);
CREATE NONCLUSTERED INDEX IX_dim_agencia_agencia_id ON dbo.dim_agencia (agencia_id);
GO

-- Dimensión categoría de riesgo
IF OBJECT_ID('dbo.dim_categoria_riesgo') IS NOT NULL DROP TABLE dbo.dim_categoria_riesgo;
CREATE TABLE dbo.dim_categoria_riesgo
(
    categoria_key    INT IDENTITY (1,1) PRIMARY KEY,
    codigo_categoria CHAR(1)       NOT NULL UNIQUE,
    descripcion      NVARCHAR(200) NOT NULL
);
GO

-- Hecho de transacciones
IF OBJECT_ID('dbo.fac_transaccion') IS NOT NULL DROP TABLE dbo.fac_transaccion;
CREATE TABLE dbo.fac_transaccion
(
    transaccion_key BIGINT IDENTITY (1,1) PRIMARY KEY,
    fecha_key       INT            NOT NULL,
    cliente_key     INT            NOT NULL,
    producto_key    INT            NOT NULL,
    agencia_key     INT            NOT NULL,
    monto           DECIMAL(18, 2) NOT NULL,
    CONSTRAINT FK_fac_transaccion_dim_tiempo FOREIGN KEY (fecha_key) REFERENCES dbo.dim_tiempo (fecha_key),
    CONSTRAINT FK_fac_transaccion_dim_cliente FOREIGN KEY (cliente_key) REFERENCES dbo.dim_cliente (cliente_key),
    CONSTRAINT FK_fac_transaccion_dim_producto FOREIGN KEY (producto_key) REFERENCES dbo.dim_producto (producto_key),
    CONSTRAINT FK_fac_transaccion_dim_agencia FOREIGN KEY (agencia_key) REFERENCES dbo.dim_agencia (agencia_key)
);
CREATE NONCLUSTERED INDEX IX_fac_transaccion_clave ON dbo.fac_transaccion (cliente_key, producto_key);
GO

-- Hecho de evaluaciones de riesgo
IF OBJECT_ID('dbo.fac_evaluacion_riesgo') IS NOT NULL DROP TABLE dbo.fac_evaluacion_riesgo;
CREATE TABLE dbo.fac_evaluacion_riesgo
(
    evaluacion_key BIGINT IDENTITY (1,1) PRIMARY KEY,
    fecha_key      INT           NOT NULL,
    cliente_key    INT           NOT NULL,
    categoria_key  INT           NOT NULL,
    puntaje        DECIMAL(5, 2) NULL,
    CONSTRAINT FK_fac_evaluacion_riesgo_dim_tiempo FOREIGN KEY (fecha_key) REFERENCES dbo.dim_tiempo (fecha_key),
    CONSTRAINT FK_fac_evaluacion_riesgo_dim_cliente FOREIGN KEY (cliente_key) REFERENCES dbo.dim_cliente (cliente_key),
    CONSTRAINT FK_fac_evaluacion_riesgo_dim_categoria FOREIGN KEY (categoria_key) REFERENCES dbo.dim_categoria_riesgo (categoria_key)
);
CREATE NONCLUSTERED INDEX IX_fac_evaluacion_riesgo_cliente ON dbo.fac_evaluacion_riesgo (cliente_key);
GO


--Insert con datos dummy para tablas dbr

SET IDENTITY_INSERT dbo.dbr_direccion ON;

INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (1, '4a Avenida 7-45 Zona 12', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (2, '8a Avenida 36-23 Zona 12', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (3, '18a Avenida 23-64 Zona 10', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (4, '1a Avenida 24-39 Zona 4', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (5, '20a Avenida 7-35 Zona 9', 'San Marcos', 'San Marcos', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (6, '18a Avenida 108-67 Zona 4', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (7, '9a Avenida 2-30 Zona 13', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (8, '11a Avenida 72-37 Zona 3', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (9, '4a Avenida 24-22 Zona 7', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (10, '12a Avenida 155-15 Zona 5', 'Flores', 'Petén', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (11, '18a Avenida 32-58 Zona 15', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (12, '18a Avenida 76-90 Zona 14', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (13, '12a Avenida 148-18 Zona 4', 'Mazatenango', 'Suchitepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (14, '8a Avenida 198-20 Zona 5', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (15, '4a Avenida 98-68 Zona 5', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (16, '12a Avenida 42-55 Zona 6', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (17, '9a Avenida 180-97 Zona 15', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (18, '3a Avenida 156-31 Zona 11', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (19, '8a Avenida 42-58 Zona 8', 'Cuilapa', 'Santa Rosa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (20, '18a Avenida 57-51 Zona 11', 'Puerto Barrios', 'Izabal', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (21, '8a Avenida 9-50 Zona 13', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (22, '9a Avenida 17-82 Zona 4', 'Quetzaltenango', 'Quetzaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (23, '7a Avenida 168-60 Zona 8', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (24, '15a Avenida 37-27 Zona 5', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (25, '18a Avenida 138-84 Zona 5', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (26, '19a Avenida 103-38 Zona 6', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (27, '17a Avenida 127-16 Zona 2', 'Guastatoya', 'El Progreso', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (28, '5a Avenida 161-97 Zona 3', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (29, '20a Avenida 17-58 Zona 7', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (30, '15a Avenida 136-80 Zona 5', 'Mazatenango', 'Suchitepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (31, '4a Avenida 175-78 Zona 15', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (32, '11a Avenida 29-65 Zona 5', 'Puerto Barrios', 'Izabal', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (33, '15a Avenida 1-43 Zona 12', 'Escuintla', 'Escuintla', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (34, '6a Avenida 130-23 Zona 15', 'San Marcos', 'San Marcos', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (35, '10a Avenida 164-87 Zona 9', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (36, '5a Avenida 96-30 Zona 13', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (37, '17a Avenida 1-51 Zona 10', 'Cuilapa', 'Santa Rosa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (38, '1a Avenida 29-56 Zona 15', 'Antigua Guatemala', 'Sacatepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (39, '8a Avenida 15-82 Zona 4', 'Jalapa', 'Jalapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (40, '3a Avenida 188-18 Zona 8', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (41, '5a Avenida 33-70 Zona 11', 'Cuilapa', 'Santa Rosa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (42, '6a Avenida 68-87 Zona 9', 'Cuilapa', 'Santa Rosa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (43, '7a Avenida 139-98 Zona 13', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (44, '10a Avenida 103-93 Zona 11', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (45, '15a Avenida 133-25 Zona 8', 'Flores', 'Petén', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (46, '8a Avenida 17-12 Zona 6', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (47, '18a Avenida 59-38 Zona 10', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (48, '3a Avenida 182-17 Zona 11', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (49, '3a Avenida 9-52 Zona 14', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (50, '17a Avenida 61-95 Zona 5', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (51, '7a Avenida 139-83 Zona 3', 'Antigua Guatemala', 'Sacatepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (52, '16a Avenida 63-70 Zona 13', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (53, '7a Avenida 25-94 Zona 2', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (54, '12a Avenida 109-69 Zona 7', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (55, '4a Avenida 16-53 Zona 7', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (56, '8a Avenida 50-78 Zona 4', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (57, '5a Avenida 109-45 Zona 3', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (58, '8a Avenida 20-80 Zona 8', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (59, '2a Avenida 167-11 Zona 9', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (60, '8a Avenida 43-72 Zona 7', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (61, '7a Avenida 103-17 Zona 15', 'Antigua Guatemala', 'Sacatepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (62, '13a Avenida 1-43 Zona 7', 'Escuintla', 'Escuintla', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (63, '10a Avenida 109-81 Zona 12', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (64, '16a Avenida 40-47 Zona 4', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (65, '2a Avenida 149-79 Zona 12', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (66, '11a Avenida 15-84 Zona 1', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (67, '17a Avenida 136-17 Zona 3', 'Antigua Guatemala', 'Sacatepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (68, '3a Avenida 48-86 Zona 2', 'San Marcos', 'San Marcos', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (69, '8a Avenida 104-82 Zona 2', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (70, '19a Avenida 153-89 Zona 1', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (71, '14a Avenida 169-82 Zona 10', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (72, '11a Avenida 67-95 Zona 4', 'San Marcos', 'San Marcos', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (73, '8a Avenida 68-26 Zona 7', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (74, '10a Avenida 118-19 Zona 6', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (75, '15a Avenida 160-22 Zona 10', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (76, '18a Avenida 55-43 Zona 9', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (77, '12a Avenida 18-41 Zona 15', 'Guastatoya', 'El Progreso', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (78, '10a Avenida 41-79 Zona 8', 'Flores', 'Petén', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (79, '20a Avenida 168-11 Zona 9', 'Jalapa', 'Jalapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (80, '18a Avenida 77-94 Zona 15', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (81, '5a Avenida 68-23 Zona 2', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (82, '5a Avenida 70-87 Zona 5', 'Cuilapa', 'Santa Rosa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (83, '11a Avenida 53-91 Zona 11', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (84, '17a Avenida 126-16 Zona 5', 'Puerto Barrios', 'Izabal', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (85, '14a Avenida 71-10 Zona 1', 'Chimaltenango', 'Chimaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (86, '5a Avenida 164-30 Zona 5', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (87, '18a Avenida 181-81 Zona 7', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (88, '4a Avenida 20-98 Zona 15', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (89, '18a Avenida 10-57 Zona 14', 'Guastatoya', 'El Progreso', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (90, '18a Avenida 38-26 Zona 7', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (91, '10a Avenida 94-15 Zona 15', 'Salamá', 'Baja Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (92, '7a Avenida 175-95 Zona 4', 'Flores', 'Petén', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (93, '12a Avenida 200-62 Zona 9', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (94, '5a Avenida 61-30 Zona 14', 'Mazatenango', 'Suchitepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (95, '14a Avenida 7-52 Zona 3', 'Escuintla', 'Escuintla', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (96, '8a Avenida 69-99 Zona 3', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (97, '13a Avenida 10-70 Zona 14', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (98, '7a Avenida 118-49 Zona 6', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (99, '8a Avenida 7-34 Zona 11', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (100, '11a Avenida 72-18 Zona 14', 'Quetzaltenango', 'Quetzaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (101, '12a Avenida 165-61 Zona 9', 'Puerto Barrios', 'Izabal', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (102, '18a Avenida 85-24 Zona 1', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (103, '6a Avenida 149-14 Zona 5', 'Puerto Barrios', 'Izabal', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (104, '20a Avenida 112-50 Zona 6', 'Chiquimula', 'Chiquimula', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (105, '20a Avenida 131-59 Zona 2', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (106, '7a Avenida 66-65 Zona 1', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (107, '17a Avenida 138-95 Zona 11', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (108, '12a Avenida 111-95 Zona 2', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (109, '20a Avenida 81-25 Zona 11', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (110, '17a Avenida 80-62 Zona 11', 'Jalapa', 'Jalapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (111, '13a Avenida 179-80 Zona 5', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (112, '7a Avenida 108-58 Zona 11', 'Guastatoya', 'El Progreso', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (113, '6a Avenida 158-48 Zona 10', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (114, '18a Avenida 1-46 Zona 5', 'Quetzaltenango', 'Quetzaltenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (115, '14a Avenida 149-93 Zona 10', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (116, '15a Avenida 114-96 Zona 8', 'Jutiapa', 'Jutiapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (117, '17a Avenida 122-31 Zona 13', 'Ciudad de Guatemala', 'Guatemala', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (118, '3a Avenida 73-94 Zona 9', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (119, '20a Avenida 86-40 Zona 2', 'Totonicapán', 'Totonicapán', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (120, '10a Avenida 58-35 Zona 13', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (121, '1a Avenida 12-70 Zona 4', 'Guastatoya', 'El Progreso', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (122, '3a Avenida 117-90 Zona 7', 'Mazatenango', 'Suchitepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (123, '7a Avenida 184-59 Zona 12', 'Sololá', 'Sololá', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (124, '13a Avenida 63-93 Zona 3', 'Antigua Guatemala', 'Sacatepéquez', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (125, '4a Avenida 200-38 Zona 7', 'Cobán', 'Alta Verapaz', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (126, '17a Avenida 119-81 Zona 1', 'Escuintla', 'Escuintla', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (127, '4a Avenida 117-69 Zona 3', 'Huehuetenango', 'Huehuetenango', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (128, '17a Avenida 144-50 Zona 10', 'Zacapa', 'Zacapa', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (129, '20a Avenida 185-74 Zona 15', 'Retalhuleu', 'Retalhuleu', 'Guatemala');
INSERT INTO dbo.dbr_direccion (direccion_id, calle, ciudad, departamento, pais)
VALUES (130, '18a Avenida 115-30 Zona 15', 'Santa Cruz del Quiché', 'Quiché', 'Guatemala');
SET IDENTITY_INSERT dbo.dbr_direccion OFF;
GO

SET IDENTITY_INSERT dbo.dbr_agencia ON;

INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (1, 'Agencia Cobán', 1, 'Sandra González', '+502 37394050');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (2, 'Agencia Salamá', 2, 'Miguel Morales', '+502 54983838');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (3, 'Agencia Chimaltenango', 3, 'Sandra Hernández', '+502 38427922');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (4, 'Agencia Chiquimula', 4, 'Marta Pérez', '+502 39174891');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (5, 'Agencia Guastatoya', 5, 'Miguel Morales', '+502 42538346');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (6, 'Agencia Escuintla', 6, 'María Vásquez', '+502 25407475');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (7, 'Agencia Ciudad de Guatemala', 7, 'Pedro García', '+502 35519695');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (8, 'Agencia Huehuetenango', 8, 'Juana García', '+502 34358134');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (9, 'Agencia Puerto Barrios', 9, 'Carlos Gómez', '+502 47353530');
INSERT INTO dbo.dbr_agencia (agencia_id, nombre, direccion_id, gerente, telefono_contacto)
VALUES (10, 'Agencia Jalapa', 10, 'María Vásquez', '+502 51267650');
SET IDENTITY_INSERT dbo.dbr_agencia OFF;
GO

SET IDENTITY_INSERT dbo.dbr_cliente ON;

INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (1, 'I', 'Rosa', 'López', NULL, '6690967054668', '89373467', '1968-07-22', 'F', '+502 31947822', 11,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (2, 'I', 'Juana', 'Ramírez', NULL, '2729806990162', '72046537', '1986-04-10', 'F', '+502 51934250', 12,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (3, 'I', 'María', 'Gómez', NULL, '6417080531003', '30923271', '1974-12-18', 'F', '+502 67847357', 13,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (4, 'I', 'Mario', 'González', NULL, '5299124190496', '63193149', '1972-12-27', 'M', '+502 38123867', 14,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (5, 'I', 'Claudia', 'López', NULL, '8651850671657', '26284987', '1981-02-24', 'F', '+502 61197150', 15,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (6, 'I', 'Rosa', 'Caal', NULL, '5314737996507', '52735454', '1974-01-29', 'F', '+502 70007285', 16,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (7, 'I', 'Jorge', 'Vásquez', NULL, '8313678377701', '43634957', '1950-11-29', 'M', '+502 67142941', 17,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (8, 'I', 'Irma', 'Ramírez', NULL, '8557444313518', '23374989', '1988-03-04', 'F', '+502 48991721', 18,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (9, 'I', 'Luis', 'Hernández', NULL, '3524082400842', '71094777', '1976-07-30', 'M', '+502 52864388', 19,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (10, 'I', 'Francisco', 'López', NULL, '7116719022941', '31869993', '1972-08-26', 'M', '+502 65069249', 20,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (11, 'I', 'Juana', 'González', NULL, '4964990913341', '23281206', '1989-09-20', 'F', '+502 60232791', 21,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (12, 'I', 'Sandra', 'Morales', NULL, '3447134936183', '24210249', '1952-12-05', 'F', '+502 68198838', 22,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (13, 'I', 'Edgar', 'González', NULL, '7464887719065', '94013990', '1961-02-26', 'M', '+502 75116053', 23,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (14, 'I', 'Jorge', 'Caal', NULL, '2787429671756', '55125674', '1953-08-11', 'M', '+502 74465228', 24,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (15, 'I', 'Juana', 'Vásquez', NULL, '7154516808760', '38597703', '1953-04-17', 'F', '+502 47921840', 25,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (16, 'I', 'Brenda', 'García', NULL, '7710932480861', '31712748', '1975-11-04', 'F', '+502 77339373', 26,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (17, 'I', 'Jorge', 'Gómez', NULL, '7378263982146', '58404499', '1993-04-15', 'M', '+502 74287874', 27,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (18, 'I', 'Sandra', 'García', NULL, '8755886753396', '36057662', '1990-01-23', 'F', '+502 63240942', 28,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (19, 'I', 'Juan', 'García', NULL, '9517187026217', '45961586', '1995-01-24', 'M', '+502 51250770', 29,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (20, 'I', 'Sandra', 'Vásquez', NULL, '9134316117240', '05045562', '1953-03-22', 'F', '+502 46387812', 30,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (21, 'I', 'Irma', 'Gómez', NULL, '2221969379237', '47407482', '2000-10-09', 'F', '+502 34956788', 31,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (22, 'I', 'Marta', 'Ramírez', NULL, '4647436713695', '94406409', '2002-09-18', 'F', '+502 76023224', 32,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (23, 'I', 'Juan', 'Caal', NULL, '4395339421047', '09521456', '1994-07-25', 'M', '+502 41787005', 33,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (24, 'I', 'Mario', 'García', NULL, '5884247451712', '36851604', '1998-05-24', 'M', '+502 66008758', 34,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (25, 'I', 'Luis', 'González', NULL, '4965137098593', '17461200', '1983-01-25', 'M', '+502 50425561', 35,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (26, 'I', 'Sandra', 'Pérez', NULL, '3826758692617', '96405377', '1958-09-20', 'F', '+502 45845250', 36,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (27, 'I', 'Ana', 'Pérez', NULL, '8506431713900', '53293183', '1982-12-15', 'F', '+502 69351502', 37,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (28, 'I', 'Mario', 'Hernández', NULL, '2904228421020', '53950240', '1979-06-24', 'M', '+502 38506621', 38,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (29, 'I', 'Rosa', 'Vásquez', NULL, '1775891783908', '47007661', '1960-03-13', 'F', '+502 62901385', 39,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (30, 'I', 'Marta', 'Pérez', NULL, '5921249985698', '47896118', '1957-04-01', 'F', '+502 78374747', 40,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (31, 'I', 'Mario', 'Gómez', NULL, '3657661565452', '71111615', '1990-07-06', 'M', '+502 38731900', 41,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (32, 'I', 'Brenda', 'López', NULL, '8851656049451', '98327315', '2002-08-13', 'F', '+502 67330344', 42,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (33, 'I', 'Ana', 'Pérez', NULL, '9368998094024', '45502296', '1974-12-29', 'F', '+502 34669798', 43,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (34, 'I', 'Pedro', 'López', NULL, '8366752545991', '02290147', '1958-03-26', 'M', '+502 74421953', 44,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (35, 'I', 'Rosa', 'González', NULL, '7643815614978', '40369003', '2004-06-18', 'F', '+502 50227910', 45,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (36, 'I', 'Mario', 'García', NULL, '4510762268388', '51606071', '1972-12-03', 'M', '+502 51009143', 46,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (37, 'I', 'Claudia', 'Gómez', NULL, '6641605297516', '13696816', '2001-06-11', 'F', '+502 50822173', 47,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (38, 'I', 'María', 'Hernández', NULL, '2181883552312', '43292127', '1979-11-18', 'F', '+502 61135363', 48,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (39, 'I', 'Claudia', 'Caal', NULL, '9955271774490', '58147700', '1990-04-10', 'F', '+502 54745561', 49,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (40, 'I', 'Edgar', 'Pérez', NULL, '9986798079359', '78207151', '1958-02-06', 'M', '+502 63859710', 50,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (41, 'I', 'Francisco', 'López', NULL, '7788925546659', '05151864', '1972-03-24', 'M', '+502 46911150', 51,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (42, 'I', 'Pedro', 'Ramírez', NULL, '9254629148652', '81685054', '1957-04-24', 'M', '+502 42097239', 52,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (43, 'I', 'Mario', 'Ramírez', NULL, '3322141888059', '29622292', '1993-08-17', 'M', '+502 78397771', 53,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (44, 'I', 'Marta', 'López', NULL, '5379473834735', '97746886', '1986-11-11', 'F', '+502 40875539', 54,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (45, 'I', 'Mario', 'Caal', NULL, '4075818141247', '82613750', '1962-06-02', 'M', '+502 57843260', 55,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (46, 'I', 'Juan', 'Gómez', NULL, '5361530515220', '47277901', '1995-01-14', 'M', '+502 31275329', 56,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (47, 'I', 'Jorge', 'Hernández', NULL, '8986143410369', '71179808', '1963-06-01', 'M', '+502 68590781', 57,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (48, 'I', 'Miguel', 'García', NULL, '6095396218518', '88880670', '1976-02-18', 'M', '+502 72659144', 58,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (49, 'I', 'Juana', 'Ramírez', NULL, '0515319520585', '27722170', '1972-10-03', 'F', '+502 49692597', 59,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (50, 'I', 'Mario', 'López', NULL, '0548687403450', '54156676', '1967-11-24', 'M', '+502 52752362', 60,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (51, 'I', 'Francisco', 'González', NULL, '5841616928451', '15447962', '1994-08-20', 'M', '+502 76289332', 61,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (52, 'I', 'Marta', 'Ramírez', NULL, '0596401658202', '97021355', '1990-02-11', 'F', '+502 55692923', 62,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (53, 'I', 'Claudia', 'López', NULL, '2755719285654', '31027868', '2004-04-14', 'F', '+502 37902806', 63,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (54, 'I', 'Jorge', 'Morales', NULL, '3947312172715', '51884422', '1990-01-14', 'M', '+502 54259329', 64,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (55, 'I', 'Irma', 'Hernández', NULL, '3237058957829', '11467866', '1960-11-20', 'F', '+502 68580920', 65,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (56, 'I', 'Carlos', 'García', NULL, '1778528922680', '18242253', '1978-06-11', 'M', '+502 53221215', 66,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (57, 'I', 'Irma', 'Morales', NULL, '4384249818299', '22995900', '1957-01-28', 'F', '+502 35450773', 67,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (58, 'I', 'Juan', 'Caal', NULL, '3969078447364', '71027677', '1973-09-29', 'M', '+502 43691752', 68,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (59, 'I', 'María', 'Caal', NULL, '5556258815371', '47321046', '1962-11-21', 'F', '+502 71297281', 69,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (60, 'I', 'Rosa', 'Hernández', NULL, '5953278774701', '68733950', '1964-04-30', 'F', '+502 33391709', 70,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (61, 'I', 'Edgar', 'González', NULL, '7480162456506', '09835841', '2003-08-10', 'M', '+502 55927430', 71,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (62, 'I', 'Irma', 'González', NULL, '4991216558523', '98680002', '1999-05-01', 'F', '+502 77888338', 72,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (63, 'I', 'María', 'González', NULL, '7298259526949', '58887947', '1996-08-04', 'F', '+502 31116487', 73,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (64, 'I', 'Ana', 'Ramírez', NULL, '6940974993097', '28962309', '1959-11-01', 'F', '+502 77011162', 74,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (65, 'I', 'Luis', 'Hernández', NULL, '7562636897028', '38578652', '1951-09-13', 'M', '+502 60847497', 75,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (66, 'I', 'Brenda', 'Ramírez', NULL, '5497334843443', '75758441', '1999-01-04', 'F', '+502 68485376', 76,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (67, 'I', 'Brenda', 'Gómez', NULL, '5240415747338', '48421993', '1985-05-25', 'F', '+502 46271083', 77,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (68, 'I', 'Juan', 'Vásquez', NULL, '3016571208267', '73454019', '1970-03-31', 'M', '+502 45584033', 78,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (69, 'I', 'Brenda', 'López', NULL, '6206724004991', '54788728', '1965-09-15', 'F', '+502 61408342', 79,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (70, 'I', 'Jorge', 'Hernández', NULL, '5274205493296', '68516122', '1960-02-09', 'M', '+502 62041402', 80,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (71, 'I', 'María', 'Hernández', NULL, '4637454990453', '01742684', '1950-08-12', 'F', '+502 76324603', 81,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (72, 'I', 'Luis', 'Morales', NULL, '9332727956878', '33918785', '1982-12-22', 'M', '+502 35241384', 82,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (73, 'I', 'Claudia', 'Pérez', NULL, '8839822587139', '71870728', '1955-07-17', 'F', '+502 57878671', 83,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (74, 'I', 'Marta', 'Caal', NULL, '8740640391065', '18017046', '1955-03-07', 'F', '+502 42078342', 84,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (75, 'I', 'Pedro', 'Gómez', NULL, '6766182512868', '23004786', '1983-08-06', 'M', '+502 65697460', 85,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (76, 'I', 'Juana', 'Hernández', NULL, '7524310690331', '19079030', '1972-03-16', 'F', '+502 56995570', 86,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (77, 'I', 'Marta', 'Hernández', NULL, '3028439599534', '28364408', '1998-06-04', 'F', '+502 69706108', 87,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (78, 'I', 'Francisco', 'Gómez', NULL, '7056856624628', '73342708', '1999-11-14', 'M', '+502 57694317', 88,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (79, 'I', 'Rosa', 'Vásquez', NULL, '2634351751830', '46990139', '1997-07-19', 'F', '+502 78607301', 89,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (80, 'I', 'Brenda', 'Hernández', NULL, '3540331739363', '85467854', '1993-01-03', 'F', '+502 47553103', 90,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (81, 'I', 'Ana', 'Vásquez', NULL, '7175355609320', '48996423', '1994-08-12', 'F', '+502 52136884', 91,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (82, 'I', 'Miguel', 'Gómez', NULL, '3785477725228', '72808010', '2001-02-12', 'M', '+502 30428411', 92,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (83, 'I', 'Rosa', 'García', NULL, '1203875099770', '08860084', '1970-10-06', 'F', '+502 65952775', 93,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (84, 'I', 'Edgar', 'López', NULL, '6211823398454', '61567933', '1995-01-21', 'M', '+502 50130957', 94,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (85, 'I', 'Carlos', 'López', NULL, '6668700217659', '18033974', '1958-05-22', 'M', '+502 33124720', 95,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (86, 'I', 'Carlos', 'Morales', NULL, '9025039261429', '39685621', '1998-09-20', 'M', '+502 63607639', 96,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (87, 'I', 'Ana', 'López', NULL, '6315999650477', '35866296', '1958-10-06', 'F', '+502 35750834', 97,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (88, 'I', 'Edgar', 'Hernández', NULL, '1426265511047', '54121267', '1956-08-05', 'M', '+502 67378632', 98,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (89, 'I', 'Brenda', 'Vásquez', NULL, '1015819956046', '61839826', '1986-08-10', 'F', '+502 41375069', 99,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (90, 'I', 'Pedro', 'Morales', NULL, '4721264647154', '37993712', '1977-01-06', 'M', '+502 50445252', 100,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (91, 'I', 'José', 'Gómez', NULL, '9657569245937', '52654793', '1979-10-22', 'M', '+502 51869855', 101,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (92, 'I', 'Juana', 'Morales', NULL, '5193982807374', '16724342', '1985-04-02', 'F', '+502 77998701', 102,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (93, 'I', 'Rosa', 'Gómez', NULL, '7979688680589', '11352909', '1956-08-20', 'F', '+502 73287311', 103,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (94, 'I', 'Juana', 'Ramírez', NULL, '1014388899375', '67982507', '1988-08-14', 'F', '+502 37016188', 104,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (95, 'I', 'Edgar', 'Gómez', NULL, '1254573875717', '75140105', '1957-09-14', 'M', '+502 73484525', 105,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (96, 'I', 'Luis', 'García', NULL, '8282586736226', '60937966', '1971-11-19', 'M', '+502 30298637', 106,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (97, 'I', 'Mario', 'Hernández', NULL, '1918255371478', '59696915', '1974-12-21', 'M', '+502 53621308', 107,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (98, 'I', 'Marta', 'Caal', NULL, '4991251341252', '86692966', '1965-06-24', 'F', '+502 42465719', 108,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (99, 'I', 'Sandra', 'Vásquez', NULL, '8274225790507', '23688767', '1965-07-17', 'F', '+502 57892486', 109,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (100, 'I', 'Marta', 'González', NULL, '1903404384279', '78819148', '1965-01-02', 'F', '+502 54619676', 110,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (101, 'J', NULL, NULL, 'Inversiones Vásquez S.A.', NULL, '78361340', NULL, NULL, '+502 50181026', 111,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (102, 'J', NULL, NULL, 'Construcciones Morales S.A.', NULL, '17133959', NULL, NULL, '+502 62464518', 112,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (103, 'J', NULL, NULL, 'Servicios Gómez S.A.', NULL, '92330958', NULL, NULL, '+502 38863296', 113, SYSDATETIME(),
        SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (104, 'J', NULL, NULL, 'Consultores Caal S.A.', NULL, '25449481', NULL, NULL, '+502 29099217', 114,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (105, 'J', NULL, NULL, 'Inversiones Gómez S.A.', NULL, '42232536', NULL, NULL, '+502 52847019', 115,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (106, 'J', NULL, NULL, 'Transportes García S.A.', NULL, '66711684', NULL, NULL, '+502 66620770', 116,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (107, 'J', NULL, NULL, 'Distribuidora Ramírez S.A.', NULL, '75901751', NULL, NULL, '+502 73397041', 117,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (108, 'J', NULL, NULL, 'Alimentos Vásquez S.A.', NULL, '36374545', NULL, NULL, '+502 56729388', 118,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (109, 'J', NULL, NULL, 'Servicios Caal S.A.', NULL, '97500170', NULL, NULL, '+502 28337415', 119, SYSDATETIME(),
        SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (110, 'J', NULL, NULL, 'Distribuidora García S.A.', NULL, '70632424', NULL, NULL, '+502 26263940', 120,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (111, 'J', NULL, NULL, 'Transportes Ramírez S.A.', NULL, '15206436', NULL, NULL, '+502 63988869', 121,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (112, 'J', NULL, NULL, 'Comercial Pérez S.A.', NULL, '03712938', NULL, NULL, '+502 65632868', 122, SYSDATETIME(),
        SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (113, 'J', NULL, NULL, 'Inversiones González S.A.', NULL, '05162713', NULL, NULL, '+502 45707387', 123,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (114, 'J', NULL, NULL, 'Comercial Pérez S.A.', NULL, '15542622', NULL, NULL, '+502 24591025', 124, SYSDATETIME(),
        SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (115, 'J', NULL, NULL, 'Inversiones Vásquez S.A.', NULL, '92753269', NULL, NULL, '+502 66074675', 125,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (116, 'J', NULL, NULL, 'Tecnologías González S.A.', NULL, '11219656', NULL, NULL, '+502 41105983', 126,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (117, 'J', NULL, NULL, 'Tecnologías García S.A.', NULL, '41389994', NULL, NULL, '+502 72275768', 127,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (118, 'J', NULL, NULL, 'Transportes López S.A.', NULL, '38983640', NULL, NULL, '+502 72600034', 128,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (119, 'J', NULL, NULL, 'Distribuidora Hernández S.A.', NULL, '61379180', NULL, NULL, '+502 44232890', 129,
        SYSDATETIME(), SYSDATETIME());
INSERT INTO dbo.dbr_cliente (cliente_id, tipo_cliente, nombre, apellido, razon_social, dpi, nit, fecha_nacimiento,
                             genero, telefono_contacto, direccion_id, creado_en, actualizado_en)
VALUES (120, 'J', NULL, NULL, 'Servicios Ramírez S.A.', NULL, '69658271', NULL, NULL, '+502 21120006', 130,
        SYSDATETIME(), SYSDATETIME());
SET IDENTITY_INSERT dbo.dbr_cliente OFF;
GO

SET IDENTITY_INSERT dbo.dbr_producto ON;

INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (1, 'cuenta_monetaria', '2126077199', 1, '2019-03-23', 'GTQ', 'activo', 46167.67, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (2, 'remesa', '8589679668', 2, '2021-05-17', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (3, 'cuenta_monetaria', '5950724801', 2, '2019-06-21', 'GTQ', 'cerrado', 15840.39, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (4, 'cuenta_monetaria', '7598745558', 3, '2021-03-11', 'GTQ', 'activo', 29528.64, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (5, 'remesa', '2024939794', 4, '2020-05-15', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (6, 'prestamo', '5793125884', 4, '2022-06-07', 'GTQ', 'activo', 125678.16, 9.64);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (7, 'cuenta_monetaria', '4040409964', 5, '2022-12-07', 'GTQ', 'activo', 1061.85, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (8, 'remesa', '2113457241', 6, '2021-01-31', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (9, 'remesa', '4807122420', 6, '2023-04-29', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (10, 'prestamo', '5569295400', 7, '2022-12-29', 'GTQ', 'activo', 195259.61, 14.41);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (11, 'prestamo', '7488758768', 7, '2019-04-24', 'GTQ', 'activo', 104925.9, 13.5);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (12, 'prestamo', '4321422584', 8, '2022-03-21', 'GTQ', 'cerrado', 138082.88, 6.73);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (13, 'cuenta_monetaria', '1052776893', 9, '2019-04-05', 'GTQ', 'activo', 23852.35, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (14, 'cuenta_monetaria', '4682870880', 10, '2022-02-06', 'GTQ', 'activo', 40254.22, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (15, 'prestamo', '6361249549', 11, '2023-01-15', 'GTQ', 'moroso', 70787.68, 17.39);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (16, 'cuenta_monetaria', '4873807154', 12, '2020-01-03', 'GTQ', 'cerrado', 11547.66, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (17, 'cuenta_monetaria', '9392707144', 12, '2019-05-22', 'GTQ', 'activo', 43911.07, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (18, 'prestamo', '9960957575', 13, '2021-07-24', 'GTQ', 'moroso', 11514.14, 8.01);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (19, 'prestamo', '6336857629', 13, '2021-01-24', 'GTQ', 'activo', 122421.28, 12.4);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (20, 'cuenta_monetaria', '2761091683', 14, '2020-04-22', 'GTQ', 'activo', 27306.49, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (21, 'cuenta_monetaria', '2320748157', 15, '2020-02-25', 'GTQ', 'activo', 26725.82, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (22, 'prestamo', '5281907480', 15, '2022-12-28', 'GTQ', 'activo', 63166.8, 5.66);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (23, 'remesa', '9141445255', 16, '2021-07-27', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (24, 'remesa', '8816681105', 16, '2019-06-03', 'GTQ', 'moroso', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (25, 'prestamo', '1561387824', 17, '2020-08-20', 'GTQ', 'activo', 59588.28, 9.73);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (26, 'prestamo', '7239547458', 18, '2020-04-23', 'GTQ', 'moroso', 24190.61, 8.04);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (27, 'cuenta_monetaria', '1667483244', 18, '2019-12-03', 'GTQ', 'activo', 22753.55, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (28, 'cuenta_monetaria', '7596745715', 19, '2023-04-27', 'GTQ', 'activo', 10777.99, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (29, 'prestamo', '1515024824', 19, '2019-11-19', 'GTQ', 'moroso', 163443.41, 9.56);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (30, 'cuenta_monetaria', '2407863065', 20, '2019-07-06', 'GTQ', 'activo', 35702.29, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (31, 'remesa', '9800175892', 21, '2020-09-04', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (32, 'cuenta_monetaria', '2073108894', 21, '2021-08-04', 'GTQ', 'activo', 5544.41, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (33, 'cuenta_monetaria', '1954720281', 22, '2020-02-10', 'GTQ', 'activo', 41271.83, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (34, 'remesa', '7812328180', 23, '2023-07-23', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (35, 'cuenta_monetaria', '8069459895', 24, '2023-07-16', 'GTQ', 'activo', 6875.18, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (36, 'cuenta_monetaria', '9342031932', 25, '2019-04-14', 'GTQ', 'moroso', 8815.47, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (37, 'remesa', '6991473746', 26, '2019-03-02', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (38, 'remesa', '2832508021', 26, '2020-12-25', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (39, 'prestamo', '6496933442', 27, '2023-12-15', 'GTQ', 'moroso', 38239.97, 14.21);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (40, 'remesa', '6562434335', 28, '2021-04-23', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (41, 'cuenta_monetaria', '5671728485', 29, '2021-02-23', 'GTQ', 'activo', 7293.18, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (42, 'remesa', '3258354191', 29, '2022-07-15', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (43, 'prestamo', '6837342064', 30, '2022-01-20', 'GTQ', 'moroso', 158472.67, 10.16);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (44, 'prestamo', '2161512446', 31, '2019-02-23', 'GTQ', 'activo', 70586.74, 8.29);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (45, 'cuenta_monetaria', '1685583357', 31, '2020-05-22', 'GTQ', 'activo', 33014.79, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (46, 'cuenta_monetaria', '6963229328', 32, '2023-09-15', 'GTQ', 'activo', 49581.33, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (47, 'cuenta_monetaria', '7839819230', 33, '2023-07-10', 'GTQ', 'activo', 37036.2, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (48, 'remesa', '8303853049', 34, '2022-03-08', 'GTQ', 'moroso', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (49, 'remesa', '5073211715', 35, '2023-09-10', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (50, 'cuenta_monetaria', '3106408413', 36, '2019-07-04', 'GTQ', 'moroso', 3280.31, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (51, 'cuenta_monetaria', '9675524665', 36, '2021-09-05', 'GTQ', 'moroso', 533.83, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (52, 'cuenta_monetaria', '9023931339', 37, '2019-05-02', 'GTQ', 'moroso', 1584.69, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (53, 'cuenta_monetaria', '8991514523', 38, '2019-05-29', 'GTQ', 'activo', 18992.74, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (54, 'prestamo', '6591038760', 39, '2019-10-07', 'GTQ', 'activo', 195413.53, 15.99);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (55, 'remesa', '2362721798', 40, '2022-12-19', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (56, 'remesa', '2532554057', 40, '2022-09-25', 'GTQ', 'moroso', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (57, 'prestamo', '8252045593', 41, '2019-09-18', 'GTQ', 'moroso', 43764.57, 5.03);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (58, 'remesa', '1139082827', 42, '2022-05-18', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (59, 'remesa', '3429019820', 42, '2021-10-13', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (60, 'remesa', '1334176969', 43, '2020-12-11', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (61, 'cuenta_monetaria', '5136395494', 43, '2023-08-10', 'GTQ', 'activo', 35593.81, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (62, 'cuenta_monetaria', '2139078760', 44, '2020-05-26', 'GTQ', 'activo', 34812.22, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (63, 'prestamo', '4380225197', 44, '2023-01-15', 'GTQ', 'activo', 10243.42, 10.79);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (64, 'prestamo', '6921525436', 45, '2022-01-23', 'GTQ', 'moroso', 81316.04, 17.43);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (65, 'cuenta_monetaria', '2938264714', 46, '2023-06-25', 'GTQ', 'activo', 42365.24, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (66, 'prestamo', '1449790661', 47, '2020-12-01', 'GTQ', 'activo', 42319.99, 10.63);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (67, 'prestamo', '5428082088', 48, '2022-08-31', 'GTQ', 'activo', 41349.47, 18.35);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (68, 'cuenta_monetaria', '2422040412', 49, '2020-01-25', 'GTQ', 'cerrado', 20759.35, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (69, 'remesa', '6504099682', 50, '2020-05-01', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (70, 'cuenta_monetaria', '3108606793', 50, '2019-04-22', 'GTQ', 'activo', 18361.03, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (71, 'prestamo', '3062994753', 51, '2019-07-18', 'GTQ', 'activo', 14889.78, 7.56);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (72, 'prestamo', '4623960580', 52, '2020-09-23', 'GTQ', 'activo', 159126.55, 12.06);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (73, 'remesa', '7631970791', 53, '2020-01-14', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (74, 'prestamo', '6096334921', 54, '2019-04-02', 'GTQ', 'activo', 60026.23, 11.98);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (75, 'prestamo', '3423420650', 54, '2019-11-06', 'GTQ', 'activo', 152924.68, 15.01);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (76, 'remesa', '7539441086', 55, '2022-01-01', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (77, 'remesa', '4786674545', 55, '2021-09-02', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (78, 'prestamo', '4067919621', 56, '2021-10-25', 'GTQ', 'moroso', 118531.79, 12.75);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (79, 'cuenta_monetaria', '2928610987', 57, '2019-12-09', 'GTQ', 'activo', 48622.16, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (80, 'cuenta_monetaria', '2818381356', 58, '2022-10-31', 'GTQ', 'activo', 22051.97, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (81, 'prestamo', '1287814151', 59, '2021-03-05', 'GTQ', 'activo', 115709.2, 13.28);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (82, 'remesa', '4751509023', 59, '2023-05-30', 'GTQ', 'moroso', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (83, 'cuenta_monetaria', '2780016559', 60, '2019-10-31', 'GTQ', 'moroso', 28546.4, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (84, 'cuenta_monetaria', '4972536230', 60, '2022-02-26', 'GTQ', 'activo', 39087.46, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (85, 'prestamo', '6429425484', 61, '2022-09-03', 'GTQ', 'activo', 102261.11, 14.13);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (86, 'cuenta_monetaria', '6477862024', 61, '2019-10-22', 'GTQ', 'activo', 31103.1, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (87, 'prestamo', '2020395327', 62, '2023-03-08', 'GTQ', 'activo', 100291.46, 9.03);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (88, 'prestamo', '6596578419', 63, '2020-07-28', 'GTQ', 'activo', 170140.85, 17.87);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (89, 'cuenta_monetaria', '8489236010', 64, '2023-05-05', 'GTQ', 'activo', 41378.25, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (90, 'remesa', '3772636814', 65, '2020-01-20', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (91, 'cuenta_monetaria', '9831336766', 65, '2023-06-09', 'GTQ', 'activo', 8369.14, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (92, 'cuenta_monetaria', '3442428958', 66, '2019-12-22', 'GTQ', 'activo', 10041.79, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (93, 'cuenta_monetaria', '2071552532', 66, '2021-07-23', 'GTQ', 'activo', 3002.68, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (94, 'prestamo', '4964570811', 67, '2022-10-27', 'GTQ', 'moroso', 15807.01, 10.59);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (95, 'cuenta_monetaria', '7662927609', 68, '2020-12-06', 'GTQ', 'activo', 8593.92, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (96, 'remesa', '5683197659', 68, '2019-02-26', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (97, 'cuenta_monetaria', '6182870116', 69, '2022-08-27', 'GTQ', 'activo', 20770.61, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (98, 'prestamo', '4914929023', 70, '2022-08-18', 'GTQ', 'activo', 42908.12, 17.01);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (99, 'remesa', '8055515912', 71, '2021-05-17', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (100, 'prestamo', '7266348777', 71, '2020-03-22', 'GTQ', 'moroso', 98672.62, 15.16);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (101, 'remesa', '1439427140', 72, '2021-11-13', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (102, 'remesa', '7910817577', 72, '2020-09-03', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (103, 'cuenta_monetaria', '6484179008', 73, '2022-09-05', 'GTQ', 'activo', 35699.14, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (104, 'cuenta_monetaria', '4287687478', 73, '2019-04-27', 'GTQ', 'moroso', 40368.78, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (105, 'remesa', '9699264134', 74, '2021-10-15', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (106, 'prestamo', '9190122806', 74, '2021-04-08', 'GTQ', 'moroso', 83772.23, 5.53);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (107, 'prestamo', '8666074487', 75, '2022-10-07', 'GTQ', 'activo', 78114.46, 9.5);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (108, 'prestamo', '5714169271', 76, '2019-09-20', 'GTQ', 'cerrado', 150774.59, 15.88);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (109, 'remesa', '9158681911', 77, '2022-09-02', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (110, 'prestamo', '9037740227', 78, '2021-05-11', 'GTQ', 'activo', 159737.18, 9.97);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (111, 'prestamo', '4655935832', 79, '2021-08-21', 'GTQ', 'moroso', 20198.62, 14.52);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (112, 'remesa', '5600836559', 79, '2023-12-27', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (113, 'remesa', '6576395496', 80, '2019-04-21', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (114, 'cuenta_monetaria', '6766723248', 81, '2022-03-12', 'GTQ', 'activo', 44695.83, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (115, 'prestamo', '5642049890', 82, '2020-11-12', 'GTQ', 'activo', 129896.23, 7.65);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (116, 'prestamo', '2174793230', 83, '2023-04-08', 'GTQ', 'activo', 156973.03, 13.64);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (117, 'cuenta_monetaria', '7139268005', 84, '2021-05-28', 'GTQ', 'activo', 48283.73, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (118, 'cuenta_monetaria', '9751963589', 84, '2020-02-13', 'GTQ', 'activo', 36667.62, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (119, 'remesa', '1818520766', 85, '2022-10-17', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (120, 'remesa', '4150801944', 85, '2020-04-08', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (121, 'cuenta_monetaria', '5736095750', 86, '2021-10-27', 'GTQ', 'activo', 29639.2, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (122, 'cuenta_monetaria', '4538382315', 86, '2020-09-02', 'GTQ', 'activo', 47448.94, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (123, 'prestamo', '5275521470', 87, '2020-12-02', 'GTQ', 'activo', 199266.39, 12.35);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (124, 'cuenta_monetaria', '2732553940', 87, '2020-04-12', 'GTQ', 'activo', 11603.91, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (125, 'remesa', '9684051360', 88, '2021-10-30', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (126, 'prestamo', '4402160254', 89, '2021-02-07', 'GTQ', 'cerrado', 176543.39, 8.84);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (127, 'remesa', '5272119095', 90, '2022-09-17', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (128, 'cuenta_monetaria', '3962452613', 91, '2021-05-03', 'GTQ', 'activo', 22493.56, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (129, 'prestamo', '4014501050', 92, '2020-02-25', 'GTQ', 'activo', 142086.49, 14.45);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (130, 'prestamo', '3841827734', 92, '2022-09-18', 'GTQ', 'activo', 108858.75, 14.34);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (131, 'cuenta_monetaria', '3652992543', 93, '2020-08-01', 'GTQ', 'activo', 6143.62, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (132, 'prestamo', '6161147047', 93, '2022-12-11', 'GTQ', 'cerrado', 87853.68, 7.41);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (133, 'cuenta_monetaria', '7359403225', 94, '2020-04-25', 'GTQ', 'activo', 635.53, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (134, 'cuenta_monetaria', '8168394616', 94, '2019-11-02', 'GTQ', 'cerrado', 47497.58, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (135, 'remesa', '4107736331', 95, '2020-06-08', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (136, 'prestamo', '6429375645', 96, '2019-04-13', 'GTQ', 'activo', 28963.69, 7.62);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (137, 'prestamo', '8201657412', 96, '2021-05-22', 'GTQ', 'activo', 150322.64, 6.42);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (138, 'cuenta_monetaria', '6027311960', 97, '2021-01-02', 'GTQ', 'moroso', 44779.12, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (139, 'remesa', '5694190173', 98, '2023-07-28', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (140, 'cuenta_monetaria', '5783872028', 98, '2021-03-30', 'GTQ', 'activo', 48134.34, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (141, 'remesa', '8948573913', 99, '2023-06-27', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (142, 'remesa', '1716309186', 99, '2019-09-29', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (143, 'cuenta_monetaria', '7832220535', 100, '2023-07-02', 'GTQ', 'activo', 28662.7, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (144, 'remesa', '5856127658', 101, '2021-09-26', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (145, 'prestamo', '2892740043', 101, '2019-05-10', 'GTQ', 'cerrado', 59706.44, 9.71);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (146, 'remesa', '9045090355', 102, '2021-11-29', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (147, 'remesa', '5704029171', 102, '2022-09-17', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (148, 'prestamo', '8049778448', 103, '2019-11-01', 'GTQ', 'moroso', 169416.27, 13.38);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (149, 'cuenta_monetaria', '9639948905', 103, '2019-11-18', 'GTQ', 'activo', 25525.59, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (150, 'prestamo', '4734111722', 103, '2019-06-03', 'GTQ', 'activo', 152771.7, 9.81);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (151, 'cuenta_monetaria', '3177244907', 104, '2022-02-01', 'GTQ', 'activo', 32344.21, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (152, 'cuenta_monetaria', '5633542128', 104, '2021-06-28', 'GTQ', 'activo', 40162.43, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (153, 'cuenta_monetaria', '8973989997', 104, '2021-07-04', 'GTQ', 'activo', 16145.05, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (154, 'cuenta_monetaria', '7027727434', 105, '2019-03-15', 'GTQ', 'activo', 28077.99, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (155, 'cuenta_monetaria', '8033172680', 105, '2023-12-28', 'GTQ', 'activo', 25662.72, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (156, 'prestamo', '7246858055', 106, '2022-02-21', 'GTQ', 'activo', 155809.12, 14.0);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (157, 'remesa', '2943612110', 106, '2019-07-19', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (158, 'cuenta_monetaria', '6761084958', 106, '2023-08-27', 'GTQ', 'activo', 31866.23, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (159, 'remesa', '1456650521', 107, '2019-12-03', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (160, 'cuenta_monetaria', '2757546829', 107, '2020-06-04', 'GTQ', 'activo', 30737.16, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (161, 'cuenta_monetaria', '2687477596', 107, '2021-07-25', 'GTQ', 'activo', 41315.43, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (162, 'cuenta_monetaria', '8546898960', 108, '2019-04-06', 'GTQ', 'moroso', 46368.01, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (163, 'cuenta_monetaria', '7229869819', 108, '2022-09-10', 'GTQ', 'cerrado', 29671.15, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (164, 'cuenta_monetaria', '9434691954', 108, '2019-01-09', 'GTQ', 'activo', 26753.04, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (165, 'remesa', '3484872186', 109, '2023-02-05', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (166, 'cuenta_monetaria', '9086117171', 109, '2021-10-29', 'GTQ', 'activo', 44128.83, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (167, 'remesa', '4274374218', 109, '2020-07-14', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (168, 'prestamo', '1572827654', 110, '2021-04-25', 'GTQ', 'cerrado', 124479.65, 18.3);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (169, 'prestamo', '1933479178', 110, '2020-03-05', 'GTQ', 'activo', 128591.84, 9.36);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (170, 'remesa', '8030335064', 110, '2022-12-25', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (171, 'remesa', '8934097788', 111, '2023-07-14', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (172, 'remesa', '1457287198', 111, '2021-02-19', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (173, 'cuenta_monetaria', '3878719791', 111, '2020-02-14', 'GTQ', 'activo', 13715.42, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (174, 'remesa', '2076151332', 112, '2023-09-16', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (175, 'remesa', '8663756690', 112, '2020-02-22', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (176, 'cuenta_monetaria', '2943878598', 112, '2022-06-15', 'GTQ', 'cerrado', 43467.75, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (177, 'remesa', '2670255496', 113, '2021-11-12', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (178, 'remesa', '3853978147', 113, '2021-02-20', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (179, 'remesa', '3371357111', 114, '2019-01-27', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (180, 'cuenta_monetaria', '9032096058', 114, '2023-08-27', 'GTQ', 'activo', 11664.65, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (181, 'remesa', '3591527330', 114, '2023-05-09', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (182, 'prestamo', '3931997465', 115, '2020-01-18', 'GTQ', 'activo', 192870.3, 16.03);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (183, 'prestamo', '5469489987', 115, '2020-07-25', 'GTQ', 'moroso', 115753.74, 6.95);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (184, 'prestamo', '5319212967', 115, '2021-08-13', 'GTQ', 'activo', 144840.97, 7.32);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (185, 'remesa', '8137764127', 116, '2021-10-01', 'GTQ', 'moroso', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (186, 'remesa', '2537965898', 116, '2023-05-25', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (187, 'remesa', '3169561289', 116, '2021-05-01', 'GTQ', 'cerrado', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (188, 'cuenta_monetaria', '2500674245', 117, '2023-12-15', 'GTQ', 'activo', 11061.01, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (189, 'prestamo', '6844582171', 117, '2020-03-23', 'GTQ', 'activo', 190558.57, 14.27);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (190, 'remesa', '1037811610', 117, '2022-10-01', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (191, 'cuenta_monetaria', '3667740351', 118, '2019-03-23', 'GTQ', 'activo', 34286.29, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (192, 'prestamo', '5058691146', 118, '2021-03-01', 'GTQ', 'activo', 58752.21, 15.86);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (193, 'remesa', '7208619610', 118, '2019-03-31', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (194, 'prestamo', '3207160929', 119, '2019-07-16', 'GTQ', 'cerrado', 41805.01, 19.34);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (195, 'remesa', '9621419224', 119, '2019-05-15', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (196, 'remesa', '1446362270', 120, '2022-01-06', 'GTQ', 'activo', 0, NULL);
INSERT INTO dbo.dbr_producto (producto_id, tipo_producto, numero_producto, cliente_id, fecha_apertura, moneda, estado,
                              saldo, tasa_interes)
VALUES (197, 'remesa', '9899689747', 120, '2022-11-06', 'GTQ', 'activo', 0, NULL);
SET IDENTITY_INSERT dbo.dbr_producto OFF;
GO

SET IDENTITY_INSERT dbo.dbr_transaccion ON;

INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1, 1, '2024-04-15 12:04:38', 'deposito', 13219.38, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (2, 1, '2023-07-02 09:10:18', 'comision', 16.34, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (3, 1, '2025-07-21 09:25:01', 'retiro', 58266.09, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (4, 1, '2024-03-19 11:31:11', 'deposito', 58486.33, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (5, 1, '2024-07-01 00:12:53', 'comision', 74.83, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (6, 2, '2023-02-16 02:38:34', 'remesa_pago', 139214.36, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (7, 2, '2023-10-24 10:58:18', 'remesa_envio', 42299.46, 'Envío de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (8, 2, '2024-01-26 14:23:08', 'remesa_envio', 71150.75, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (9, 2, '2023-08-14 04:57:55', 'remesa_pago', 119535.89, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (10, 2, '2023-10-30 23:05:05', 'remesa_envio', 44778.67, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (11, 3, '2024-07-20 20:12:34', 'deposito', 18572.95, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (12, 3, '2024-08-09 21:43:24', 'retiro', 80619.09, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (13, 3, '2023-11-09 07:38:52', 'comision', 76.73, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (14, 3, '2023-08-05 15:01:27', 'comision', 86.63, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (15, 3, '2023-06-14 06:41:56', 'deposito', 92571.05, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (16, 4, '2023-04-28 06:36:10', 'comision', 81.97, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (17, 4, '2025-05-21 19:58:59', 'retiro', 96736.71, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (18, 4, '2023-10-25 02:27:09', 'retiro', 14820.54, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (19, 4, '2024-05-13 12:02:45', 'retiro', 19319.45, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (20, 4, '2023-04-13 10:22:53', 'comision', 16.28, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (21, 4, '2023-11-22 17:41:22', 'retiro', 49319.08, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (22, 4, '2024-12-11 21:16:08', 'deposito', 84876.25, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (23, 4, '2025-04-07 11:31:02', 'retiro', 25379.06, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (24, 5, '2025-03-15 08:03:55', 'remesa_pago', 41574.31, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (25, 5, '2023-05-18 12:04:18', 'remesa_pago', 69480.97, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (26, 6, '2024-05-13 20:05:08', 'pago', 26447.95, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (27, 6, '2023-03-25 10:13:00', 'pago', 133705.43, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (28, 6, '2023-09-27 22:48:52', 'pago', 109141.06, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (29, 6, '2025-05-19 18:27:56', 'pago', 121915.1, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (30, 6, '2024-02-19 21:28:57', 'pago', 135954.91, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (31, 6, '2023-09-24 19:47:13', 'interes', 1009.61, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (32, 6, '2024-01-10 14:17:25', 'pago', 133726.49, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (33, 7, '2023-05-18 16:55:09', 'comision', 55.94, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (34, 7, '2024-01-08 18:17:00', 'deposito', 99435.51, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (35, 7, '2024-12-01 06:02:17', 'comision', 22.63, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (36, 7, '2023-07-03 20:37:13', 'comision', 69.35, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (37, 7, '2025-01-23 17:36:13', 'retiro', 6158.93, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (38, 7, '2023-08-26 02:17:19', 'retiro', 55478.33, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (39, 7, '2024-11-15 07:31:42', 'comision', 91.7, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (40, 7, '2024-02-02 17:06:01', 'retiro', 132244.64, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (41, 7, '2024-10-26 11:47:56', 'deposito', 105590.06, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (42, 8, '2025-05-04 09:35:13', 'remesa_envio', 56561.27, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (43, 8, '2024-01-10 21:23:48', 'remesa_envio', 77547.77, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (44, 8, '2025-07-18 08:06:55', 'remesa_pago', 52999.41, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (45, 9, '2025-03-22 17:33:11', 'remesa_envio', 75325.36, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (46, 9, '2024-03-26 06:01:46', 'remesa_envio', 11655.53, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (47, 9, '2023-08-05 05:28:12', 'remesa_envio', 23687.87, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (48, 9, '2025-01-04 04:18:29', 'remesa_envio', 62250.59, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (49, 10, '2024-05-08 17:25:59', 'interes', 2344.74, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (50, 10, '2024-08-27 05:52:14', 'interes', 2344.74, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (51, 10, '2023-09-07 01:34:15', 'pago', 86065.63, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (52, 10, '2023-05-18 22:55:15', 'pago', 133630.57, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (53, 11, '2023-06-20 09:24:10', 'pago', 77544.44, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (54, 11, '2024-09-05 20:31:12', 'pago', 131788.5, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (55, 11, '2025-08-27 03:07:19', 'pago', 67435.58, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (56, 12, '2023-06-24 07:59:12', 'interes', 774.41, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (57, 12, '2023-05-27 21:12:48', 'pago', 93519.44, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (58, 12, '2023-09-28 06:06:23', 'interes', 774.41, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (59, 12, '2024-09-02 21:30:10', 'pago', 34549.09, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (60, 12, '2023-05-16 03:57:10', 'pago', 30432.05, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (61, 12, '2024-12-01 15:17:03', 'pago', 90866.1, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (62, 12, '2024-05-02 22:22:56', 'pago', 131675.12, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (63, 12, '2024-05-30 04:16:43', 'pago', 72387.92, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (64, 12, '2025-07-12 21:58:18', 'pago', 134555.65, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (65, 12, '2024-06-18 15:18:59', 'interes', 774.41, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (66, 13, '2024-03-15 08:21:19', 'retiro', 118454.38, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (67, 13, '2023-12-25 21:26:47', 'comision', 91.71, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (68, 13, '2023-04-11 15:29:29', 'deposito', 38252.25, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (69, 13, '2025-07-20 03:03:06', 'retiro', 89784.02, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (70, 13, '2024-02-23 09:23:11', 'deposito', 919.87, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (71, 13, '2024-08-14 19:01:30', 'deposito', 78012.3, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (72, 13, '2024-11-01 07:28:44', 'comision', 82.39, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (73, 13, '2024-01-06 03:52:50', 'deposito', 63968.13, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (74, 13, '2023-09-17 09:30:49', 'comision', 48.12, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (75, 13, '2024-09-18 10:01:58', 'comision', 45.77, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (76, 13, '2024-02-28 20:06:05', 'comision', 53.42, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (77, 13, '2024-07-26 20:12:13', 'retiro', 38141.27, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (78, 13, '2024-08-14 12:32:15', 'comision', 45.83, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (79, 14, '2023-05-02 08:21:56', 'retiro', 117488.08, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (80, 14, '2023-04-13 07:48:29', 'comision', 46.05, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (81, 14, '2025-03-31 20:02:45', 'comision', 72.74, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (82, 14, '2023-06-14 14:10:00', 'comision', 10.48, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (83, 14, '2025-04-23 05:17:28', 'retiro', 138886.68, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (84, 14, '2023-04-01 02:19:59', 'retiro', 33343.36, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (85, 14, '2024-09-15 01:22:28', 'comision', 44.59, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (86, 14, '2024-09-20 23:53:26', 'comision', 35.78, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (87, 14, '2023-02-28 06:22:53', 'comision', 54.49, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (88, 14, '2023-07-26 23:54:59', 'comision', 35.74, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (89, 14, '2025-03-13 21:49:39', 'comision', 56.42, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (90, 14, '2024-09-21 06:10:14', 'comision', 13.25, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (91, 14, '2024-11-01 00:00:37', 'deposito', 13117.74, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (92, 14, '2025-03-09 14:32:34', 'retiro', 100482.34, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (93, 14, '2024-08-23 07:17:35', 'comision', 11.38, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (94, 15, '2024-07-16 10:21:29', 'interes', 1025.83, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (95, 15, '2025-04-15 10:04:02', 'pago', 90993.87, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (96, 15, '2024-04-10 14:42:27', 'pago', 39240.02, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (97, 15, '2024-06-02 03:52:34', 'pago', 75525.06, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (98, 16, '2025-04-02 18:41:17', 'retiro', 131429.35, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (99, 16, '2023-09-14 16:07:14', 'retiro', 84518.97, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (100, 16, '2025-02-14 12:22:00', 'retiro', 102271.04, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (101, 16, '2025-06-01 00:59:44', 'retiro', 17528.62, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (102, 16, '2024-01-27 23:04:15', 'deposito', 101569.26, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (103, 16, '2025-03-30 11:29:43', 'retiro', 143321.31, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (104, 17, '2023-01-10 09:35:17', 'deposito', 43164.71, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (105, 17, '2024-11-20 12:27:05', 'deposito', 83227.27, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (106, 17, '2024-05-02 11:25:39', 'retiro', 32863.06, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (107, 17, '2023-10-03 06:39:17', 'comision', 71.48, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (108, 17, '2024-05-25 07:16:10', 'deposito', 110340.82, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (109, 17, '2023-07-31 08:20:42', 'deposito', 125257.58, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (110, 17, '2023-12-31 05:40:46', 'deposito', 18069.79, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (111, 17, '2024-11-23 17:56:14', 'comision', 10.6, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (112, 17, '2023-02-13 17:33:34', 'retiro', 93138.05, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (113, 17, '2025-07-08 20:55:03', 'retiro', 73671.72, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (114, 17, '2023-10-14 14:29:10', 'deposito', 112550.39, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (115, 17, '2023-02-25 19:08:29', 'retiro', 71800.18, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (116, 17, '2023-02-03 18:17:40', 'retiro', 59118.17, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (117, 18, '2023-05-04 18:52:02', 'interes', 76.86, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (118, 18, '2024-12-06 00:18:23', 'pago', 101148.05, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (119, 18, '2024-08-17 03:40:05', 'interes', 76.86, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (120, 18, '2024-09-19 09:27:19', 'pago', 82329.65, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (121, 18, '2023-10-03 17:09:40', 'interes', 76.86, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (122, 18, '2023-07-08 18:09:34', 'interes', 76.86, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (123, 18, '2024-03-05 13:33:19', 'interes', 76.86, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (124, 18, '2023-10-14 16:24:37', 'pago', 85754.32, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (125, 18, '2024-12-03 08:19:18', 'pago', 108150.24, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (126, 18, '2024-07-22 15:44:11', 'interes', 76.86, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (127, 19, '2025-03-30 05:26:41', 'interes', 1265.02, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (128, 19, '2023-06-30 15:20:49', 'interes', 1265.02, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (129, 19, '2025-07-03 22:57:40', 'interes', 1265.02, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (130, 19, '2023-11-04 09:08:15', 'pago', 59820.45, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (131, 19, '2023-03-03 07:50:41', 'interes', 1265.02, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (132, 20, '2023-04-09 16:22:43', 'comision', 40.12, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (133, 20, '2024-01-04 20:24:06', 'comision', 93.87, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (134, 20, '2023-12-19 00:43:19', 'retiro', 18273.5, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (135, 20, '2023-07-23 21:00:09', 'comision', 68.49, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (136, 20, '2023-06-28 10:21:44', 'retiro', 48831.03, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (137, 20, '2024-05-14 16:16:20', 'deposito', 57222.54, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (138, 20, '2024-04-19 22:59:59', 'deposito', 130251.82, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (139, 20, '2024-03-07 22:59:02', 'comision', 61.45, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (140, 20, '2023-03-23 05:53:53', 'retiro', 34309.87, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (141, 20, '2024-10-30 10:36:28', 'comision', 34.07, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (142, 20, '2023-10-05 16:11:53', 'retiro', 112209.54, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (143, 20, '2024-04-06 15:04:22', 'deposito', 27664.54, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (144, 20, '2023-05-09 08:32:33', 'comision', 32.65, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (145, 20, '2023-08-04 06:04:37', 'retiro', 15541.1, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (146, 20, '2025-08-17 17:13:41', 'comision', 14.84, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (147, 21, '2025-02-22 03:01:51', 'deposito', 39441.59, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (148, 21, '2023-03-28 23:50:30', 'retiro', 46474.66, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (149, 21, '2025-01-25 10:20:47', 'retiro', 94009.45, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (150, 21, '2024-06-23 06:12:41', 'deposito', 5369.73, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (151, 21, '2025-05-31 11:50:24', 'retiro', 70132.3, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (152, 21, '2025-08-15 09:55:05', 'comision', 50.04, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (153, 21, '2023-07-01 21:30:41', 'comision', 51.09, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (154, 21, '2024-03-21 19:03:30', 'comision', 67.56, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (155, 21, '2025-07-19 12:38:24', 'retiro', 80996.25, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (156, 21, '2024-03-28 11:12:32', 'retiro', 61889.35, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (157, 21, '2023-11-07 00:23:03', 'deposito', 78545.1, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (158, 21, '2023-12-19 10:26:26', 'retiro', 80311.32, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (159, 21, '2025-08-27 17:22:10', 'retiro', 1468.98, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (160, 22, '2024-09-03 08:25:05', 'pago', 82277.01, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (161, 22, '2024-02-26 20:24:32', 'interes', 297.94, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (162, 22, '2023-09-13 05:56:40', 'interes', 297.94, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (163, 22, '2023-08-14 09:34:29', 'pago', 63393.68, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (164, 22, '2024-06-13 22:19:35', 'interes', 297.94, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (165, 22, '2024-10-26 19:22:02', 'interes', 297.94, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (166, 22, '2023-07-12 02:29:33', 'pago', 20579.94, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (167, 23, '2024-09-24 16:29:05', 'remesa_pago', 105100.84, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (168, 23, '2023-07-12 11:40:27', 'remesa_envio', 22907.18, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (169, 23, '2023-01-23 06:46:11', 'remesa_envio', 42388.97, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (170, 23, '2025-01-02 15:57:44', 'remesa_envio', 34998.29, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (171, 24, '2024-05-20 07:54:27', 'remesa_pago', 63094.43, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (172, 25, '2024-04-19 01:09:19', 'interes', 483.16, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (173, 25, '2025-05-13 05:19:08', 'pago', 40048.89, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (174, 25, '2023-03-15 19:46:37', 'interes', 483.16, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (175, 25, '2023-07-16 09:06:18', 'interes', 483.16, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (176, 25, '2023-05-05 09:03:51', 'interes', 483.16, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (177, 25, '2023-09-11 01:13:12', 'pago', 69179.11, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (178, 25, '2024-06-17 07:35:21', 'interes', 483.16, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (179, 25, '2024-11-28 11:21:48', 'interes', 483.16, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (180, 26, '2025-02-01 20:00:34', 'pago', 38071.58, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (181, 26, '2023-07-23 13:07:21', 'pago', 129562.28, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (182, 26, '2023-04-26 08:35:28', 'interes', 162.08, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (183, 27, '2023-06-21 10:03:08', 'comision', 20.77, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (184, 27, '2023-01-10 01:31:44', 'comision', 80.51, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (185, 27, '2024-12-05 21:42:26', 'deposito', 55772.66, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (186, 27, '2023-09-12 05:44:29', 'retiro', 13801.09, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (187, 27, '2023-12-13 22:45:37', 'deposito', 9060.29, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (188, 28, '2025-03-21 03:54:36', 'deposito', 73227.65, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (189, 28, '2024-07-25 23:28:15', 'retiro', 120848.25, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (190, 28, '2025-01-20 07:01:32', 'deposito', 103418.57, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (191, 28, '2025-01-11 04:54:19', 'retiro', 134809.59, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (192, 28, '2024-12-24 15:55:44', 'comision', 36.52, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (193, 28, '2023-07-14 20:37:58', 'deposito', 81588.72, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (194, 28, '2025-01-19 17:03:13', 'retiro', 130162.51, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (195, 28, '2025-07-25 20:11:22', 'deposito', 10424.6, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (196, 28, '2024-04-05 10:45:54', 'retiro', 81286.73, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (197, 28, '2023-01-01 23:13:47', 'comision', 44.11, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (198, 28, '2025-06-23 00:40:53', 'comision', 87.11, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (199, 28, '2023-09-02 11:40:34', 'comision', 15.7, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (200, 28, '2025-04-18 14:06:29', 'deposito', 78658.06, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (201, 29, '2024-09-19 10:18:30', 'interes', 1302.1, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (202, 29, '2024-10-18 11:43:28', 'pago', 14528.82, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (203, 29, '2023-02-14 04:43:29', 'pago', 131036.57, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (204, 29, '2023-04-20 17:40:18', 'pago', 14903.16, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (205, 29, '2024-10-19 14:08:54', 'interes', 1302.1, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (206, 30, '2024-12-19 21:29:31', 'retiro', 7457.94, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (207, 30, '2024-09-12 02:34:49', 'deposito', 139538.63, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (208, 30, '2024-11-02 17:53:29', 'deposito', 70262.07, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (209, 30, '2024-01-05 20:19:00', 'comision', 94.44, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (210, 30, '2025-04-21 13:26:14', 'comision', 15.25, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (211, 30, '2023-09-30 19:15:39', 'deposito', 110171.62, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (212, 30, '2023-03-21 07:51:38', 'comision', 18.74, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (213, 30, '2024-06-28 14:01:46', 'deposito', 29048.61, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (214, 30, '2024-08-06 22:46:02', 'deposito', 83807.68, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (215, 30, '2024-03-01 03:50:29', 'comision', 61.89, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (216, 30, '2024-12-20 15:32:57', 'deposito', 25104.72, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (217, 30, '2024-07-17 14:37:12', 'comision', 40.38, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (218, 30, '2024-06-30 21:50:32', 'retiro', 140034.64, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (219, 30, '2024-07-17 11:49:13', 'retiro', 61910.26, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (220, 31, '2024-09-15 08:45:51', 'remesa_envio', 56321.95, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (221, 31, '2025-08-06 09:15:03', 'remesa_pago', 144251.6, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (222, 31, '2024-02-11 00:00:25', 'remesa_envio', 147445.18, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (223, 32, '2024-06-14 04:55:05', 'retiro', 1084.67, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (224, 32, '2023-08-08 11:27:55', 'deposito', 115751.31, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (225, 32, '2025-07-30 20:09:29', 'comision', 60.07, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (226, 32, '2023-06-08 03:25:58', 'deposito', 69109.43, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (227, 32, '2023-05-22 09:38:52', 'retiro', 133454.84, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (228, 33, '2023-09-20 10:56:01', 'deposito', 85616.03, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (229, 33, '2025-07-28 07:54:59', 'comision', 16.95, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (230, 33, '2025-03-22 17:34:06', 'deposito', 73292.63, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (231, 33, '2025-04-19 03:28:19', 'comision', 67.8, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (232, 33, '2025-01-18 20:58:54', 'retiro', 11863.76, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (233, 33, '2025-08-01 12:10:29', 'retiro', 131980.9, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (234, 33, '2024-03-02 04:23:19', 'deposito', 112177.03, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (235, 33, '2025-08-08 00:24:58', 'comision', 79.97, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (236, 34, '2023-11-09 19:05:31', 'remesa_envio', 47965.55, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (237, 35, '2023-12-01 18:17:30', 'comision', 29.87, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (238, 35, '2024-11-20 14:18:15', 'retiro', 112950.75, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (239, 35, '2024-05-31 03:16:47', 'deposito', 64847.16, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (240, 35, '2023-06-01 04:48:46', 'retiro', 12473.51, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (241, 35, '2025-02-02 01:47:43', 'comision', 45.93, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (242, 35, '2024-02-13 18:16:14', 'retiro', 116096.39, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (243, 35, '2025-02-19 04:54:37', 'retiro', 83938.5, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (244, 36, '2024-10-29 20:48:05', 'deposito', 84219.02, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (245, 36, '2023-09-10 08:49:20', 'deposito', 40011.94, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (246, 36, '2023-11-28 20:58:19', 'deposito', 16968.23, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (247, 36, '2024-03-09 13:17:56', 'retiro', 28654.41, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (248, 36, '2024-08-31 23:51:45', 'deposito', 115475.23, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (249, 36, '2023-12-25 22:26:09', 'retiro', 93515.01, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (250, 36, '2023-02-15 08:30:03', 'deposito', 102835.35, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (251, 36, '2025-02-14 03:07:27', 'deposito', 110963.29, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (252, 36, '2025-08-29 22:36:36', 'deposito', 130325.98, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (253, 36, '2023-01-15 12:29:53', 'comision', 82.39, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (254, 36, '2024-04-05 17:09:19', 'deposito', 49848.32, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (255, 37, '2023-07-28 19:53:40', 'remesa_pago', 82365.13, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (256, 37, '2025-01-17 05:08:46', 'remesa_envio', 56553.34, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (257, 38, '2023-09-19 06:12:04', 'remesa_envio', 42673.63, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (258, 39, '2023-02-24 16:55:43', 'pago', 10083.01, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (259, 39, '2024-11-09 13:06:54', 'pago', 2959.84, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (260, 39, '2023-08-25 13:51:39', 'pago', 135590.42, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (261, 39, '2025-06-06 21:44:23', 'pago', 28043.97, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (262, 39, '2024-04-13 20:24:50', 'pago', 6058.89, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (263, 39, '2023-11-09 12:08:41', 'interes', 452.82, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (264, 39, '2025-02-01 05:42:58', 'pago', 52082.31, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (265, 40, '2024-10-02 11:00:26', 'remesa_envio', 149399.56, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (266, 40, '2023-10-10 02:15:27', 'remesa_pago', 131813.72, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (267, 40, '2025-08-24 20:12:17', 'remesa_pago', 33914.85, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (268, 41, '2024-11-03 04:59:51', 'deposito', 109510.46, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (269, 41, '2024-11-25 22:17:54', 'comision', 71.79, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (270, 41, '2023-09-04 20:51:30', 'deposito', 64027.1, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (271, 41, '2025-07-20 22:02:26', 'retiro', 67430.46, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (272, 41, '2023-07-31 23:45:20', 'deposito', 87196.5, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (273, 41, '2025-06-02 05:01:42', 'retiro', 103310.96, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (274, 41, '2025-07-20 04:55:27', 'retiro', 149353.3, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (275, 41, '2024-11-02 20:33:55', 'deposito', 47692.68, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (276, 41, '2024-06-29 04:18:37', 'deposito', 47707.88, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (277, 41, '2025-01-14 01:04:24', 'retiro', 132031.77, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (278, 41, '2024-02-26 11:02:40', 'retiro', 111866.9, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (279, 42, '2025-03-08 06:50:32', 'remesa_envio', 19818.73, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (280, 42, '2025-02-19 22:16:53', 'remesa_pago', 90880.12, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (281, 43, '2024-09-02 08:27:12', 'pago', 103137.94, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (282, 43, '2023-03-23 17:21:09', 'pago', 75398.46, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (283, 43, '2024-04-25 23:39:00', 'interes', 1341.74, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (284, 43, '2025-05-22 14:06:25', 'interes', 1341.74, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (285, 43, '2023-05-21 05:57:47', 'pago', 34018.33, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (286, 43, '2025-02-21 00:32:47', 'interes', 1341.74, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (287, 44, '2025-01-30 07:23:05', 'pago', 10013.84, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (288, 44, '2025-06-06 22:27:59', 'interes', 487.64, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (289, 44, '2025-06-06 16:39:31', 'pago', 64190.6, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (290, 44, '2024-09-14 13:50:56', 'interes', 487.64, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (291, 44, '2024-09-18 20:49:24', 'pago', 78145.3, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (292, 44, '2024-04-12 01:32:39', 'pago', 77853.53, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (293, 45, '2024-07-25 14:06:17', 'comision', 78.86, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (294, 45, '2023-07-14 10:36:05', 'retiro', 59766.18, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (295, 45, '2025-03-03 10:24:35', 'retiro', 25056.34, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (296, 45, '2024-09-19 01:59:09', 'comision', 56.53, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (297, 45, '2024-04-19 23:31:25', 'retiro', 13657.08, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (298, 46, '2023-07-04 21:18:55', 'comision', 59.18, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (299, 46, '2024-02-28 11:46:36', 'retiro', 3834.33, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (300, 46, '2024-08-27 07:21:07', 'retiro', 13617.93, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (301, 46, '2024-12-09 23:36:50', 'comision', 81.68, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (302, 46, '2023-04-04 04:09:23', 'comision', 50.45, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (303, 46, '2023-03-29 19:04:17', 'comision', 44.57, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (304, 47, '2025-08-30 05:49:18', 'retiro', 82596.85, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (305, 47, '2025-02-25 06:13:18', 'retiro', 84867.19, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (306, 47, '2023-06-16 05:15:53', 'deposito', 115396.6, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (307, 47, '2024-03-05 11:12:58', 'retiro', 109551.25, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (308, 47, '2023-10-23 22:48:30', 'deposito', 17721.34, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (309, 47, '2023-07-27 00:07:43', 'comision', 78.89, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (310, 47, '2024-04-14 18:07:05', 'retiro', 81570.82, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (311, 47, '2024-09-14 17:57:59', 'deposito', 32609.39, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (312, 47, '2024-04-09 14:55:59', 'retiro', 12002.8, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (313, 47, '2023-01-07 08:54:35', 'comision', 35.03, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (314, 47, '2025-04-19 07:33:35', 'deposito', 27807.51, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (315, 47, '2024-10-30 12:42:26', 'deposito', 21891.62, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (316, 47, '2024-11-14 21:02:51', 'comision', 36.86, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (317, 47, '2023-02-20 03:57:52', 'retiro', 149060.9, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (318, 48, '2024-09-17 21:39:43', 'remesa_envio', 144947.36, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (319, 48, '2024-01-04 01:18:17', 'remesa_envio', 115299.95, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (320, 48, '2024-01-13 13:47:48', 'remesa_envio', 113790.45, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (321, 49, '2023-10-27 17:08:30', 'remesa_envio', 18391.28, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (322, 50, '2024-06-23 15:03:52', 'comision', 28.89, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (323, 50, '2024-09-18 02:07:06', 'deposito', 85747.92, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (324, 50, '2023-03-31 17:36:34', 'comision', 71.98, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (325, 50, '2024-03-13 22:10:02', 'retiro', 39023.04, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (326, 50, '2024-09-30 12:53:00', 'deposito', 92182.07, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (327, 50, '2024-06-16 23:00:18', 'retiro', 73926.42, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (328, 50, '2025-06-23 22:11:16', 'deposito', 106317.2, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (329, 50, '2023-01-02 04:18:13', 'deposito', 69786.36, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (330, 50, '2025-01-25 07:32:55', 'comision', 99.91, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (331, 50, '2023-02-16 12:09:10', 'retiro', 84106.28, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (332, 51, '2024-10-17 07:19:30', 'comision', 35.35, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (333, 51, '2023-11-12 10:55:58', 'comision', 59.5, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (334, 51, '2023-04-27 12:08:04', 'retiro', 59467.79, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (335, 51, '2024-09-22 01:03:36', 'deposito', 29182.94, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (336, 51, '2025-08-02 17:26:37', 'retiro', 119608.43, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (337, 52, '2023-06-09 22:50:08', 'retiro', 133819.54, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (338, 52, '2025-07-06 12:12:03', 'retiro', 117619.96, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (339, 52, '2025-08-08 02:02:22', 'comision', 36.94, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (340, 52, '2024-07-22 19:30:39', 'deposito', 31318.54, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (341, 52, '2025-03-29 12:52:26', 'deposito', 145445.03, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (342, 52, '2025-05-10 01:08:05', 'retiro', 147544.45, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (343, 52, '2025-05-12 06:02:33', 'comision', 64.51, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (344, 52, '2024-09-01 04:15:15', 'retiro', 105819.4, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (345, 52, '2024-12-27 01:09:05', 'retiro', 62139.05, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (346, 52, '2025-06-17 08:39:08', 'retiro', 67840.76, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (347, 52, '2023-08-10 19:07:05', 'retiro', 26334.41, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (348, 52, '2025-03-14 01:21:41', 'deposito', 137011.74, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (349, 53, '2023-01-26 17:34:23', 'comision', 23.87, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (350, 53, '2025-08-03 17:36:09', 'comision', 88.65, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (351, 53, '2025-03-05 11:55:04', 'deposito', 115445.26, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (352, 53, '2025-04-21 18:47:32', 'comision', 99.34, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (353, 53, '2025-01-11 01:19:51', 'retiro', 58199.47, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (354, 53, '2023-04-29 00:08:58', 'retiro', 139857.37, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (355, 53, '2025-06-11 03:10:13', 'retiro', 70084.7, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (356, 53, '2023-04-16 18:57:13', 'comision', 77.1, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (357, 53, '2024-08-14 11:21:53', 'comision', 90.29, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (358, 53, '2023-07-25 07:00:37', 'retiro', 41569.77, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (359, 53, '2025-03-02 16:03:37', 'comision', 20.59, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (360, 53, '2023-06-11 09:57:46', 'deposito', 2386.98, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (361, 53, '2024-07-27 18:42:58', 'deposito', 31065.95, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (362, 54, '2023-10-05 05:09:14', 'interes', 2603.89, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (363, 54, '2023-09-08 06:14:09', 'pago', 46775.5, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (364, 54, '2024-07-07 16:09:09', 'pago', 19598.09, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (365, 54, '2025-07-13 01:50:13', 'pago', 57601.59, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (366, 54, '2024-03-12 14:16:09', 'pago', 105731.17, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (367, 54, '2024-10-06 16:13:56', 'interes', 2603.89, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (368, 54, '2023-12-07 07:12:51', 'pago', 146054.92, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (369, 54, '2024-08-04 04:47:54', 'pago', 121946.37, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (370, 55, '2024-04-11 11:18:03', 'remesa_pago', 70634.83, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (371, 56, '2025-05-31 22:27:43', 'remesa_pago', 136937.96, 'Pago de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (372, 56, '2023-07-07 12:01:36', 'remesa_pago', 68047.13, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (373, 57, '2024-05-01 04:06:36', 'interes', 183.45, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (374, 57, '2024-04-17 06:13:07', 'interes', 183.45, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (375, 57, '2024-09-10 20:55:24', 'pago', 76241.65, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (376, 57, '2025-04-17 03:53:42', 'interes', 183.45, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (377, 58, '2025-03-22 10:59:59', 'remesa_pago', 60182.39, 'Pago de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (378, 59, '2024-09-27 08:52:21', 'remesa_envio', 146086.37, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (379, 59, '2023-03-09 12:24:18', 'remesa_envio', 122105.96, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (380, 60, '2025-03-14 15:51:02', 'remesa_pago', 81724.58, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (381, 60, '2023-06-27 02:50:09', 'remesa_pago', 17237.0, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (382, 60, '2024-04-19 11:50:47', 'remesa_envio', 123321.26, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (383, 60, '2023-11-12 14:46:28', 'remesa_envio', 89779.05, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (384, 61, '2023-12-02 17:59:48', 'comision', 69.41, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (385, 61, '2023-08-11 05:03:28', 'comision', 91.29, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (386, 61, '2025-02-14 05:20:31', 'comision', 23.43, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (387, 61, '2023-10-26 14:11:55', 'comision', 62.01, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (388, 61, '2023-07-30 11:31:37', 'retiro', 85584.43, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (389, 61, '2025-07-29 15:49:40', 'comision', 98.43, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (390, 61, '2023-04-02 21:12:59', 'deposito', 91762.46, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (391, 61, '2024-02-18 04:38:38', 'retiro', 9455.34, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (392, 61, '2023-02-24 00:01:50', 'comision', 60.4, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (393, 61, '2023-04-23 10:16:29', 'deposito', 35362.65, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (394, 61, '2024-02-08 22:45:48', 'retiro', 106794.87, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (395, 62, '2024-03-21 19:50:49', 'deposito', 99406.89, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (396, 62, '2023-05-23 06:51:11', 'comision', 44.61, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (397, 62, '2025-05-10 15:11:27', 'deposito', 43341.78, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (398, 62, '2023-05-18 00:25:20', 'deposito', 97293.55, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (399, 62, '2025-01-08 17:43:12', 'comision', 49.31, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (400, 62, '2023-03-28 04:59:45', 'comision', 82.53, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (401, 62, '2025-07-04 22:00:23', 'retiro', 93524.95, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (402, 62, '2024-06-05 15:26:30', 'comision', 83.81, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (403, 62, '2023-12-30 08:13:08', 'deposito', 63773.3, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (404, 62, '2024-08-14 18:08:14', 'comision', 31.31, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (405, 62, '2023-10-03 14:57:29', 'comision', 61.87, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (406, 63, '2024-08-04 17:35:42', 'interes', 92.11, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (407, 63, '2024-08-17 17:31:55', 'pago', 21398.91, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (408, 63, '2025-05-29 10:10:24', 'interes', 92.11, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (409, 64, '2024-06-19 22:12:43', 'pago', 36860.17, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (410, 64, '2024-12-01 23:04:18', 'interes', 1181.12, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (411, 64, '2023-02-24 12:30:29', 'pago', 70383.43, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (412, 64, '2025-07-16 17:05:03', 'interes', 1181.12, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (413, 65, '2025-03-28 10:43:36', 'retiro', 25209.47, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (414, 65, '2025-02-06 11:04:15', 'comision', 80.65, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (415, 65, '2023-03-04 22:54:43', 'retiro', 86763.35, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (416, 65, '2023-02-22 23:53:45', 'retiro', 121353.48, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (417, 65, '2023-01-28 10:26:33', 'retiro', 12468.27, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (418, 65, '2023-03-20 10:06:58', 'retiro', 19967.56, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (419, 65, '2023-10-09 09:21:19', 'deposito', 111240.23, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (420, 65, '2023-06-28 21:32:44', 'comision', 23.6, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (421, 65, '2024-01-14 06:23:09', 'retiro', 117400.9, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (422, 65, '2024-05-11 06:34:59', 'comision', 87.58, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (423, 66, '2023-05-29 21:40:59', 'pago', 125658.37, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (424, 66, '2025-02-27 13:57:02', 'pago', 99134.03, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (425, 66, '2023-08-04 21:02:07', 'interes', 374.88, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (426, 66, '2024-10-19 09:37:34', 'pago', 7973.23, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (427, 67, '2024-05-02 10:58:20', 'interes', 632.3, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (428, 67, '2023-08-28 13:49:41', 'interes', 632.3, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (429, 67, '2023-09-26 05:17:05', 'interes', 632.3, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (430, 67, '2023-10-23 16:20:27', 'interes', 632.3, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (431, 67, '2024-06-26 01:29:36', 'pago', 137665.05, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (432, 67, '2025-05-14 15:43:15', 'interes', 632.3, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (433, 67, '2023-10-04 09:43:27', 'pago', 38376.05, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (434, 67, '2024-02-05 16:47:18', 'pago', 110173.59, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (435, 67, '2025-02-27 07:05:49', 'interes', 632.3, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (436, 68, '2024-07-14 00:23:06', 'comision', 10.76, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (437, 68, '2023-01-13 14:58:23', 'deposito', 78837.11, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (438, 68, '2023-12-26 07:59:19', 'comision', 35.5, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (439, 68, '2023-02-04 00:51:46', 'comision', 18.27, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (440, 68, '2024-11-03 07:53:39', 'comision', 67.43, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (441, 68, '2023-03-30 22:00:57', 'deposito', 56456.17, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (442, 68, '2025-04-02 06:43:37', 'deposito', 104378.48, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (443, 68, '2023-10-29 17:00:04', 'comision', 94.26, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (444, 68, '2025-08-02 10:03:46', 'retiro', 103864.0, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (445, 68, '2023-09-21 05:53:49', 'deposito', 41665.39, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (446, 69, '2024-02-02 12:06:41', 'remesa_envio', 38809.97, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (447, 69, '2023-07-02 16:02:27', 'remesa_envio', 73809.1, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (448, 69, '2024-09-16 14:17:43', 'remesa_envio', 96857.93, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (449, 69, '2023-05-28 19:41:01', 'remesa_pago', 32836.14, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (450, 70, '2025-01-02 09:25:47', 'deposito', 5325.65, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (451, 70, '2024-08-08 09:07:26', 'retiro', 2912.84, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (452, 70, '2023-06-02 23:46:12', 'comision', 10.08, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (453, 70, '2024-11-11 14:13:01', 'retiro', 22825.96, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (454, 70, '2025-07-15 14:14:52', 'comision', 10.33, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (455, 70, '2024-05-04 15:52:34', 'retiro', 126622.97, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (456, 70, '2024-07-07 08:13:22', 'deposito', 57725.14, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (457, 70, '2023-05-05 20:39:09', 'comision', 94.15, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (458, 70, '2023-12-08 11:01:32', 'retiro', 8373.68, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (459, 70, '2024-01-10 19:27:54', 'retiro', 12160.47, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (460, 70, '2025-02-17 10:33:25', 'comision', 28.28, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (461, 70, '2023-02-10 13:59:13', 'comision', 27.19, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (462, 71, '2024-10-07 13:04:49', 'interes', 93.81, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (463, 71, '2025-06-25 23:02:21', 'interes', 93.81, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (464, 71, '2023-05-24 01:17:59', 'pago', 3902.15, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (465, 71, '2023-09-02 17:48:44', 'interes', 93.81, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (466, 72, '2024-05-26 19:26:24', 'interes', 1599.22, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (467, 72, '2023-02-07 12:21:10', 'pago', 50724.02, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (468, 72, '2024-02-20 04:18:11', 'pago', 121084.85, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (469, 72, '2024-04-14 19:32:08', 'pago', 111183.62, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (470, 72, '2025-08-05 02:37:21', 'pago', 110345.41, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (471, 72, '2024-10-31 00:41:38', 'interes', 1599.22, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (472, 72, '2023-02-16 08:50:08', 'pago', 2253.34, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (473, 73, '2025-04-20 03:32:32', 'remesa_pago', 91722.76, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (474, 73, '2023-03-07 03:52:17', 'remesa_envio', 74621.81, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (475, 73, '2023-08-14 02:17:51', 'remesa_envio', 63989.1, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (476, 74, '2023-05-04 20:58:13', 'pago', 48306.32, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (477, 74, '2025-02-21 01:39:35', 'pago', 50392.01, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (478, 74, '2023-10-08 05:08:32', 'interes', 599.26, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (479, 74, '2024-12-14 13:28:07', 'pago', 65855.32, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (480, 74, '2023-02-11 04:51:21', 'pago', 118678.74, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (481, 74, '2024-01-21 05:44:37', 'pago', 131956.08, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (482, 74, '2023-01-07 00:15:46', 'pago', 138927.93, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (483, 74, '2025-06-27 10:19:49', 'interes', 599.26, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (484, 75, '2023-07-31 05:12:34', 'interes', 1912.83, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (485, 75, '2024-04-06 15:00:05', 'pago', 140719.63, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (486, 75, '2024-12-09 01:22:11', 'pago', 107608.09, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (487, 75, '2025-08-31 03:12:17', 'interes', 1912.83, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (488, 75, '2024-03-04 00:09:59', 'pago', 28866.24, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (489, 76, '2024-09-25 13:10:35', 'remesa_envio', 69685.98, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (490, 77, '2023-02-24 07:03:11', 'remesa_envio', 119512.28, 'Envío de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (491, 77, '2024-05-24 06:25:11', 'remesa_envio', 100554.38, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (492, 77, '2023-02-25 23:28:43', 'remesa_pago', 42831.17, 'Pago de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (493, 78, '2023-12-09 22:27:27', 'interes', 1259.4, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (494, 78, '2023-04-17 01:54:35', 'pago', 23791.04, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (495, 78, '2024-05-11 18:44:49', 'pago', 10721.84, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (496, 78, '2025-01-08 16:11:43', 'interes', 1259.4, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (497, 78, '2023-07-23 11:51:28', 'pago', 116868.39, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (498, 78, '2023-08-22 03:34:13', 'pago', 110688.41, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (499, 78, '2024-01-20 08:02:02', 'pago', 70701.44, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (500, 79, '2025-06-30 15:52:09', 'deposito', 32503.16, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (501, 79, '2024-04-10 06:28:58', 'retiro', 56085.41, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (502, 79, '2025-01-07 07:04:08', 'comision', 42.27, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (503, 79, '2023-07-27 12:13:45', 'deposito', 4910.98, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (504, 79, '2023-03-03 10:12:59', 'deposito', 16755.28, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (505, 80, '2024-03-04 06:13:59', 'retiro', 33056.05, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (506, 80, '2024-09-10 05:42:30', 'comision', 95.75, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (507, 80, '2024-08-14 20:07:30', 'deposito', 13062.5, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (508, 80, '2024-05-15 07:52:49', 'comision', 52.61, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (509, 80, '2023-10-13 00:31:41', 'comision', 48.53, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (510, 80, '2023-09-11 11:54:59', 'retiro', 86962.11, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (511, 80, '2025-08-26 05:25:25', 'comision', 90.84, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (512, 80, '2023-02-15 01:27:30', 'retiro', 110048.1, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (513, 80, '2023-02-04 15:29:57', 'comision', 45.49, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (514, 80, '2024-04-08 18:01:58', 'deposito', 12555.42, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (515, 80, '2024-12-10 14:48:16', 'deposito', 19993.53, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (516, 80, '2023-09-02 23:34:47', 'deposito', 2487.93, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (517, 81, '2024-12-21 16:43:19', 'pago', 146465.47, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (518, 81, '2025-03-01 05:02:49', 'interes', 1280.52, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (519, 81, '2025-03-19 13:29:11', 'interes', 1280.52, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (520, 81, '2025-05-31 22:50:22', 'pago', 57793.4, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (521, 81, '2024-06-27 01:11:27', 'interes', 1280.52, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (522, 82, '2024-12-15 22:18:01', 'remesa_envio', 118175.01, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (523, 82, '2024-09-27 12:13:20', 'remesa_envio', 77259.0, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (524, 82, '2025-06-28 01:52:38', 'remesa_envio', 57504.95, 'Envío de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (525, 83, '2023-02-11 13:18:36', 'retiro', 26372.58, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (526, 83, '2024-12-22 02:26:22', 'comision', 73.84, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (527, 83, '2023-05-22 12:11:39', 'deposito', 80991.11, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (528, 83, '2025-01-25 21:07:17', 'comision', 28.88, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (529, 83, '2023-11-25 12:50:30', 'retiro', 75584.54, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (530, 83, '2023-10-11 01:58:58', 'deposito', 55984.79, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (531, 83, '2024-05-12 18:15:26', 'comision', 84.66, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (532, 83, '2024-12-27 19:21:57', 'comision', 84.28, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (533, 83, '2024-04-07 22:36:29', 'retiro', 120005.59, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (534, 83, '2023-07-12 16:40:14', 'deposito', 12117.54, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (535, 83, '2023-10-23 02:48:05', 'deposito', 24798.46, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (536, 83, '2024-12-14 05:23:12', 'retiro', 22659.66, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (537, 83, '2024-06-17 22:50:18', 'deposito', 44046.1, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (538, 83, '2025-08-12 04:48:25', 'retiro', 52070.37, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (539, 84, '2023-01-22 10:36:49', 'deposito', 9536.13, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (540, 84, '2025-05-04 18:55:07', 'comision', 40.23, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (541, 84, '2023-12-18 23:52:31', 'comision', 80.81, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (542, 84, '2024-08-30 19:18:09', 'comision', 50.07, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (543, 84, '2024-08-03 04:48:15', 'retiro', 25843.4, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (544, 84, '2023-08-21 17:37:50', 'retiro', 145611.53, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (545, 84, '2023-06-01 12:51:24', 'retiro', 68443.39, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (546, 84, '2024-09-25 05:51:15', 'comision', 58.18, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (547, 84, '2023-06-29 05:35:17', 'deposito', 35762.01, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (548, 84, '2023-11-21 20:55:04', 'deposito', 66189.21, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (549, 84, '2023-07-08 07:28:10', 'comision', 73.64, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (550, 84, '2023-12-19 05:23:11', 'retiro', 67319.52, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (551, 84, '2024-06-30 10:58:46', 'deposito', 138073.05, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (552, 84, '2025-08-11 18:10:59', 'deposito', 142173.58, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (553, 84, '2023-06-09 00:09:22', 'comision', 59.15, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (554, 85, '2024-10-24 10:45:39', 'interes', 1204.12, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (555, 85, '2025-08-24 20:53:19', 'pago', 119956.47, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (556, 85, '2023-12-13 04:05:21', 'interes', 1204.12, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (557, 85, '2023-05-23 20:03:35', 'pago', 46281.52, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (558, 85, '2024-09-24 08:01:23', 'interes', 1204.12, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (559, 85, '2023-04-05 11:52:57', 'pago', 91261.87, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (560, 85, '2024-08-20 19:10:00', 'pago', 117214.38, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (561, 85, '2023-07-20 00:49:15', 'pago', 80808.0, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (562, 86, '2024-11-18 03:10:52', 'comision', 45.5, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (563, 86, '2023-11-22 21:57:38', 'comision', 56.04, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (564, 86, '2025-07-19 13:08:45', 'retiro', 22277.1, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (565, 86, '2024-01-14 14:03:28', 'retiro', 1927.4, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (566, 86, '2023-12-26 11:13:01', 'retiro', 131157.83, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (567, 86, '2023-08-09 16:10:24', 'comision', 99.33, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (568, 86, '2023-10-23 05:57:48', 'comision', 97.33, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (569, 86, '2025-01-16 15:04:49', 'deposito', 125343.18, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (570, 86, '2023-03-30 05:13:47', 'deposito', 45554.35, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (571, 86, '2023-12-10 02:24:25', 'comision', 78.05, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (572, 86, '2023-01-07 14:54:28', 'comision', 92.3, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (573, 86, '2023-06-29 20:14:11', 'retiro', 106566.03, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (574, 86, '2023-07-24 06:46:20', 'retiro', 43490.53, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (575, 86, '2023-02-13 10:59:42', 'comision', 37.35, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (576, 86, '2025-01-27 16:52:25', 'deposito', 4123.32, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (577, 87, '2023-09-26 10:55:43', 'interes', 754.69, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (578, 87, '2024-10-31 10:28:27', 'interes', 754.69, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (579, 87, '2024-05-18 23:28:33', 'pago', 4363.54, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (580, 87, '2024-05-19 02:25:45', 'interes', 754.69, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (581, 87, '2024-05-07 20:35:30', 'interes', 754.69, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (582, 88, '2024-12-11 04:21:14', 'interes', 2533.68, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (583, 88, '2025-01-20 20:56:40', 'pago', 126807.48, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (584, 88, '2024-08-18 02:07:49', 'pago', 48020.2, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (585, 88, '2024-01-01 05:56:45', 'pago', 40973.29, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (586, 88, '2024-10-13 12:57:39', 'pago', 43549.44, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (587, 88, '2024-10-16 02:47:49', 'pago', 114989.72, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (588, 88, '2025-02-22 03:26:27', 'pago', 81602.48, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (589, 88, '2025-04-26 10:57:42', 'interes', 2533.68, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (590, 88, '2023-04-09 19:27:27', 'interes', 2533.68, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (591, 88, '2023-01-14 04:59:10', 'interes', 2533.68, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (592, 89, '2024-02-26 12:23:25', 'deposito', 15452.44, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (593, 89, '2024-05-30 08:03:01', 'deposito', 119286.5, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (594, 89, '2024-09-20 19:08:18', 'comision', 74.13, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (595, 89, '2024-03-03 16:45:57', 'deposito', 17573.19, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (596, 89, '2025-08-03 00:37:57', 'retiro', 52296.67, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (597, 89, '2023-05-23 16:05:25', 'comision', 57.08, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (598, 89, '2023-06-26 11:05:35', 'deposito', 111694.59, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (599, 89, '2023-08-16 04:41:10', 'comision', 22.81, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (600, 89, '2023-11-11 04:33:49', 'deposito', 19619.72, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (601, 89, '2024-03-11 04:04:03', 'deposito', 2919.08, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (602, 89, '2025-02-14 15:42:04', 'deposito', 29533.01, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (603, 89, '2025-03-23 18:41:42', 'comision', 15.33, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (604, 90, '2023-02-14 02:24:43', 'remesa_pago', 100171.2, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (605, 90, '2025-03-12 04:30:25', 'remesa_envio', 88181.7, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (606, 90, '2023-07-09 12:47:56', 'remesa_envio', 13707.82, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (607, 91, '2023-12-23 12:49:23', 'deposito', 128285.2, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (608, 91, '2023-09-05 18:22:59', 'comision', 16.15, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (609, 91, '2025-02-20 00:30:32', 'comision', 29.53, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (610, 91, '2023-10-16 06:15:14', 'comision', 10.39, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (611, 91, '2025-08-04 07:47:31', 'comision', 86.62, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (612, 91, '2024-01-11 21:27:31', 'deposito', 66005.91, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (613, 91, '2023-07-05 12:55:07', 'retiro', 63671.37, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (614, 91, '2023-08-22 14:50:22', 'deposito', 114235.28, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (615, 91, '2023-05-07 16:57:46', 'deposito', 78007.16, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (616, 91, '2025-02-19 13:09:09', 'comision', 35.94, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (617, 91, '2023-03-26 11:56:46', 'retiro', 17446.82, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (618, 91, '2024-04-12 21:51:34', 'comision', 38.08, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (619, 91, '2023-08-20 20:10:02', 'retiro', 43659.34, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (620, 91, '2023-07-13 02:32:03', 'retiro', 140868.39, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (621, 92, '2023-01-14 17:54:01', 'comision', 19.47, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (622, 92, '2024-06-19 23:58:37', 'comision', 17.65, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (623, 92, '2024-02-09 14:35:10', 'comision', 63.15, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (624, 92, '2025-01-29 06:08:34', 'deposito', 54620.13, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (625, 92, '2023-12-13 07:17:28', 'comision', 85.96, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (626, 92, '2023-05-06 08:28:42', 'retiro', 108807.55, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (627, 92, '2025-02-22 21:11:13', 'comision', 34.57, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (628, 93, '2024-05-02 21:57:38', 'retiro', 148129.73, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (629, 93, '2023-10-13 05:21:56', 'retiro', 16294.7, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (630, 93, '2024-05-16 18:06:18', 'deposito', 94292.82, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (631, 93, '2023-01-31 03:37:35', 'comision', 14.76, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (632, 93, '2024-05-25 00:58:26', 'deposito', 57456.68, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (633, 93, '2023-06-06 11:01:22', 'comision', 66.09, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (634, 93, '2024-11-07 18:55:50', 'retiro', 118930.44, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (635, 93, '2023-10-28 18:07:40', 'retiro', 75768.73, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (636, 93, '2023-12-18 19:40:48', 'comision', 11.59, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (637, 93, '2024-03-16 04:20:15', 'retiro', 67572.32, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (638, 94, '2024-04-15 01:18:36', 'pago', 26612.69, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (639, 94, '2025-06-24 05:58:34', 'interes', 139.5, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (640, 94, '2023-05-18 11:22:34', 'interes', 139.5, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (641, 94, '2025-02-21 03:58:56', 'interes', 139.5, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (642, 94, '2024-12-02 19:38:19', 'interes', 139.5, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (643, 94, '2024-07-29 05:41:27', 'pago', 58768.58, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (644, 94, '2024-08-28 13:45:18', 'interes', 139.5, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (645, 94, '2023-11-25 02:14:10', 'pago', 88610.47, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (646, 94, '2025-05-07 13:20:26', 'interes', 139.5, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (647, 94, '2023-01-28 22:45:40', 'interes', 139.5, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (648, 95, '2024-03-14 12:33:58', 'retiro', 61848.25, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (649, 95, '2024-11-08 08:53:31', 'deposito', 35269.85, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (650, 95, '2024-08-29 03:05:33', 'comision', 15.9, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (651, 95, '2023-04-28 12:17:29', 'deposito', 3054.83, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (652, 95, '2023-02-08 16:46:52', 'comision', 87.7, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (653, 95, '2024-06-11 15:20:03', 'retiro', 3158.3, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (654, 96, '2023-01-23 11:31:26', 'remesa_pago', 85596.0, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (655, 96, '2024-08-09 03:33:29', 'remesa_pago', 15098.5, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (656, 96, '2023-12-11 18:05:07', 'remesa_pago', 25077.42, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (657, 96, '2024-01-08 15:52:26', 'remesa_envio', 74593.06, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (658, 96, '2025-05-10 19:30:32', 'remesa_envio', 43174.6, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (659, 97, '2024-08-10 14:38:14', 'deposito', 93723.39, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (660, 97, '2025-01-04 21:03:04', 'deposito', 88820.51, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (661, 97, '2023-03-10 20:37:22', 'comision', 52.77, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (662, 97, '2023-12-22 02:47:28', 'comision', 84.14, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (663, 97, '2025-04-03 10:55:09', 'retiro', 99552.16, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (664, 97, '2023-07-24 15:05:04', 'retiro', 37764.59, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (665, 97, '2024-04-09 19:56:10', 'deposito', 132146.4, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (666, 97, '2025-06-02 06:47:30', 'comision', 54.93, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (667, 97, '2023-10-02 23:13:34', 'comision', 82.8, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (668, 98, '2024-06-18 07:18:19', 'interes', 608.22, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (669, 98, '2023-06-01 08:45:06', 'pago', 111990.38, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (670, 98, '2025-05-14 15:51:07', 'interes', 608.22, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (671, 99, '2024-10-11 07:24:40', 'remesa_pago', 40113.52, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (672, 100, '2023-09-20 21:53:24', 'pago', 60939.3, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (673, 100, '2023-06-03 06:59:14', 'pago', 36913.43, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (674, 100, '2024-04-20 17:40:20', 'interes', 1246.56, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (675, 100, '2024-10-24 01:20:50', 'pago', 23987.84, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (676, 100, '2023-01-30 09:24:28', 'interes', 1246.56, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (677, 101, '2024-10-21 01:32:15', 'remesa_pago', 117356.84, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (678, 101, '2025-05-30 03:03:20', 'remesa_pago', 90279.8, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (679, 102, '2025-07-07 13:13:56', 'remesa_envio', 59594.57, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (680, 102, '2023-08-30 04:04:31', 'remesa_envio', 78341.44, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (681, 102, '2025-08-30 19:07:26', 'remesa_pago', 74518.02, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (682, 102, '2023-09-01 21:50:19', 'remesa_envio', 116001.31, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (683, 103, '2025-05-02 21:16:28', 'comision', 45.1, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (684, 103, '2025-08-15 15:23:46', 'deposito', 21727.26, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (685, 103, '2023-08-08 09:59:45', 'retiro', 61315.5, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (686, 103, '2023-02-27 17:51:12', 'comision', 43.72, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (687, 103, '2023-11-21 19:52:11', 'retiro', 71280.63, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (688, 103, '2023-10-12 05:16:33', 'retiro', 71335.74, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (689, 103, '2025-04-21 11:13:12', 'deposito', 96845.1, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (690, 103, '2023-02-05 01:59:26', 'comision', 92.57, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (691, 103, '2023-09-17 20:07:27', 'retiro', 46459.35, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (692, 103, '2025-07-13 04:26:37', 'comision', 88.03, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (693, 104, '2023-01-09 14:18:28', 'retiro', 45203.13, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (694, 104, '2023-11-01 07:39:35', 'deposito', 137392.03, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (695, 104, '2025-06-19 23:27:46', 'retiro', 118418.68, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (696, 104, '2025-06-06 02:54:58', 'retiro', 70716.58, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (697, 104, '2025-08-06 12:06:50', 'comision', 48.01, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (698, 104, '2025-04-24 05:50:16', 'comision', 33.49, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (699, 104, '2023-12-27 15:19:24', 'comision', 75.63, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (700, 104, '2025-01-25 11:53:50', 'retiro', 104311.99, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (701, 104, '2024-10-18 23:21:34', 'deposito', 94560.44, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (702, 104, '2023-01-04 14:35:15', 'deposito', 94281.61, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (703, 104, '2024-08-12 02:59:38', 'deposito', 23757.58, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (704, 105, '2025-05-17 21:37:38', 'remesa_pago', 118917.08, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (705, 105, '2024-04-07 17:25:00', 'remesa_envio', 39175.91, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (706, 106, '2025-03-29 10:15:35', 'pago', 12751.4, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (707, 106, '2023-07-06 14:19:36', 'interes', 386.05, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (708, 106, '2023-08-18 00:45:17', 'pago', 138474.54, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (709, 106, '2024-10-03 08:19:37', 'pago', 146121.72, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (710, 106, '2023-09-26 06:08:39', 'pago', 60215.13, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (711, 106, '2024-09-06 09:28:19', 'pago', 13450.28, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (712, 106, '2023-06-24 20:39:09', 'pago', 2215.82, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (713, 106, '2024-03-21 16:31:08', 'interes', 386.05, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (714, 107, '2024-12-31 07:23:46', 'pago', 141913.24, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (715, 107, '2023-10-22 17:59:31', 'interes', 618.41, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (716, 107, '2024-03-17 07:31:20', 'pago', 149281.6, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (717, 107, '2025-01-14 06:53:40', 'interes', 618.41, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (718, 107, '2024-02-23 05:18:49', 'pago', 43599.92, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (719, 107, '2023-08-30 22:29:20', 'interes', 618.41, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (720, 108, '2024-08-19 23:33:54', 'interes', 1995.25, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (721, 108, '2023-01-11 17:04:17', 'pago', 130729.38, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (722, 108, '2024-12-04 07:43:35', 'interes', 1995.25, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (723, 108, '2025-01-23 21:44:35', 'interes', 1995.25, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (724, 108, '2023-04-08 20:16:47', 'pago', 7911.68, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (725, 108, '2024-04-27 12:53:59', 'pago', 903.61, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (726, 108, '2024-09-26 13:52:10', 'interes', 1995.25, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (727, 108, '2024-11-18 13:30:14', 'pago', 145211.87, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (728, 109, '2024-08-17 06:31:50', 'remesa_pago', 25562.99, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (729, 110, '2025-06-17 17:02:32', 'pago', 13538.23, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (730, 110, '2024-03-19 05:09:45', 'interes', 1327.15, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (731, 110, '2023-11-17 01:36:28', 'pago', 74931.67, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (732, 110, '2025-02-04 13:07:43', 'interes', 1327.15, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (733, 110, '2025-07-13 09:35:00', 'interes', 1327.15, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (734, 110, '2023-11-17 15:51:57', 'pago', 47399.88, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (735, 110, '2025-02-21 05:30:26', 'interes', 1327.15, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (736, 110, '2023-07-13 05:24:40', 'pago', 34556.1, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (737, 111, '2023-09-24 05:57:17', 'interes', 244.4, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (738, 111, '2023-04-29 18:01:08', 'pago', 66283.8, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (739, 111, '2024-05-11 16:39:59', 'interes', 244.4, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (740, 111, '2025-05-16 05:23:25', 'pago', 52505.68, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (741, 111, '2025-06-08 10:20:39', 'pago', 125259.55, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (742, 111, '2025-04-22 09:55:55', 'pago', 87573.75, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (743, 111, '2024-06-22 20:46:54', 'pago', 62521.21, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (744, 111, '2023-09-10 18:08:08', 'pago', 133116.42, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (745, 111, '2023-10-19 04:26:29', 'interes', 244.4, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (746, 111, '2024-08-27 03:51:42', 'interes', 244.4, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (747, 112, '2023-03-25 16:45:23', 'remesa_pago', 68162.92, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (748, 113, '2024-11-04 00:12:40', 'remesa_pago', 145468.6, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (749, 113, '2025-08-31 16:29:48', 'remesa_pago', 142118.02, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (750, 113, '2023-05-13 07:41:44', 'remesa_envio', 120253.54, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (751, 113, '2023-11-27 02:01:19', 'remesa_envio', 82118.72, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (752, 113, '2024-01-26 03:22:10', 'remesa_pago', 38349.07, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (753, 114, '2023-04-02 00:44:48', 'deposito', 24524.81, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (754, 114, '2023-10-19 23:33:45', 'comision', 23.87, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (755, 114, '2024-05-17 15:44:30', 'comision', 82.57, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (756, 114, '2025-07-14 21:58:23', 'deposito', 53920.73, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (757, 114, '2025-05-02 13:22:43', 'comision', 27.99, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (758, 114, '2025-06-25 14:07:47', 'retiro', 40345.06, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (759, 114, '2024-03-09 03:17:05', 'retiro', 121668.05, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (760, 114, '2023-07-10 15:48:19', 'comision', 48.34, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (761, 114, '2024-06-09 12:26:33', 'retiro', 101498.36, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (762, 114, '2025-08-11 18:02:02', 'comision', 66.66, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (763, 114, '2023-03-27 10:35:03', 'retiro', 65659.59, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (764, 115, '2023-06-02 04:39:09', 'interes', 828.09, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (765, 115, '2024-06-19 15:34:23', 'interes', 828.09, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (766, 115, '2023-02-18 20:03:39', 'pago', 137603.57, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (767, 115, '2023-04-21 18:35:32', 'interes', 828.09, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (768, 115, '2023-04-07 16:55:03', 'interes', 828.09, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (769, 115, '2023-09-18 21:19:11', 'pago', 115320.15, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (770, 115, '2023-04-27 16:51:10', 'pago', 117947.95, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (771, 116, '2023-03-27 15:09:18', 'interes', 1784.26, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (772, 116, '2024-08-24 16:33:57', 'interes', 1784.26, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (773, 116, '2025-04-07 09:39:03', 'interes', 1784.26, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (774, 117, '2023-07-09 02:50:52', 'comision', 98.4, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (775, 117, '2025-06-11 03:52:16', 'retiro', 80202.96, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (776, 117, '2024-02-09 04:14:53', 'deposito', 25843.13, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (777, 117, '2024-04-16 14:44:56', 'comision', 96.92, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (778, 117, '2025-01-13 17:43:15', 'retiro', 92813.06, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (779, 117, '2024-01-05 14:22:53', 'retiro', 13236.51, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (780, 117, '2023-01-15 06:56:48', 'deposito', 122413.64, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (781, 117, '2025-05-29 00:58:34', 'deposito', 72219.47, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (782, 118, '2023-09-05 15:51:59', 'comision', 87.24, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (783, 118, '2023-07-15 03:08:04', 'retiro', 115481.2, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (784, 118, '2024-04-30 15:21:36', 'deposito', 17557.18, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (785, 118, '2025-01-26 16:12:41', 'retiro', 70776.23, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (786, 118, '2024-08-22 08:50:01', 'deposito', 44295.23, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (787, 118, '2023-02-22 12:09:18', 'deposito', 15489.26, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (788, 118, '2024-03-01 18:02:52', 'comision', 62.08, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (789, 118, '2023-10-25 01:20:51', 'retiro', 60012.09, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (790, 118, '2024-08-28 22:15:49', 'comision', 91.46, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (791, 118, '2023-08-26 02:12:36', 'comision', 11.71, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (792, 118, '2023-11-20 20:08:36', 'deposito', 40250.55, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (793, 118, '2025-06-29 17:14:01', 'deposito', 74268.84, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (794, 118, '2024-04-04 15:52:57', 'deposito', 24283.88, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (795, 118, '2024-04-25 12:31:08', 'retiro', 34892.26, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (796, 118, '2024-08-24 12:20:53', 'comision', 86.81, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (797, 119, '2025-06-23 10:40:55', 'remesa_pago', 143974.52, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (798, 119, '2025-03-26 17:11:48', 'remesa_envio', 93314.17, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (799, 120, '2024-11-14 17:34:53', 'remesa_envio', 26076.34, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (800, 121, '2024-05-18 03:40:25', 'retiro', 141463.9, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (801, 121, '2023-11-07 08:32:45', 'deposito', 83568.89, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (802, 121, '2024-01-03 09:29:44', 'retiro', 101571.49, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (803, 121, '2025-04-27 18:19:51', 'deposito', 121041.65, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (804, 121, '2024-03-16 04:08:58', 'comision', 30.4, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (805, 121, '2023-08-18 17:42:28', 'retiro', 149050.06, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (806, 121, '2025-02-26 01:41:57', 'comision', 34.07, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (807, 121, '2025-05-23 18:45:52', 'comision', 70.25, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (808, 121, '2025-08-06 15:56:26', 'retiro', 144400.8, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (809, 121, '2023-04-19 22:13:48', 'comision', 80.39, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (810, 121, '2025-04-23 20:28:44', 'deposito', 76145.13, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (811, 121, '2024-10-07 04:17:54', 'deposito', 136656.77, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (812, 121, '2025-01-15 10:38:09', 'comision', 49.74, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (813, 121, '2024-05-25 03:36:54', 'deposito', 97099.24, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (814, 122, '2023-05-06 07:21:02', 'retiro', 145448.54, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (815, 122, '2023-09-09 17:14:44', 'retiro', 43085.07, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (816, 122, '2023-03-29 09:41:07', 'retiro', 107308.44, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (817, 122, '2024-01-05 22:55:02', 'comision', 32.09, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (818, 122, '2024-03-07 08:18:28', 'deposito', 120285.12, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (819, 122, '2025-07-29 14:54:08', 'retiro', 142780.9, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (820, 122, '2025-03-24 13:10:18', 'deposito', 66442.55, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (821, 123, '2023-03-28 12:19:02', 'interes', 2050.78, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (822, 123, '2025-03-01 05:58:58', 'interes', 2050.78, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (823, 123, '2024-02-07 01:21:01', 'pago', 135386.42, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (824, 123, '2024-10-08 18:55:28', 'interes', 2050.78, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (825, 124, '2025-06-26 20:09:22', 'retiro', 108260.5, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (826, 124, '2025-07-20 12:31:49', 'deposito', 124067.83, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (827, 124, '2024-09-17 05:20:49', 'comision', 46.35, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (828, 124, '2025-06-27 19:49:18', 'comision', 80.95, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (829, 124, '2024-12-15 12:34:12', 'comision', 46.41, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (830, 124, '2025-06-21 10:58:42', 'deposito', 5641.83, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (831, 124, '2024-02-04 04:35:15', 'comision', 99.27, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (832, 124, '2023-08-07 03:22:46', 'comision', 59.66, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (833, 124, '2023-12-15 23:08:40', 'deposito', 3610.92, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (834, 124, '2024-08-29 09:25:07', 'deposito', 124851.13, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (835, 124, '2025-01-13 15:23:30', 'comision', 19.94, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (836, 125, '2023-09-23 22:49:40', 'remesa_pago', 18659.57, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (837, 125, '2024-04-04 10:50:54', 'remesa_envio', 68026.76, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (838, 125, '2025-04-04 21:10:30', 'remesa_envio', 52615.54, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (839, 126, '2025-01-01 13:45:01', 'pago', 15873.52, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (840, 126, '2024-08-19 07:00:38', 'interes', 1300.54, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (841, 126, '2023-04-11 05:20:09', 'interes', 1300.54, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (842, 126, '2023-03-25 03:21:31', 'pago', 63790.52, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (843, 126, '2024-05-02 07:49:12', 'interes', 1300.54, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (844, 127, '2024-11-24 19:09:37', 'remesa_pago', 88277.09, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (845, 127, '2025-03-08 14:22:24', 'remesa_pago', 87687.14, 'Pago de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (846, 127, '2024-03-26 17:49:25', 'remesa_pago', 123589.39, 'Pago de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (847, 128, '2023-05-11 17:38:59', 'comision', 51.19, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (848, 128, '2025-06-02 19:15:55', 'deposito', 104201.16, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (849, 128, '2024-04-29 01:11:13', 'comision', 24.12, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (850, 128, '2024-01-14 04:19:26', 'comision', 86.71, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (851, 128, '2023-05-04 13:27:22', 'comision', 36.06, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (852, 128, '2023-06-06 04:17:12', 'retiro', 45808.2, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (853, 128, '2023-11-07 10:42:12', 'retiro', 4293.87, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (854, 128, '2023-05-26 21:28:03', 'retiro', 7392.79, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (855, 128, '2025-06-29 10:19:16', 'deposito', 27543.26, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (856, 128, '2023-01-03 04:27:13', 'comision', 41.38, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (857, 128, '2024-03-03 17:31:08', 'comision', 37.87, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (858, 128, '2025-07-10 12:17:59', 'retiro', 71336.61, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (859, 128, '2023-05-16 05:02:36', 'comision', 67.28, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (860, 129, '2023-06-02 11:50:26', 'pago', 119991.76, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (861, 129, '2024-02-24 14:05:55', 'pago', 135046.64, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (862, 129, '2024-07-07 01:40:05', 'interes', 1710.96, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (863, 129, '2024-10-23 03:13:23', 'pago', 106110.57, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (864, 129, '2024-10-07 11:14:41', 'pago', 96622.74, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (865, 129, '2023-07-17 22:31:34', 'pago', 143598.19, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (866, 129, '2023-07-13 17:19:28', 'pago', 18130.45, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (867, 129, '2023-07-04 00:41:26', 'interes', 1710.96, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (868, 129, '2023-09-09 21:06:03', 'interes', 1710.96, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (869, 129, '2025-04-06 19:25:32', 'interes', 1710.96, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (870, 130, '2024-05-18 00:50:49', 'interes', 1300.86, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (871, 130, '2023-07-04 15:06:26', 'pago', 128961.3, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (872, 130, '2024-01-27 09:21:48', 'pago', 17285.23, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (873, 131, '2023-06-22 10:23:21', 'deposito', 27482.07, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (874, 131, '2023-06-07 11:10:12', 'retiro', 101823.42, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (875, 131, '2024-09-21 11:50:36', 'deposito', 4172.96, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (876, 131, '2023-11-02 14:11:50', 'deposito', 48074.22, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (877, 131, '2025-07-03 11:48:15', 'retiro', 56389.42, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (878, 131, '2023-02-23 07:22:29', 'deposito', 112844.85, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (879, 131, '2023-08-31 17:56:55', 'comision', 77.72, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (880, 131, '2025-08-30 04:11:23', 'retiro', 9188.73, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (881, 131, '2024-07-20 14:49:16', 'deposito', 72677.31, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (882, 131, '2024-10-10 08:30:36', 'deposito', 40447.04, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (883, 131, '2024-11-22 03:41:45', 'deposito', 114470.45, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (884, 131, '2023-11-08 20:41:21', 'retiro', 66952.74, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (885, 131, '2023-07-28 05:11:00', 'retiro', 81111.92, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (886, 132, '2024-07-04 15:25:42', 'interes', 542.5, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (887, 132, '2023-01-02 16:55:02', 'interes', 542.5, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (888, 132, '2023-01-01 02:11:27', 'interes', 542.5, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (889, 132, '2024-09-04 09:08:04', 'interes', 542.5, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (890, 132, '2025-05-12 23:01:04', 'pago', 87815.36, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (891, 132, '2023-10-16 01:39:21', 'pago', 110903.52, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (892, 133, '2023-11-04 03:15:59', 'retiro', 104794.55, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (893, 133, '2025-01-12 20:15:38', 'retiro', 131754.07, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (894, 133, '2024-09-17 18:22:47', 'retiro', 132601.35, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (895, 133, '2024-10-12 09:30:57', 'comision', 50.74, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (896, 133, '2024-11-09 11:42:37', 'retiro', 31672.52, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (897, 133, '2023-12-03 00:34:40', 'comision', 22.04, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (898, 134, '2024-05-02 00:09:20', 'deposito', 100938.69, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (899, 134, '2024-07-23 17:48:11', 'retiro', 80765.9, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (900, 134, '2024-07-05 01:07:36', 'comision', 50.07, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (901, 134, '2023-12-28 13:42:12', 'comision', 42.22, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (902, 134, '2025-05-09 00:18:25', 'deposito', 69457.61, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (903, 134, '2024-03-31 00:20:27', 'deposito', 111497.35, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (904, 134, '2024-11-27 13:01:40', 'deposito', 13585.98, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (905, 134, '2024-10-02 11:02:18', 'comision', 29.9, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (906, 134, '2024-01-07 01:20:22', 'retiro', 73976.4, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (907, 134, '2023-08-03 00:15:35', 'deposito', 147641.1, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (908, 134, '2023-04-24 10:05:52', 'comision', 55.03, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (909, 134, '2024-07-19 07:03:17', 'comision', 76.49, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (910, 134, '2024-08-01 06:23:26', 'deposito', 88265.87, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (911, 134, '2023-05-11 09:27:09', 'comision', 86.99, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (912, 135, '2023-07-16 00:50:30', 'remesa_pago', 102133.99, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (913, 135, '2023-01-03 15:33:02', 'remesa_envio', 128093.59, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (914, 135, '2024-03-18 14:48:50', 'remesa_pago', 18345.48, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (915, 136, '2024-05-22 13:09:38', 'pago', 132581.99, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (916, 136, '2023-02-18 10:07:09', 'interes', 183.92, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (917, 136, '2024-04-04 11:30:50', 'pago', 58839.65, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (918, 136, '2023-03-25 20:49:09', 'pago', 148540.67, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (919, 136, '2024-12-07 15:25:50', 'pago', 137557.58, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (920, 136, '2023-06-18 11:59:12', 'interes', 183.92, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (921, 136, '2024-10-03 22:45:58', 'pago', 4278.13, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (922, 136, '2025-04-07 00:52:28', 'interes', 183.92, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (923, 136, '2023-09-11 03:55:34', 'interes', 183.92, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (924, 136, '2023-12-15 01:58:54', 'interes', 183.92, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (925, 137, '2025-08-24 02:39:16', 'interes', 804.23, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (926, 137, '2024-10-02 16:15:17', 'pago', 12921.65, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (927, 137, '2025-07-27 01:12:50', 'interes', 804.23, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (928, 137, '2025-06-30 02:22:03', 'pago', 9394.13, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (929, 137, '2023-02-26 10:58:34', 'interes', 804.23, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (930, 137, '2023-04-15 02:01:52', 'pago', 44308.02, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (931, 138, '2023-04-09 22:28:31', 'retiro', 35043.49, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (932, 138, '2025-03-17 22:43:09', 'deposito', 68066.35, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (933, 138, '2025-03-25 15:35:12', 'comision', 65.73, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (934, 138, '2024-10-28 00:56:44', 'retiro', 77630.21, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (935, 138, '2023-07-17 03:55:56', 'deposito', 1942.06, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (936, 138, '2024-08-30 07:02:57', 'comision', 21.34, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (937, 138, '2023-09-20 12:56:21', 'retiro', 72261.76, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (938, 138, '2024-03-31 06:46:09', 'deposito', 20737.14, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (939, 138, '2023-03-03 04:38:55', 'retiro', 87719.89, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (940, 138, '2024-10-29 13:01:30', 'retiro', 87591.52, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (941, 138, '2025-03-05 05:18:07', 'deposito', 70481.61, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (942, 139, '2023-10-26 13:25:43', 'remesa_envio', 77700.32, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (943, 139, '2023-02-28 08:38:34', 'remesa_envio', 63366.96, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (944, 139, '2023-07-25 23:19:18', 'remesa_envio', 117811.04, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (945, 140, '2024-11-14 17:19:14', 'comision', 72.27, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (946, 140, '2024-09-06 12:03:23', 'comision', 60.95, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (947, 140, '2024-09-22 10:54:33', 'retiro', 49360.0, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (948, 140, '2024-04-10 01:32:10', 'retiro', 32988.94, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (949, 140, '2024-10-16 08:07:12', 'comision', 30.72, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (950, 140, '2023-08-07 08:42:08', 'retiro', 110214.47, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (951, 140, '2025-04-06 13:41:11', 'deposito', 60106.85, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (952, 140, '2024-01-07 00:21:36', 'deposito', 53747.21, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (953, 141, '2023-05-26 10:34:46', 'remesa_pago', 29241.08, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (954, 142, '2023-02-14 01:04:50', 'remesa_envio', 29753.97, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (955, 142, '2023-08-13 09:32:20', 'remesa_envio', 51038.64, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (956, 142, '2023-09-09 06:30:01', 'remesa_envio', 3321.66, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (957, 143, '2023-01-22 04:59:48', 'retiro', 98264.89, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (958, 143, '2023-12-13 07:39:16', 'retiro', 68484.93, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (959, 143, '2025-04-08 13:33:24', 'comision', 25.42, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (960, 143, '2025-03-29 22:41:24', 'retiro', 131770.34, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (961, 143, '2023-05-02 05:15:31', 'deposito', 119255.23, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (962, 143, '2024-06-29 13:46:10', 'comision', 43.68, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (963, 144, '2024-10-13 08:54:13', 'remesa_envio', 114486.05, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (964, 144, '2023-07-13 19:29:44', 'remesa_pago', 118459.21, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (965, 144, '2023-09-11 01:56:20', 'remesa_pago', 130940.44, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (966, 144, '2024-08-21 17:48:12', 'remesa_envio', 109122.05, 'Envío de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (967, 145, '2023-06-21 18:31:05', 'interes', 483.12, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (968, 145, '2024-01-19 18:09:10', 'interes', 483.12, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (969, 145, '2023-11-26 13:36:45', 'interes', 483.12, 'Interés mensual', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (970, 145, '2024-04-30 09:46:11', 'interes', 483.12, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (971, 146, '2023-08-01 07:59:33', 'remesa_envio', 67866.8, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (972, 147, '2023-08-12 11:08:27', 'remesa_pago', 133317.47, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (973, 147, '2023-06-10 13:37:14', 'remesa_pago', 82627.74, 'Pago de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (974, 147, '2025-02-08 03:03:33', 'remesa_pago', 66731.35, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (975, 147, '2023-08-24 21:15:41', 'remesa_envio', 69841.44, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (976, 148, '2024-03-12 16:25:33', 'interes', 1888.99, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (977, 148, '2024-02-23 13:22:50', 'interes', 1888.99, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (978, 148, '2023-10-07 13:55:18', 'pago', 27016.9, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (979, 148, '2023-09-29 23:29:47', 'pago', 53928.03, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (980, 148, '2023-10-29 18:16:07', 'pago', 117902.41, 'Pago de cuota del préstamo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (981, 148, '2023-04-11 04:19:03', 'pago', 54099.51, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (982, 148, '2023-07-25 12:09:06', 'pago', 101298.59, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (983, 148, '2023-11-06 09:59:34', 'pago', 105875.83, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (984, 149, '2025-07-23 09:30:27', 'deposito', 115534.41, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (985, 149, '2025-04-22 12:37:13', 'retiro', 141877.67, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (986, 149, '2025-02-14 23:51:32', 'deposito', 70853.4, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (987, 149, '2025-02-18 05:26:06', 'retiro', 34214.02, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (988, 149, '2024-04-30 08:30:34', 'comision', 62.83, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (989, 149, '2025-02-14 17:03:58', 'comision', 83.3, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (990, 149, '2025-03-21 03:07:35', 'retiro', 126885.67, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (991, 149, '2025-02-27 15:12:27', 'deposito', 65858.25, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (992, 149, '2023-01-31 13:38:32', 'deposito', 86668.52, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (993, 149, '2023-11-09 00:21:08', 'retiro', 121579.17, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (994, 149, '2023-12-14 08:12:35', 'retiro', 63915.33, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (995, 149, '2025-02-20 19:34:24', 'retiro', 48979.32, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (996, 149, '2024-08-04 01:10:21', 'deposito', 23138.32, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (997, 150, '2024-01-26 07:26:05', 'interes', 1248.91, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (998, 150, '2024-07-01 14:04:10', 'pago', 71269.17, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (999, 150, '2024-08-06 16:26:23', 'interes', 1248.91, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1000, 150, '2023-06-25 03:47:52', 'pago', 4905.67, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1001, 150, '2024-05-15 00:58:37', 'pago', 29929.91, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1002, 150, '2023-10-18 07:29:46', 'pago', 43736.72, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1003, 150, '2023-03-13 16:33:13', 'pago', 55360.97, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1004, 150, '2023-06-25 11:53:50', 'interes', 1248.91, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1005, 150, '2023-06-10 04:01:55', 'pago', 80514.31, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1006, 151, '2024-02-03 07:31:03', 'deposito', 130580.32, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1007, 151, '2024-03-18 17:17:10', 'deposito', 90596.05, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1008, 151, '2024-08-24 07:23:24', 'comision', 74.51, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1009, 151, '2023-10-10 07:20:37', 'deposito', 148663.66, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1010, 151, '2023-03-07 14:32:08', 'comision', 82.68, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1011, 151, '2023-12-03 20:43:29', 'retiro', 69084.66, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1012, 152, '2025-01-24 03:19:01', 'retiro', 96980.24, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1013, 152, '2023-12-22 10:49:47', 'retiro', 91992.82, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1014, 152, '2024-03-01 09:04:14', 'deposito', 135004.7, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1015, 152, '2024-04-13 14:00:18', 'comision', 26.51, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1016, 152, '2023-04-08 14:19:43', 'comision', 95.11, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1017, 153, '2023-10-08 22:52:04', 'comision', 36.27, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1018, 153, '2024-12-15 07:54:36', 'retiro', 61750.6, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1019, 153, '2023-05-05 13:25:30', 'deposito', 113333.99, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1020, 153, '2025-02-23 11:52:11', 'retiro', 67695.3, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1021, 153, '2023-08-01 18:25:30', 'deposito', 69378.91, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1022, 153, '2024-10-16 16:49:02', 'retiro', 51614.29, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1023, 153, '2025-05-26 07:04:40', 'retiro', 5762.42, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1024, 154, '2024-12-27 04:58:08', 'retiro', 100577.31, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1025, 154, '2024-05-11 16:47:50', 'deposito', 12474.04, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1026, 154, '2024-12-31 15:56:13', 'deposito', 70671.08, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1027, 154, '2025-05-11 05:52:30', 'deposito', 125790.53, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1028, 154, '2023-04-13 06:27:10', 'retiro', 18710.29, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1029, 154, '2023-06-22 02:49:29', 'comision', 78.72, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1030, 155, '2024-03-27 13:02:15', 'deposito', 32579.2, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1031, 155, '2025-07-03 19:22:49', 'deposito', 66364.52, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1032, 155, '2025-05-06 23:06:43', 'comision', 67.69, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1033, 155, '2024-02-04 11:13:32', 'retiro', 7957.05, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1034, 155, '2023-02-19 13:44:25', 'deposito', 139330.2, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1035, 155, '2025-07-19 08:41:05', 'deposito', 13798.83, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1036, 155, '2023-01-29 00:31:48', 'retiro', 123096.93, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1037, 156, '2025-06-22 03:31:01', 'pago', 108629.32, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1038, 156, '2024-03-01 18:39:34', 'pago', 122362.09, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1039, 156, '2024-07-29 22:49:14', 'pago', 93738.54, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1040, 156, '2024-02-09 15:34:43', 'pago', 34937.98, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1041, 156, '2024-01-01 11:46:24', 'pago', 2347.69, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1042, 156, '2023-01-13 14:10:11', 'pago', 68870.51, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1043, 157, '2024-10-27 22:42:57', 'remesa_pago', 6686.45, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1044, 157, '2024-02-25 10:58:42', 'remesa_pago', 147467.06, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1045, 157, '2024-12-30 19:31:18', 'remesa_envio', 37865.83, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1046, 158, '2023-11-29 22:58:09', 'comision', 44.97, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1047, 158, '2023-12-07 06:23:00', 'comision', 78.55, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1048, 158, '2025-05-21 17:33:13', 'deposito', 50332.27, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1049, 158, '2025-07-22 21:18:01', 'retiro', 57417.47, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1050, 158, '2024-05-30 21:23:20', 'comision', 98.95, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1051, 158, '2023-01-22 22:26:26', 'deposito', 46396.41, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1052, 158, '2025-02-14 08:52:02', 'comision', 17.15, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1053, 158, '2024-01-19 18:09:29', 'retiro', 30381.57, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1054, 158, '2023-07-29 23:22:33', 'deposito', 35785.79, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1055, 158, '2025-08-26 16:09:20', 'comision', 88.96, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1056, 158, '2023-10-12 11:33:40', 'comision', 80.83, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1057, 158, '2024-06-17 15:06:20', 'comision', 83.14, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1058, 158, '2023-08-23 12:03:40', 'retiro', 36413.12, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1059, 158, '2023-02-25 09:02:30', 'comision', 72.67, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1060, 159, '2025-06-12 13:53:22', 'remesa_pago', 27613.47, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1061, 159, '2023-03-08 17:54:00', 'remesa_envio', 143053.81, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1062, 159, '2024-10-11 05:09:10', 'remesa_envio', 18921.59, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1063, 159, '2024-08-29 19:58:58', 'remesa_envio', 35522.89, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1064, 159, '2024-03-12 17:00:20', 'remesa_pago', 24707.41, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1065, 160, '2024-03-10 06:25:25', 'comision', 32.41, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1066, 160, '2024-08-13 16:19:15', 'comision', 28.13, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1067, 160, '2023-03-23 13:05:31', 'retiro', 56719.85, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1068, 160, '2024-03-27 15:23:23', 'comision', 64.85, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1069, 160, '2025-02-17 05:40:31', 'retiro', 3069.68, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1070, 160, '2024-03-13 03:01:49', 'retiro', 89317.99, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1071, 160, '2024-07-20 06:23:49', 'retiro', 57129.49, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1072, 160, '2024-04-09 10:18:42', 'retiro', 84365.1, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1073, 161, '2023-12-08 04:58:31', 'comision', 52.23, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1074, 161, '2025-07-27 06:54:14', 'deposito', 2023.86, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1075, 161, '2025-01-17 13:37:34', 'retiro', 60742.83, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1076, 161, '2025-08-20 14:22:07', 'comision', 43.58, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1077, 161, '2023-11-12 23:20:23', 'comision', 16.41, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1078, 161, '2025-08-01 04:31:55', 'retiro', 139826.22, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1079, 162, '2025-02-20 15:53:06', 'retiro', 115713.43, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1080, 162, '2024-06-05 17:47:24', 'comision', 71.96, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1081, 162, '2024-10-28 14:01:46', 'retiro', 110376.06, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1082, 162, '2024-05-04 01:15:22', 'retiro', 94679.81, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1083, 162, '2024-12-15 23:29:45', 'deposito', 39273.47, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1084, 162, '2025-08-24 05:21:55', 'retiro', 37187.48, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1085, 162, '2025-09-01 05:52:38', 'deposito', 17597.92, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1086, 162, '2024-10-21 13:59:37', 'retiro', 105939.86, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1087, 163, '2025-07-20 06:52:29', 'retiro', 24956.96, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1088, 163, '2023-09-16 11:00:12', 'comision', 97.09, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1089, 163, '2024-08-23 11:12:47', 'comision', 47.04, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1090, 163, '2023-04-22 23:09:45', 'comision', 79.9, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1091, 163, '2025-04-13 05:11:45', 'retiro', 112334.64, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1092, 163, '2024-12-16 11:13:03', 'deposito', 148055.12, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1093, 163, '2023-01-02 03:31:37', 'deposito', 116084.17, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1094, 163, '2024-06-21 15:10:36', 'comision', 35.95, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1095, 163, '2023-06-24 06:25:21', 'retiro', 28041.37, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1096, 163, '2023-07-22 17:42:42', 'deposito', 75441.8, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1097, 163, '2024-04-06 20:38:49', 'deposito', 27927.14, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1098, 163, '2025-02-06 06:39:10', 'deposito', 38976.85, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1099, 163, '2024-03-27 22:49:20', 'comision', 19.83, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1100, 164, '2023-10-28 03:07:13', 'retiro', 18789.77, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1101, 164, '2023-12-17 01:04:48', 'comision', 31.13, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1102, 164, '2024-11-19 03:40:13', 'deposito', 9252.36, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1103, 164, '2024-11-12 21:12:22', 'deposito', 14616.59, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1104, 164, '2025-03-21 00:15:51', 'retiro', 90487.43, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1105, 164, '2025-08-12 17:41:31', 'retiro', 113561.05, 'Retiro en cajero', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1106, 165, '2023-12-11 13:29:59', 'remesa_pago', 149916.83, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1107, 165, '2025-08-21 13:09:04', 'remesa_pago', 56827.51, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1108, 165, '2023-12-31 12:01:27', 'remesa_envio', 562.39, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1109, 165, '2025-01-12 05:03:21', 'remesa_envio', 90326.19, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1110, 166, '2025-08-31 09:02:56', 'retiro', 67842.52, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1111, 166, '2024-06-11 15:02:29', 'comision', 26.91, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1112, 166, '2023-01-18 23:04:30', 'retiro', 131027.83, 'Retiro en cajero', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1113, 166, '2024-11-25 16:10:36', 'deposito', 91053.78, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1114, 166, '2025-01-26 22:18:13', 'deposito', 52315.26, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1115, 166, '2024-11-05 03:39:26', 'comision', 44.64, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1116, 166, '2023-07-19 05:12:44', 'comision', 88.86, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1117, 166, '2023-02-02 04:39:19', 'retiro', 119543.43, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1118, 166, '2025-05-02 19:58:45', 'retiro', 25291.12, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1119, 167, '2024-05-08 19:41:06', 'remesa_envio', 36579.06, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1120, 168, '2023-04-19 15:50:02', 'pago', 24119.27, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1121, 168, '2025-07-13 13:57:44', 'interes', 1898.31, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1122, 168, '2025-01-06 09:22:47', 'interes', 1898.31, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1123, 168, '2024-11-12 04:56:33', 'interes', 1898.31, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1124, 169, '2025-06-11 08:08:54', 'pago', 96633.58, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1125, 169, '2025-07-21 13:53:43', 'interes', 1003.02, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1126, 169, '2023-08-17 09:25:59', 'pago', 43717.38, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1127, 169, '2023-04-02 12:23:15', 'pago', 111718.2, 'Pago de cuota del préstamo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1128, 169, '2024-08-09 13:23:20', 'pago', 128014.21, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1129, 169, '2024-08-13 00:03:40', 'interes', 1003.02, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1130, 169, '2024-08-27 19:30:02', 'pago', 127083.08, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1131, 169, '2023-11-24 13:17:24', 'pago', 78010.73, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1132, 170, '2023-08-16 03:52:50', 'remesa_pago', 1477.36, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1133, 170, '2023-11-20 05:16:06', 'remesa_pago', 125598.78, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1134, 170, '2024-11-27 16:35:40', 'remesa_envio', 90259.67, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1135, 170, '2025-02-03 01:15:01', 'remesa_pago', 46402.82, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1136, 170, '2023-10-08 20:53:51', 'remesa_pago', 94698.45, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1137, 171, '2023-10-26 13:42:55', 'remesa_envio', 147173.3, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1138, 171, '2023-06-06 07:40:05', 'remesa_envio', 105091.07, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1139, 171, '2025-08-03 06:31:04', 'remesa_pago', 109136.58, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1140, 171, '2025-04-14 05:47:45', 'remesa_envio', 82236.64, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1141, 172, '2024-11-25 17:14:12', 'remesa_pago', 113681.36, 'Pago de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1142, 172, '2023-03-15 19:13:05', 'remesa_pago', 42426.38, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1143, 172, '2024-12-18 19:57:08', 'remesa_pago', 14688.2, 'Pago de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1144, 172, '2025-02-09 21:07:52', 'remesa_envio', 127486.48, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1145, 173, '2024-11-01 05:57:35', 'comision', 22.38, 'Comisión por servicios', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1146, 173, '2023-10-26 05:16:22', 'deposito', 32798.66, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1147, 173, '2025-01-22 23:42:39', 'deposito', 54397.64, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1148, 173, '2023-04-15 05:22:26', 'retiro', 142564.68, 'Retiro en cajero', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1149, 173, '2024-11-26 06:07:29', 'deposito', 14497.56, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1150, 173, '2023-07-03 01:54:37', 'deposito', 147043.49, 'Depósito en efectivo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1151, 173, '2024-08-30 15:47:41', 'deposito', 94083.18, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1152, 173, '2023-09-08 01:14:15', 'deposito', 36204.23, 'Depósito en efectivo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1153, 173, '2023-11-06 21:42:19', 'deposito', 97954.27, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1154, 173, '2025-03-05 23:58:33', 'deposito', 116681.85, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1155, 173, '2023-10-09 23:01:21', 'comision', 50.06, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1156, 173, '2023-05-03 04:14:46', 'deposito', 18395.53, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1157, 174, '2023-01-24 21:21:59', 'remesa_pago', 41131.35, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1158, 174, '2025-03-24 21:35:09', 'remesa_envio', 57655.59, 'Envío de remesa', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1159, 175, '2024-08-08 04:33:34', 'remesa_envio', 48851.82, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1160, 175, '2023-07-09 14:45:27', 'remesa_envio', 59130.1, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1161, 175, '2025-03-13 19:17:59', 'remesa_pago', 9683.36, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1162, 176, '2024-12-31 23:43:39', 'deposito', 113050.88, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1163, 176, '2024-11-05 04:16:18', 'deposito', 129314.32, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1164, 176, '2023-01-06 20:11:48', 'retiro', 120096.89, 'Retiro en cajero', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1165, 176, '2023-02-10 04:41:24', 'comision', 28.56, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1166, 176, '2023-03-31 20:28:47', 'retiro', 127732.37, 'Retiro en cajero', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1167, 176, '2023-03-28 04:32:26', 'comision', 36.87, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1168, 176, '2023-06-25 15:24:10', 'comision', 10.01, 'Comisión por servicios', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1169, 176, '2023-02-17 18:54:44', 'retiro', 98907.72, 'Retiro en cajero', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1170, 176, '2023-05-24 21:00:37', 'retiro', 104295.71, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1171, 176, '2025-07-21 12:49:12', 'comision', 58.44, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1172, 176, '2024-12-05 03:36:17', 'comision', 83.78, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1173, 176, '2023-02-07 06:50:51', 'deposito', 45026.41, 'Depósito en efectivo', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1174, 176, '2023-05-18 21:55:24', 'comision', 29.44, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1175, 177, '2023-05-12 22:39:27', 'remesa_pago', 11246.51, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1176, 177, '2023-09-24 13:54:00', 'remesa_envio', 60068.9, 'Envío de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1177, 177, '2025-08-25 09:15:15', 'remesa_pago', 141035.88, 'Pago de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1178, 178, '2023-07-28 02:34:08', 'remesa_pago', 149304.35, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1179, 178, '2025-01-01 13:32:57', 'remesa_envio', 63011.0, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1180, 178, '2023-11-20 15:47:16', 'remesa_pago', 3983.89, 'Pago de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1181, 178, '2023-09-11 02:49:21', 'remesa_pago', 18780.72, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1182, 178, '2024-12-01 19:57:55', 'remesa_pago', 9987.31, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1183, 179, '2025-07-20 12:08:34', 'remesa_pago', 22034.81, 'Pago de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1184, 179, '2023-10-08 00:21:32', 'remesa_envio', 56635.68, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1185, 179, '2024-01-23 03:49:22', 'remesa_envio', 26442.13, 'Envío de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1186, 180, '2025-04-21 17:49:35', 'deposito', 79391.12, 'Depósito en efectivo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1187, 180, '2025-06-05 10:16:01', 'comision', 34.39, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1188, 180, '2025-07-07 01:44:46', 'deposito', 47767.66, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1189, 180, '2023-07-05 12:34:02', 'comision', 71.0, 'Comisión por servicios', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1190, 180, '2024-07-18 21:38:57', 'retiro', 71581.59, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1191, 180, '2023-09-23 00:20:44', 'comision', 56.22, 'Comisión por servicios', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1192, 180, '2024-11-04 04:36:03', 'deposito', 56882.22, 'Depósito en efectivo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1193, 180, '2023-02-24 23:16:20', 'retiro', 106154.61, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1194, 180, '2024-11-25 22:09:43', 'retiro', 106047.34, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1195, 180, '2024-03-25 12:53:19', 'retiro', 75384.16, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1196, 180, '2024-03-14 18:57:15', 'comision', 89.32, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1197, 180, '2023-11-09 23:08:33', 'deposito', 142123.45, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1198, 180, '2025-02-28 11:23:11', 'deposito', 95238.03, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1199, 180, '2025-01-17 08:44:22', 'deposito', 24850.46, 'Depósito en efectivo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1200, 181, '2025-01-31 10:24:27', 'remesa_pago', 121271.2, 'Pago de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1201, 182, '2024-11-24 18:31:14', 'pago', 72000.43, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1202, 182, '2024-12-02 19:23:03', 'pago', 60880.17, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1203, 182, '2023-07-14 00:15:55', 'interes', 2576.43, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1204, 182, '2025-02-06 12:33:47', 'pago', 149133.87, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1205, 182, '2024-12-01 22:10:48', 'pago', 91145.29, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1206, 182, '2024-11-21 19:03:38', 'pago', 26304.65, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1207, 182, '2025-05-09 04:51:14', 'interes', 2576.43, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1208, 182, '2024-03-08 18:02:27', 'interes', 2576.43, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1209, 182, '2024-01-18 04:07:21', 'interes', 2576.43, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1210, 183, '2023-10-25 10:53:33', 'interes', 670.41, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1211, 183, '2023-09-29 07:45:26', 'pago', 110730.06, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1212, 183, '2024-02-08 07:55:03', 'interes', 670.41, 'Interés mensual', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1213, 183, '2025-04-25 01:17:23', 'interes', 670.41, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1214, 184, '2023-02-28 12:57:08', 'pago', 92367.98, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1215, 184, '2023-11-02 12:53:05', 'pago', 872.65, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1216, 184, '2024-02-16 12:54:29', 'pago', 15290.53, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1217, 184, '2023-07-22 03:05:07', 'pago', 61666.79, 'Pago de cuota del préstamo', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1218, 184, '2023-01-08 05:39:58', 'interes', 883.53, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1219, 184, '2024-04-26 14:23:40', 'interes', 883.53, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1220, 184, '2024-01-09 15:35:43', 'pago', 80510.46, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1221, 184, '2023-04-22 15:58:04', 'interes', 883.53, 'Interés mensual', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1222, 184, '2023-05-24 12:52:45', 'interes', 883.53, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1223, 184, '2024-01-03 07:13:33', 'pago', 28516.1, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1224, 185, '2024-02-09 15:19:48', 'remesa_pago', 135159.57, 'Pago de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1225, 185, '2024-11-13 07:14:42', 'remesa_pago', 143958.86, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1226, 186, '2024-03-07 17:48:23', 'remesa_pago', 119993.03, 'Pago de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1227, 187, '2025-02-08 14:33:32', 'remesa_pago', 19799.51, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1228, 187, '2025-03-22 00:46:12', 'remesa_envio', 23415.74, 'Envío de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1229, 187, '2023-01-14 08:36:39', 'remesa_envio', 101778.72, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1230, 188, '2024-09-03 00:17:32', 'retiro', 72080.93, 'Retiro en cajero', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1231, 188, '2024-05-12 03:00:28', 'retiro', 37237.32, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1232, 188, '2025-01-16 18:36:49', 'deposito', 37495.07, 'Depósito en efectivo', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1233, 188, '2025-06-03 09:35:41', 'comision', 32.26, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1234, 188, '2023-07-23 17:15:14', 'comision', 80.44, 'Comisión por servicios', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1235, 188, '2024-12-18 18:17:21', 'comision', 26.31, 'Comisión por servicios', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1236, 188, '2024-10-06 23:06:02', 'deposito', 34484.69, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1237, 188, '2024-02-15 01:23:48', 'retiro', 148560.78, 'Retiro en cajero', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1238, 188, '2024-03-12 00:38:34', 'comision', 27.97, 'Comisión por servicios', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1239, 188, '2024-01-25 14:49:45', 'comision', 37.58, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1240, 188, '2023-08-16 12:14:23', 'retiro', 71931.37, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1241, 189, '2024-10-21 01:52:50', 'interes', 2266.06, 'Interés mensual', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1242, 189, '2023-10-03 13:14:14', 'interes', 2266.06, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1243, 189, '2024-12-29 15:13:17', 'pago', 48044.15, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1244, 189, '2023-07-06 01:29:19', 'pago', 7914.38, 'Pago de cuota del préstamo', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1245, 189, '2023-08-06 10:23:17', 'interes', 2266.06, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1246, 189, '2025-07-19 22:04:58', 'pago', 64693.04, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1247, 189, '2025-08-29 17:53:13', 'interes', 2266.06, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1248, 189, '2023-11-08 04:03:38', 'pago', 100375.24, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1249, 189, '2025-02-27 04:44:39', 'interes', 2266.06, 'Interés mensual', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1250, 190, '2025-01-30 21:26:29', 'remesa_pago', 35814.01, 'Pago de remesa', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1251, 190, '2023-08-04 21:16:28', 'remesa_pago', 13175.95, 'Pago de remesa', 2, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1252, 190, '2023-05-14 22:55:17', 'remesa_envio', 6251.74, 'Envío de remesa', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1253, 191, '2024-12-22 16:13:47', 'deposito', 11324.45, 'Depósito en efectivo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1254, 191, '2024-09-25 12:29:04', 'retiro', 108830.06, 'Retiro en cajero', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1255, 191, '2024-06-30 05:35:42', 'deposito', 19262.01, 'Depósito en efectivo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1256, 191, '2024-07-17 09:11:39', 'comision', 97.76, 'Comisión por servicios', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1257, 191, '2024-04-04 22:55:57', 'comision', 20.57, 'Comisión por servicios', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1258, 191, '2023-03-11 17:34:44', 'retiro', 78612.04, 'Retiro en cajero', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1259, 191, '2025-03-20 00:47:47', 'deposito', 89913.13, 'Depósito en efectivo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1260, 191, '2023-10-24 01:39:16', 'comision', 15.47, 'Comisión por servicios', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1261, 192, '2024-05-21 19:23:11', 'pago', 24911.18, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1262, 192, '2024-01-29 20:28:47', 'interes', 776.51, 'Interés mensual', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1263, 192, '2024-09-13 09:53:05', 'pago', 27691.54, 'Pago de cuota del préstamo', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1264, 192, '2024-08-08 07:55:48', 'pago', 131885.34, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1265, 192, '2024-04-11 18:20:36', 'interes', 776.51, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1266, 192, '2025-05-22 08:01:19', 'interes', 776.51, 'Interés mensual', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1267, 192, '2024-07-19 04:20:11', 'pago', 33667.02, 'Pago de cuota del préstamo', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1268, 192, '2023-09-01 10:37:32', 'pago', 95978.34, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1269, 192, '2025-08-07 04:50:28', 'interes', 776.51, 'Interés mensual', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1270, 193, '2025-04-23 07:38:41', 'remesa_envio', 309.85, 'Envío de remesa', 6, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1271, 193, '2024-10-09 22:01:59', 'remesa_pago', 48751.82, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1272, 194, '2025-01-09 04:51:52', 'interes', 673.76, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1273, 194, '2023-10-29 11:49:10', 'pago', 93930.7, 'Pago de cuota del préstamo', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1274, 194, '2025-04-23 12:56:33', 'pago', 109598.45, 'Pago de cuota del préstamo', 5, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1275, 194, '2023-06-30 09:19:12', 'pago', 80654.57, 'Pago de cuota del préstamo', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1276, 194, '2023-04-19 13:54:27', 'interes', 673.76, 'Interés mensual', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1277, 194, '2024-07-18 07:30:21', 'interes', 673.76, 'Interés mensual', 4, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1278, 194, '2023-11-29 09:47:11', 'pago', 87291.4, 'Pago de cuota del préstamo', 7, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1279, 195, '2024-04-01 08:26:12', 'remesa_pago', 55359.14, 'Pago de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1280, 195, '2023-04-06 18:03:26', 'remesa_envio', 68962.58, 'Envío de remesa', 3, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1281, 196, '2024-08-06 17:51:33', 'remesa_envio', 97169.88, 'Envío de remesa', 1, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1282, 196, '2023-11-14 05:55:54', 'remesa_envio', 122643.13, 'Envío de remesa', 10, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1283, 197, '2023-03-13 05:13:31', 'remesa_envio', 64016.62, 'Envío de remesa', 8, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1284, 197, '2025-07-19 23:29:17', 'remesa_pago', 15125.05, 'Pago de remesa', 9, SYSDATETIME());
INSERT INTO dbo.dbr_transaccion (transaccion_id, producto_id, fecha_transaccion, tipo_transaccion, monto, descripcion,
                                 agencia_id, creado_en)
VALUES (1285, 191, '2025-12-20 00:47:47', 'deposito', 589913.13, 'Depósito en efectivo', 1, SYSDATETIME());
SET IDENTITY_INSERT dbo.dbr_transaccion OFF;
GO

SET IDENTITY_INSERT dbo.dbr_evaluacion_riesgo ON;

INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (1, 1, '2022-10-04', 'A', 70.62, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (2, 2, '2022-01-26', 'A', 92.08, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (3, 2, '2022-03-08', 'C', 36.07, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (4, 2, '2022-05-05', 'B', 63.33, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (5, 3, '2022-09-23', 'A', 86.31, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (6, 3, '2025-03-08', 'A', 86.34, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (7, 4, '2022-04-14', 'A', 80.6, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (8, 4, '2023-01-08', 'D', 30.53, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (9, 5, '2022-04-04', 'B', 53.55, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (10, 5, '2022-08-06', 'D', 36.87, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (11, 5, '2024-06-03', 'A', 85.91, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (12, 6, '2024-06-04', 'A', 84.98, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (13, 6, '2024-10-27', 'A', 97.21, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (14, 6, '2025-03-22', 'C', 55.85, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (15, 7, '2023-06-05', 'B', 78.79, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (16, 7, '2025-02-04', 'A', 99.84, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (17, 7, '2025-08-24', 'A', 79.58, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (18, 8, '2023-07-14', 'B', 66.16, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (19, 8, '2024-03-26', 'B', 56.9, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (20, 8, '2025-10-26', 'C', 45.81, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (21, 9, '2023-01-12', 'B', 78.73, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (22, 9, '2023-06-01', 'A', 80.48, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (23, 9, '2023-12-03', 'D', 34.57, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (24, 10, '2025-04-07', 'C', 31.68, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (25, 11, '2022-12-14', 'A', 87.45, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (26, 11, '2023-07-24', 'B', 54.75, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (27, 11, '2024-01-23', 'A', 77.35, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (28, 12, '2023-03-16', 'B', 58.99, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (29, 12, '2023-12-17', 'A', 93.44, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (30, 13, '2022-03-02', 'A', 74.81, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (31, 13, '2022-10-25', 'B', 78.45, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (32, 14, '2024-10-17', 'E', 10.43, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (33, 14, '2024-12-08', 'A', 76.36, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (34, 14, '2025-03-09', 'A', 75.51, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (35, 15, '2022-12-15', 'A', 81.14, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (36, 15, '2025-06-21', 'A', 73.13, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (37, 15, '2025-07-06', 'C', 40.06, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (38, 16, '2022-02-07', 'B', 72.7, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (39, 17, '2022-10-26', 'B', 51.44, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (40, 17, '2023-05-03', 'A', 99.42, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (41, 17, '2023-11-02', 'E', 10.0, 'Evaluación de riesgo categoría E');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (42, 18, '2022-06-14', 'D', 25.11, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (43, 18, '2024-03-23', 'C', 30.71, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (44, 19, '2022-05-06', 'A', 88.78, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (45, 19, '2023-11-15', 'A', 76.47, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (46, 20, '2023-09-17', 'E', 12.17, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (47, 21, '2024-06-20', 'D', 22.93, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (48, 21, '2025-03-11', 'C', 41.63, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (49, 22, '2022-03-19', 'D', 26.41, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (50, 22, '2022-03-25', 'C', 32.62, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (51, 22, '2025-02-26', 'A', 98.02, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (52, 23, '2022-03-23', 'C', 37.74, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (53, 23, '2024-06-03', 'A', 96.3, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (54, 24, '2022-10-16', 'A', 95.77, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (55, 25, '2023-08-12', 'A', 96.27, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (56, 25, '2024-06-03', 'B', 69.32, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (57, 25, '2025-09-15', 'A', 94.64, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (58, 26, '2024-07-06', 'B', 75.61, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (59, 27, '2022-06-15', 'D', 23.95, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (60, 27, '2025-11-18', 'C', 57.52, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (61, 28, '2022-06-11', 'E', 9.73, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (62, 28, '2023-07-11', 'B', 58.35, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (63, 29, '2025-03-21', 'A', 87.05, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (64, 30, '2022-06-26', 'A', 96.04, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (65, 30, '2025-08-07', 'B', 58.1, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (66, 31, '2023-02-09', 'B', 58.95, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (67, 32, '2023-01-03', 'D', 22.86, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (68, 32, '2023-11-09', 'A', 75.96, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (69, 33, '2023-12-14', 'A', 90.79, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (70, 33, '2025-09-23', 'A', 93.49, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (71, 34, '2023-06-22', 'E', 18.78, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (72, 35, '2024-01-05', 'E', 8.13, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (73, 35, '2024-02-26', 'A', 83.52, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (74, 35, '2025-03-16', 'A', 83.48, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (75, 36, '2022-04-24', 'E', 8.4, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (76, 37, '2025-04-12', 'A', 75.73, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (77, 38, '2024-06-01', 'A', 79.21, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (78, 39, '2025-11-15', 'B', 60.55, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (79, 40, '2024-02-06', 'A', 87.85, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (80, 40, '2025-07-12', 'A', 95.35, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (81, 41, '2022-02-26', 'C', 32.69, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (82, 41, '2024-12-20', 'D', 13.11, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (83, 42, '2022-11-10', 'C', 46.55, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (84, 42, '2022-11-15', 'D', 38.52, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (85, 42, '2025-04-08', 'C', 43.92, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (86, 43, '2023-09-10', 'A', 97.08, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (87, 43, '2024-11-09', 'B', 50.12, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (88, 43, '2025-01-12', 'A', 70.79, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (89, 44, '2024-06-06', 'B', 74.86, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (90, 44, '2025-04-18', 'B', 53.87, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (91, 44, '2025-04-20', 'E', 3.47, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (92, 45, '2022-12-26', 'B', 73.53, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (93, 45, '2023-07-08', 'B', 57.81, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (94, 45, '2023-09-04', 'D', 16.11, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (95, 46, '2022-11-25', 'C', 57.62, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (96, 46, '2023-01-20', 'A', 92.27, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (97, 47, '2023-05-07', 'B', 57.36, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (98, 47, '2024-03-08', 'C', 53.11, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (99, 48, '2022-03-21', 'D', 13.33, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (100, 48, '2022-11-19', 'A', 74.26, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (101, 49, '2022-02-16', 'C', 57.38, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (102, 50, '2025-01-14', 'A', 98.78, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (103, 51, '2024-01-06', 'B', 68.94, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (104, 51, '2025-03-06', 'A', 80.28, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (105, 51, '2025-07-11', 'E', 12.0, 'Evaluación de riesgo categoría E');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (106, 52, '2022-09-01', 'A', 96.96, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (107, 52, '2023-04-28', 'A', 72.5, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (108, 52, '2024-02-07', 'A', 78.21, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (109, 53, '2024-12-18', 'B', 64.01, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (110, 54, '2023-04-22', 'C', 51.52, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (111, 54, '2025-04-09', 'A', 93.79, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (112, 55, '2023-12-16', 'B', 63.38, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (113, 56, '2024-10-04', 'B', 61.22, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (114, 56, '2025-07-07', 'A', 75.02, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (115, 57, '2024-07-01', 'A', 94.27, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (116, 57, '2024-10-14', 'A', 77.36, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (117, 57, '2024-10-27', 'A', 74.35, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (118, 58, '2024-12-01', 'C', 36.41, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (119, 59, '2023-09-03', 'A', 76.52, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (120, 59, '2025-05-20', 'C', 58.39, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (121, 60, '2022-10-21', 'A', 75.91, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (122, 60, '2025-06-27', 'B', 79.71, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (123, 60, '2025-11-25', 'A', 75.13, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (124, 61, '2023-10-01', 'C', 47.27, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (125, 61, '2024-01-21', 'B', 53.93, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (126, 62, '2022-06-21', 'A', 84.1, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (127, 63, '2024-05-11', 'B', 59.4, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (128, 63, '2024-07-03', 'A', 90.89, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (129, 64, '2022-01-05', 'A', 79.69, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (130, 64, '2022-01-08', 'B', 55.11, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (131, 64, '2022-06-20', 'D', 21.07, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (132, 65, '2022-05-26', 'A', 71.44, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (133, 66, '2024-12-20', 'A', 74.13, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (134, 66, '2025-05-23', 'A', 95.86, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (135, 67, '2023-10-16', 'B', 79.29, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (136, 67, '2025-11-04', 'C', 36.77, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (137, 68, '2022-06-18', 'C', 36.18, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (138, 68, '2023-11-21', 'E', 1.21, 'Evaluación de riesgo categoría E');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (139, 69, '2025-07-07', 'B', 60.21, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (140, 70, '2022-03-08', 'D', 21.57, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (141, 70, '2024-05-23', 'B', 56.09, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (142, 70, '2025-11-05', 'A', 82.69, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (143, 71, '2022-03-15', 'A', 70.86, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (144, 71, '2022-12-04', 'B', 57.97, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (145, 71, '2023-01-15', 'A', 82.94, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (146, 72, '2022-08-09', 'B', 71.96, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (147, 72, '2024-02-02', 'A', 82.08, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (148, 72, '2025-09-11', 'B', 64.81, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (149, 73, '2022-01-19', 'A', 71.98, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (150, 73, '2022-04-04', 'A', 88.61, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (151, 73, '2022-11-08', 'A', 73.04, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (152, 74, '2023-04-12', 'A', 70.09, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (153, 74, '2024-08-07', 'D', 28.66, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (154, 74, '2024-12-20', 'D', 30.64, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (155, 75, '2022-03-06', 'B', 50.62, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (156, 75, '2022-11-16', 'D', 15.12, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (157, 75, '2024-08-05', 'A', 80.56, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (158, 76, '2025-04-16', 'A', 94.57, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (159, 77, '2023-03-25', 'A', 79.14, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (160, 77, '2023-09-17', 'B', 72.04, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (161, 78, '2025-01-27', 'A', 91.3, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (162, 78, '2025-05-12', 'C', 55.71, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (163, 79, '2022-03-14', 'A', 70.93, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (164, 79, '2023-11-05', 'B', 62.92, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (165, 79, '2025-02-09', 'A', 97.62, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (166, 80, '2024-11-22', 'B', 77.37, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (167, 81, '2023-05-22', 'A', 87.39, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (168, 81, '2024-06-13', 'C', 33.69, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (169, 81, '2025-05-10', 'B', 73.78, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (170, 82, '2022-08-22', 'A', 90.43, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (171, 83, '2023-05-16', 'A', 83.62, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (172, 83, '2024-02-26', 'C', 33.7, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (173, 84, '2025-06-22', 'C', 31.5, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (174, 85, '2023-02-23', 'A', 87.56, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (175, 85, '2024-03-24', 'A', 84.2, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (176, 86, '2022-05-10', 'B', 76.28, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (177, 86, '2024-03-19', 'A', 93.03, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (178, 86, '2025-07-13', 'B', 55.99, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (179, 87, '2025-07-04', 'A', 83.26, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (180, 87, '2025-09-06', 'D', 31.38, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (181, 88, '2025-01-18', 'A', 93.0, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (182, 88, '2025-07-14', 'A', 97.21, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (183, 89, '2024-01-25', 'B', 63.88, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (184, 89, '2024-03-20', 'B', 75.18, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (185, 89, '2025-03-13', 'A', 99.59, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (186, 90, '2022-02-24', 'B', 65.32, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (187, 90, '2022-05-19', 'C', 45.49, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (188, 90, '2025-12-11', 'E', 2.73, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (189, 91, '2023-05-21', 'A', 72.01, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (190, 91, '2024-12-01', 'D', 25.59, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (191, 91, '2025-10-23', 'A', 70.74, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (192, 92, '2022-02-10', 'C', 55.25, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (193, 92, '2025-08-06', 'C', 50.44, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (194, 93, '2022-03-05', 'C', 46.4, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (195, 93, '2022-07-05', 'A', 90.03, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (196, 93, '2023-03-17', 'B', 70.03, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (197, 94, '2022-08-14', 'B', 50.33, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (198, 94, '2024-08-04', 'B', 76.8, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (199, 94, '2025-03-01', 'A', 97.21, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (200, 95, '2023-06-17', 'D', 25.1, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (201, 95, '2025-05-01', 'C', 41.72, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (202, 96, '2023-05-26', 'C', 39.09, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (203, 96, '2023-06-21', 'D', 29.35, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (204, 96, '2024-08-23', 'B', 69.77, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (205, 97, '2024-03-23', 'C', 32.03, 'Evaluación de riesgo categoría C');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (206, 97, '2024-10-19', 'C', 36.95, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (207, 97, '2024-10-20', 'B', 70.38, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (208, 98, '2023-02-06', 'C', 41.52, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (209, 99, '2022-10-09', 'A', 95.4, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (210, 100, '2022-03-11', 'A', 99.67, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (211, 100, '2022-12-15', 'A', 77.57, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (212, 101, '2023-04-24', 'B', 73.7, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (213, 101, '2023-07-27', 'A', 98.79, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (214, 102, '2023-01-12', 'C', 47.05, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (215, 103, '2023-11-24', 'A', 94.83, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (216, 103, '2025-04-27', 'A', 96.99, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (217, 104, '2025-07-21', 'A', 72.13, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (218, 105, '2024-01-08', 'C', 38.7, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (219, 105, '2024-02-04', 'A', 80.74, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (220, 105, '2025-04-02', 'A', 78.64, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (221, 106, '2024-07-20', 'A', 90.93, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (222, 107, '2022-06-14', 'A', 80.04, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (223, 107, '2024-11-01', 'A', 86.41, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (224, 108, '2022-04-16', 'D', 27.94, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (225, 108, '2022-06-03', 'A', 86.54, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (226, 108, '2022-10-20', 'A', 71.25, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (227, 109, '2023-01-02', 'A', 93.45, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (228, 109, '2023-11-12', 'B', 61.38, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (229, 109, '2025-08-10', 'A', 84.47, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (230, 110, '2023-07-23', 'A', 73.54, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (231, 110, '2025-09-05', 'D', 20.55, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (232, 111, '2023-04-03', 'B', 56.81, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (233, 112, '2022-01-28', 'A', 71.31, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (234, 112, '2022-03-15', 'B', 57.33, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (235, 112, '2023-01-03', 'B', 64.36, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (236, 113, '2022-05-18', 'A', 91.16, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (237, 114, '2025-12-10', 'D', 33.41, 'Evaluación de riesgo categoría D');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (238, 115, '2022-01-12', 'D', 31.17, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (239, 115, '2023-09-09', 'A', 76.11, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (240, 115, '2024-12-18', 'E', 4.61, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (241, 116, '2022-06-24', 'C', 34.26, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (242, 117, '2025-01-09', 'A', 81.53, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (243, 117, '2025-02-01', 'A', 78.37, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (244, 117, '2025-11-25', 'B', 75.88, 'Evaluación de riesgo categoría B');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (245, 118, '2023-04-13', 'A', 82.93, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (246, 119, '2022-09-25', 'C', 40.09, NULL);
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (247, 119, '2024-01-20', 'A', 92.6, 'Evaluación de riesgo categoría A');
INSERT INTO dbo.dbr_evaluacion_riesgo (evaluacion_id, cliente_id, fecha_evaluacion, categoria_riesgo, puntaje,
                                       observaciones)
VALUES (248, 120, '2024-12-27', 'B', 75.97, NULL);
SET IDENTITY_INSERT dbo.dbr_evaluacion_riesgo OFF;
GO

INSERT INTO dbo.dbr_categoria_riesgo (codigo_categoria, descripcion)
VALUES ('A', 'Al día o con hasta 1 mes de mora'),
       ('B', 'Más de 1 hasta 2 meses de mora'),
       ('C', 'Más de 2 hasta 4 meses de mora'),
       ('D', 'Más de 4 hasta 6 meses de mora'),
       ('E', 'Más de 6 meses de mora');
GO


--Alejandro Daniel Montufar Reyes