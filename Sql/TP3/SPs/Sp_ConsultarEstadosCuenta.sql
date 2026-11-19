USE CuentaAhorrosTP2;
GO

/*
   sp_ConsultarEstadosCuenta
   Devuelve los estados de cuenta de una cuenta, del mas reciente al mas
   antiguo, con sus fechas, saldos (inicial, final y minimo), intereses,
   contadores (ATM, cajero humano y SINPE) y la moneda de la cuenta.
   Registra la consulta en la bitacora (tipo de operacion 7).

   Permisos: un cliente solo puede ver las cuentas que aparecen en
   UsuarioPuedeVer; el administrador puede ver cualquiera.

   Entrada : @inIdUsuario      usuario que consulta
             @inNumeroCuenta   numero de la cuenta
   Salida  : @outResultCode
               0      = exito
               50002  = parametros invalidos, usuario o cuenta inexistente
                        o usuario sin acceso a la cuenta
               50000  = error inesperado (queda en dbo.ErrorBD)
               otro   = codigo de error de sp_RegistrarBitacora

   Ejemplo de ejecucion:
     DECLARE @r INT;
     EXEC dbo.sp_ConsultarEstadosCuenta
         @inIdUsuario = 1,
         @inNumeroCuenta = '11000001',
         @outResultCode = @r OUTPUT;
     SELECT @r AS CodigoResultado;
*/

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarEstadosCuenta
    @inIdUsuario INT,
    @inNumeroCuenta VARCHAR(16),
    @outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCuenta INT;
    DECLARE @flagEsAdministrador BIT;
    DECLARE @codigoBitacora INT;

    SET @outResultCode = 0;

    -- Valida parametros
    IF @inIdUsuario IS NULL
       OR @inNumeroCuenta IS NULL
       OR LTRIM(RTRIM(@inNumeroCuenta)) = ''
    BEGIN
        SET @outResultCode = 50002;
        RETURN;
    END;

    BEGIN TRY

        -- Identifica usuario
        SELECT
            @flagEsAdministrador = EsAdministrador
        FROM dbo.Usuario
        WHERE Id = @inIdUsuario;

        -- Identifica cuenta
        SELECT
            @idCuenta = Id
        FROM dbo.Cuenta
        WHERE NumeroCuenta = @inNumeroCuenta;

        IF @flagEsAdministrador IS NULL
           OR @idCuenta IS NULL
        BEGIN
            SET @outResultCode = 50002;
            RETURN;
        END;

        -- Admin cualquier cuenta y cliente solo cuentas autorizadas
        IF @flagEsAdministrador = 0
           AND NOT EXISTS (
               SELECT 1
               FROM dbo.UsuarioPuedeVer
               WHERE IdUsuario = @inIdUsuario
                 AND IdCuenta = @idCuenta
           )
        BEGIN
            SET @outResultCode = 50002;
            RETURN;
        END;

        -- Registra la consulta en la bitacora (tipo 7). No abre transaccion.
        EXEC dbo.sp_RegistrarBitacora
            @inIdUsuario = @inIdUsuario,
            @inIdTipoOperacion = 7,
            @inIP = NULL,
            @inJsonAntes = NULL,
            @inJsonDespues = NULL,
            @outResultCode = @codigoBitacora OUTPUT;

        IF @codigoBitacora IS NULL
           OR @codigoBitacora <> 0
        BEGIN
            SET @outResultCode = ISNULL(@codigoBitacora, 50000);
            RETURN;
        END;

        -- Estados del mas reciente al mas antiguo.
        SELECT
            E.Id AS IdEstadoCuenta,
            E.FechaInicio,
            E.FechaFin,
            DATEADD(DAY, 1, E.FechaFin) AS FechaEmision,
            E.SaldoInicial,
            E.SaldoFinal,
            E.SaldoMinimo,
            E.InteresesAcumulados,
            E.CantRetiros,
            E.CantDepositos,
            E.CantSinpeEntrantes,
            E.CantSinpeSalientes,

            -- Contadores de la TP3
            E.CantOperacionesATM,
            E.CantRetirosATM,
            E.CantOperacionesHumano,
            E.CantRetirosHumano,

            -- Total de operaciones SINPE
            E.CantSinpeEntrantes + E.CantSinpeSalientes
                AS CantOperacionesSinpe,

            -- Moneda de la cuenta
            TM.Simbolo AS SimboloMoneda,
            TM.Nombre  AS NombreMoneda

        FROM dbo.EstadoCuenta AS E
        -- Cuenta y tipo de cuenta para llegar a la moneda
        INNER JOIN dbo.Cuenta AS C ON C.Id = E.IdCuenta
        INNER JOIN dbo.TipoCuentaAhorro AS TC ON TC.Id = C.IdTipoCuentaAhorro
        INNER JOIN dbo.TipoMoneda AS TM ON TM.Id = TC.IdTipoMoneda
        WHERE E.IdCuenta = @idCuenta
        ORDER BY E.FechaFin DESC, E.Id DESC;

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