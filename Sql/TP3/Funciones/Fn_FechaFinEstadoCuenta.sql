/*
    Funcion: dbo.fnFechaFinEstadoCuenta
    Fecha en que vence el estado de cuenta que se abre despues de un
    cierre: el mismo dia del mes en que se creo la cuenta, en el mes
    siguiente al cierre. Si ese mes es mas corto, el ultimo dia del mes.
    Es la misma regla que tenia sp_CerrarYAbrirEstadoCuenta.
    Solo calcula: no lee ni escribe tablas y no abre transacciones.
    La usa dbo.sp_ProcesarCuentaDia.
    Ejemplos (cuenta creada un dia 31):
        SELECT dbo.fnFechaFinEstadoCuenta('2026-03-31', '2026-04-30');
        -- 2026-05-31
        SELECT dbo.fnFechaFinEstadoCuenta('2026-03-31', '2026-05-31');
        -- 2026-06-30 (junio no tiene 31)
    Orden de instalacion: antes de SPs/Sp_ProcesarCuentaDia.sql.
*/
USE CuentaAhorrosTP2;
GO

CREATE OR ALTER FUNCTION dbo.fnFechaFinEstadoCuenta (
    @inFechaCreacion DATE,
    @inFechaCierre   DATE
)
RETURNS DATE
AS
BEGIN
    DECLARE @mesSiguiente DATE = DATEADD(MONTH, 1, @inFechaCierre);

    IF (DAY(@inFechaCreacion) > DAY(EOMONTH(@mesSiguiente)))
    BEGIN
        RETURN EOMONTH(@mesSiguiente);
    END;

    RETURN DATEFROMPARTS(YEAR(@mesSiguiente), MONTH(@mesSiguiente),
                         DAY(@inFechaCreacion));
END;
GO

-- Verificacion: deben salir 2026-05-31 y 2026-06-30
SELECT
    dbo.fnFechaFinEstadoCuenta('2026-03-31', '2026-04-30') AS Ejemplo1,
    dbo.fnFechaFinEstadoCuenta('2026-03-31', '2026-05-31') AS Ejemplo2;
GO