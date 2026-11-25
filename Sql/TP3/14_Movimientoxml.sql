/*
tabla de movimientos.
   Simulacion_TP3.sql copia aqui, una sola vez, los movimientos del XML de
   operaciones (con nodes(), sin volver a recorrer el XML). Despues
   dbo.sp_ProcesarCuentaDia toma de aqui los movimientos pendientes de cada
   cuenta y los marca como procesados DENTRO de la misma transaccion en que
   los aplica. Asi la tabla dice exactamente que falta si la simulacion se
   cae a medias.
     Secuencia        posicion del movimiento dentro de su fecha (1, 2, ...),
                      en el orden del XML. Con la fecha forma la referencia
                      del movimiento: '2026-04-20#3'.
     FlagProcesado    0 pendiente, 1 procesado (aplicado o rechazado).
     CodigoResultado  NULL mientras esta pendiente; 0 aplicado; otro valor es
                      el codigo del rechazo (ver sp_ProcesarCuentaDia).
   Se puede correr varias veces: si la tabla ya existe, no hace nada.
   Orden de instalacion: despues de 13_Comprobantes.sql y antes de
   SPs/Sp_ProcesarCuentaDia.sql.
*/
USE CuentaAhorrosTP2;
GO

IF OBJECT_ID('dbo.MovimientoXml', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MovimientoXml (
        Id              INT           IDENTITY(1,1) NOT NULL,
        FechaOperacion  DATE          NOT NULL,
        Secuencia       INT           NOT NULL,
        NumeroCuenta    VARCHAR(16)   NOT NULL,
        TipoMovimiento  VARCHAR(64)   NOT NULL,
        Monto           DECIMAL(18,2) NOT NULL,
        Descripcion     NVARCHAR(256) NOT NULL,
        FlagProcesado   BIT           NOT NULL
            CONSTRAINT DF_MovimientoXml_Procesado DEFAULT (0),
        CodigoResultado INT           NULL,
        CONSTRAINT PK_MovimientoXml PRIMARY KEY (Id),
        CONSTRAINT UQ_MovimientoXml_FechaSecuencia
            UNIQUE (FechaOperacion, Secuencia),
        CONSTRAINT CK_MovimientoXml_Secuencia CHECK (Secuencia > 0),
        CONSTRAINT CK_MovimientoXml_Resultado
            CHECK ((FlagProcesado = 0 AND CodigoResultado IS NULL)
                OR (FlagProcesado = 1 AND CodigoResultado IS NOT NULL))
    );
END;
GO

-- Verificacion: debe salir la tabla
SELECT name AS TablaDeMovimientos
FROM sys.tables
WHERE name = 'MovimientoXml';
GO