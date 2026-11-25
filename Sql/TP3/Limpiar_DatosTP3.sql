/*
   Limpieza de datos de la simulacion.
   Borra TODOS los datos de cuentas y movimientos, y el control de la
   simulacion (corridas, fechas y la tabla de movimientos MovimientoXml),
   para poder volver a correr
   Simulacion_TP3.sql desde la primera fecha. Tambien borra los
   comprobantes (dbo.Comprobante). NO toca los catalogos
   (TipoMoneda, TipoCuentaAhorro, TipoMovimiento, etc.), ni los SP, ni el
   trigger. Tambien deja vacia dbo.ErrorBD y reinicia los Id para que
   empiecen en 1.
   El orden de los DELETE respeta las llaves foraneas (primero las hijas).
*/
USE CuentaAhorrosTP2;
GO

-- Control de la simulacion. Solo se reinicia el Id si la tabla tenia filas
-- (en una tabla recien creada, RESEED 0 haria que el primer Id fuera 0).
IF OBJECT_ID('dbo.ControlSimulacion', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.ControlSimulacion)
    BEGIN
        DELETE FROM dbo.ControlSimulacion;
        DBCC CHECKIDENT ('dbo.ControlSimulacion', RESEED, 0);
    END;
END;

IF OBJECT_ID('dbo.CorridaSimulacion', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.CorridaSimulacion)
    BEGIN
        DELETE FROM dbo.CorridaSimulacion;
        DBCC CHECKIDENT ('dbo.CorridaSimulacion', RESEED, 0);
    END;
END;

-- Tabla de movimientos del XML: la simulacion la vuelve a llenar
IF OBJECT_ID('dbo.MovimientoXml', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.MovimientoXml)
    BEGIN
        DELETE FROM dbo.MovimientoXml;
        DBCC CHECKIDENT ('dbo.MovimientoXml', RESEED, 0);
    END;
END;

DELETE FROM dbo.Bitacora;
DELETE FROM dbo.UsuarioPuedeVer;
DELETE FROM dbo.Usuario;
DELETE FROM dbo.Movimiento;

-- Comprobantes: despues de Movimiento (que tiene el FK al comprobante) y
-- antes de Cuenta. Solo se reinicia el Id si la tabla tenia filas.
IF OBJECT_ID('dbo.Comprobante', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.Comprobante)
    BEGIN
        DELETE FROM dbo.Comprobante;
        DBCC CHECKIDENT ('dbo.Comprobante', RESEED, 0);
    END;
END;

DELETE FROM dbo.EstadoCuenta;
DELETE FROM dbo.Beneficiario;
DELETE FROM dbo.Cuenta;
DELETE FROM dbo.Telefono;
DELETE FROM dbo.Persona;
DELETE FROM dbo.ErrorBD;

DBCC CHECKIDENT ('dbo.Bitacora',        RESEED, 0);
DBCC CHECKIDENT ('dbo.UsuarioPuedeVer', RESEED, 0);
DBCC CHECKIDENT ('dbo.Usuario',         RESEED, 0);
DBCC CHECKIDENT ('dbo.Movimiento',      RESEED, 0);
DBCC CHECKIDENT ('dbo.EstadoCuenta',    RESEED, 0);
DBCC CHECKIDENT ('dbo.Beneficiario',    RESEED, 0);
DBCC CHECKIDENT ('dbo.Cuenta',          RESEED, 0);
DBCC CHECKIDENT ('dbo.Telefono',        RESEED, 0);
DBCC CHECKIDENT ('dbo.Persona',         RESEED, 0);
DBCC CHECKIDENT ('dbo.ErrorBD',         RESEED, 0);
GO

-- Verificacion: todo en 0 y los catalogos intactos (TipoMovimiento = 18)
SELECT (SELECT COUNT(*) FROM dbo.Persona)           AS Personas,
       (SELECT COUNT(*) FROM dbo.Usuario)           AS Usuarios,
       (SELECT COUNT(*) FROM dbo.Cuenta)            AS Cuentas,
       (SELECT COUNT(*) FROM dbo.EstadoCuenta)      AS Estados,
       (SELECT COUNT(*) FROM dbo.Movimiento)        AS Movimientos,
       (SELECT COUNT(*) FROM dbo.Comprobante)       AS Comprobantes,
       (SELECT COUNT(*) FROM dbo.ErrorBD)           AS Errores,
       (SELECT COUNT(*) FROM dbo.ControlSimulacion) AS FechasControl,
       (SELECT COUNT(*) FROM dbo.CorridaSimulacion) AS Corridas,
       (SELECT COUNT(*) FROM dbo.MovimientoXml)     AS MovimientosXml,
       (SELECT COUNT(*) FROM dbo.TipoMovimiento)    AS TiposMov_esperado_18;
GO


/*
SELECT * FROM dbo.Usuario WHERE NombreUsuario = 'fquiros';      -- 0 filas
SELECT * FROM dbo.Persona WHERE ValorDocumentoIdentidad = '130004000';  -- 0
*/

/*
UPDATE dbo.Comprobante
SET FlagEnviado=0, FechaHoraEnvio=NULL
WHERE Id IN (1,2,3);
*/