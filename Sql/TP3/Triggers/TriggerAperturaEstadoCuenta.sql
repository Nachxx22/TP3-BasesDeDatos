USE CuentaAhorrosTP2;
GO

/*
   Cuando se inserta una cuenta, abre su primer estado de cuenta: empieza en
   la fecha de creacion, termina un mes despues, sus saldos son el saldo de
   la cuenta (0) y todos sus contadores empiezan en 0.
   Funciona con varias cuentas en un mismo INSERT (usa la tabla inserted).

   Se puede ejecutar varias veces: si el trigger ya existe, lo reemplaza.
*/

CREATE OR ALTER TRIGGER dbo.tr_Cuenta_AperturaEstadoCuenta
ON dbo.Cuenta
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Primer estado de cuenta de cada cuenta insertada.
    INSERT INTO dbo.EstadoCuenta (
        IdCuenta
        , FechaInicio
        , FechaFin
        , SaldoInicial
        , SaldoMinimo
        , SaldoFinal
        , InteresesAcumulados
        , CantRetiros
        , CantDepositos
        , CantSinpeEntrantes
        , CantSinpeSalientes
        , CantOperacionesATM
        , CantRetirosATM
        , CantOperacionesHumano
        , CantRetirosHumano
    )
    SELECT
        i.Id
        , i.FechaCreacion
        , DATEADD(MONTH, 1, i.FechaCreacion)
        , i.Saldo
        , i.Saldo
        , i.Saldo
        , 0
        , 0
        , 0
        , 0
        , 0
        , 0
        , 0
        , 0
        , 0
    FROM inserted AS i;
END;
GO