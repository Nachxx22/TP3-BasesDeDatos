USE CuentaAhorrosTP2;
GO

/*
   Sp_ConsultarCatalogos.sql
   Listas que usa la pagina web en el formulario de beneficiarios:
     - sp_ListarParentezcos
     - sp_ListarTiposDocumento
*/

/*
   sp_ListarParentezcos
   Devuelve los parentescos (Id, Nombre) ordenados por Id.

   Salida  : @outResultCode
               0      = exito
               50000  = error inesperado (queda en dbo.ErrorBD)

   Ejemplo de ejecucion:
     DECLARE @outResultCode INT;
     EXEC dbo.sp_ListarParentezcos
         @outResultCode = @outResultCode OUTPUT;
     SELECT @outResultCode AS CodigoResultado;
*/

CREATE OR ALTER PROCEDURE dbo.sp_ListarParentezcos
    @outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Consulta los parentescos disponibles
        SELECT Id,
               Nombre
        FROM dbo.Parentezco
        ORDER BY Id;

        SET @outResultCode = 0;
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.ErrorBD (
            NumeroError, Severidad, Estado, Procedimiento, Linea, Mensaje
        )
        VALUES (
            ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE()
        );

        SET @outResultCode = 50000;
    END CATCH;
END;
GO

/*
   sp_ListarTiposDocumento
   Devuelve los tipos de documento de identidad (Id, Nombre) ordenados por Id.

   Salida  : @outResultCode
               0      = exito
               50000  = error inesperado (queda en dbo.ErrorBD)

   Ejemplo de ejecucion:
     DECLARE @outResultCode INT;
     EXEC dbo.sp_ListarTiposDocumento
         @outResultCode = @outResultCode OUTPUT;
     SELECT @outResultCode AS CodigoResultado;
*/

CREATE OR ALTER PROCEDURE dbo.sp_ListarTiposDocumento
    @outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Consulta los tipos de documento disponibles
        SELECT Id,
               Nombre
        FROM dbo.TipoDocuIdentidad
        ORDER BY Id;

        SET @outResultCode = 0;
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.ErrorBD (
            NumeroError, Severidad, Estado, Procedimiento, Linea, Mensaje
        )
        VALUES (
            ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE()
        );

        SET @outResultCode = 50000;
    END CATCH;
END;
GO