USE CuentaAhorrosTP2;
GO

/*
   sp_RegistrarBitacora
   Registra una operacion en dbo.Bitacora: usuario, tipo de operacion, IP y
   los datos antes y despues del cambio (JSON). La usan los SP de sesion,
   de beneficiarios y de consulta de estados de cuenta y movimientos.

   Antes de insertar revisa que:
     - el usuario y el tipo de operacion existan;
     - el login (tipo 1) traiga la IP;
     - agregar beneficiario (tipo 3) traiga el JSON de despues;
     - actualizar y eliminar (tipos 4, 5 y 6) traigan los dos JSON;
     - los JSON que vengan tengan formato valido.

   Entrada : @inIdUsuario, @inIdTipoOperacion, @inIP (opcional),
             @inJsonAntes (opcional), @inJsonDespues (opcional)
   Salida  : @outResultCode
               0      = exito
               50007  = usuario inexistente o datos incompletos o invalidos
               50008  = tipo de operacion inexistente
               50000  = error inesperado (queda en dbo.ErrorBD)

   Ejemplo de ejecucion:
     DECLARE @outResultCode INT;
     EXEC dbo.sp_RegistrarBitacora
         @inIdUsuario = 1,
         @inIdTipoOperacion = 1,
         @inIP = '127.0.0.1',
         @outResultCode = @outResultCode OUTPUT;
     SELECT @outResultCode AS CodigoResultado;
*/

CREATE OR ALTER PROCEDURE dbo.sp_RegistrarBitacora
    @inIdUsuario INT,
    @inIdTipoOperacion INT,
    @inIP VARCHAR(45) = NULL,
    @inJsonAntes NVARCHAR(MAX) = NULL,
    @inJsonDespues NVARCHAR(MAX) = NULL,
    @outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- ver si existe el usuario
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuario
        WHERE Id = @inIdUsuario
    )
    BEGIN
        SET @outResultCode = 50007;
        RETURN;
    END;

    -- ver el tipo de operacion
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.TipoOperacionBitacora
        WHERE Id = @inIdTipoOperacion
    )
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    -- El login debe registrar una IP
    IF @inIdTipoOperacion = 1
       AND (@inIP IS NULL OR LTRIM(RTRIM(@inIP)) = '')
    BEGIN
        SET @outResultCode = 50007;
        RETURN;
    END;

    -- Agregar beneficiario requiere datos despues
    IF @inIdTipoOperacion = 3
       AND @inJsonDespues IS NULL
    BEGIN
        SET @outResultCode = 50007;
        RETURN;
    END;

    -- Actualizar y eliminar requieren los dos estados
    IF @inIdTipoOperacion IN (4, 5, 6)
       AND (@inJsonAntes IS NULL OR @inJsonDespues IS NULL)
    BEGIN
        SET @outResultCode = 50007;
        RETURN;
    END;

    -- Valida el formato de los JSON
    IF ((@inJsonAntes IS NOT NULL
         AND ISJSON(@inJsonAntes) <> 1)
        OR (@inJsonDespues IS NOT NULL
            AND ISJSON(@inJsonDespues) <> 1))
    BEGIN
        SET @outResultCode = 50007;
        RETURN;
    END;

    BEGIN TRY
        INSERT INTO dbo.Bitacora (
            IdUsuario,
            IdTipoOperacion,
            IP,
            JsonAntes,
            JsonDespues
        )
        VALUES (
            @inIdUsuario,
            @inIdTipoOperacion,
            @inIP,
            @inJsonAntes,
            @inJsonDespues
        );

        SET @outResultCode = 0;
    END TRY
    BEGIN CATCH
        -- Si quien la llama tiene una transaccion abierta y la deshace, este
        -- registro en ErrorBD tambien se deshace.
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