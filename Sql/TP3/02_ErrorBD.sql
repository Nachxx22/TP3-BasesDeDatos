USE CuentaAhorrosTP2;
GO

/*
   02_ErrorBD
   Crea la tabla dbo.ErrorBD, donde los procedimientos almacenados guardan
   los errores de SQL que capturan en su bloque CATCH (cada uno hace su
   propio INSERT).

   Solo la crea si no existe, asi que se puede ejecutar varias veces.

   Orden de instalacion: despues de 01_ModeloFisicoFinanciero.sql y antes
   de los procedimientos almacenados.
*/

IF OBJECT_ID(N'dbo.ErrorBD', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ErrorBD (
        Id              INT IDENTITY(1,1) NOT NULL,
        FechaHora       DATETIME2(3)   NOT NULL CONSTRAINT DF_ErrorBD_Fecha DEFAULT (SYSDATETIME()),
        NumeroError     INT            NULL,
        Severidad       INT            NULL,
        Estado          INT            NULL,
        Procedimiento   NVARCHAR(128)  NULL,
        Linea           INT            NULL,
        Mensaje         NVARCHAR(4000) NOT NULL,
        CONSTRAINT PK_ErrorBD PRIMARY KEY (Id)
    );
END;
GO