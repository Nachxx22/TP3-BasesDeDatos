/*
    Funcion: dbo.fnTextoComprobante
    Arma el texto del correo del comprobante de un movimiento: el mismo
    texto que armaba sp_AplicarMovimiento. Los montos salen con
    dbo.fnTextoMonto.
    @inMonto va con signo: negativo si el movimiento es un debito. Si
    @inMontoComision es mayor que 0, agrega el cargo por exceder el monto
    diario SINPE y el saldo final.
    Solo calcula: no lee ni escribe tablas y no abre transacciones.
    La usa dbo.sp_ProcesarCuentaDia.
    Orden de instalacion: despues de 13_Comprobantes.sql (fnTextoMonto) y
    antes de SPs/Sp_ProcesarCuentaDia.sql.
*/
USE CuentaAhorrosTP2;
GO

CREATE OR ALTER FUNCTION dbo.fnTextoComprobante (
    @inNombreDueno          VARCHAR(64),
    @inNumeroCuenta         VARCHAR(16),
    @inNombreTipoMovimiento VARCHAR(64),
    @inFecha                DATE,
    @inDescripcion          NVARCHAR(256),
    @inMonto                DECIMAL(18,2),
    @inNuevoSaldo           DECIMAL(18,2),
    @inMontoComision        DECIMAL(18,2),
    @inSaldoFinal           DECIMAL(18,2),
    @inSimbolo              NVARCHAR(4)
)
RETURNS NVARCHAR(2000)
AS
BEGIN
    DECLARE @saltoLinea NVARCHAR(2) = CHAR(13) + CHAR(10);

    RETURN N'Hola, ' + @inNombreDueno + N':' + @saltoLinea + @saltoLinea
        + N'Este es el comprobante de un movimiento en su cuenta de '
        + N'ahorros ' + @inNumeroCuenta + N'.' + @saltoLinea + @saltoLinea
        + N'Tipo de movimiento: ' + @inNombreTipoMovimiento + @saltoLinea
        + N'Fecha: ' + CONVERT(NVARCHAR(10), @inFecha, 23) + @saltoLinea
        + N'Detalle: ' + @inDescripcion + @saltoLinea
        + N'Monto: ' + dbo.fnTextoMonto(@inMonto, @inSimbolo) + @saltoLinea
        + N'Nuevo saldo: ' + dbo.fnTextoMonto(@inNuevoSaldo, @inSimbolo)
        + @saltoLinea
        + CASE
              WHEN @inMontoComision > 0
                  THEN N'Cargo por exceder el monto diario SINPE: '
                       + dbo.fnTextoMonto(-@inMontoComision, @inSimbolo)
                       + @saltoLinea
                       + N'Saldo final: '
                       + dbo.fnTextoMonto(@inSaldoFinal, @inSimbolo)
                       + @saltoLinea
              ELSE N''
          END
        + @saltoLinea
        + N'Correo enviado por el sistema del banco. '
        + N'No responda a este mensaje.';
END;
GO

-- Verificacion: un retiro SINPE que paso el maximo del dia (con comision).
-- El texto sale en la pestana Messages.
PRINT dbo.fnTextoComprobante('Ana Mora', '11000001', 'Retiro Sinpe',
    '2026-04-20', N'Pago de alquiler', -150000.00, 100000.00, 500.00,
    99500.00, N'$');
GO