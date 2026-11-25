/*
   Prueba de dbo.sp_ProcesarCuentaDia: lo de una cuenta en una fecha, en
   UNA sola transaccion. Todo termina en ROLLBACK: no deja nada en la base.

   Usa la cuenta 11000001 y el dia en que vence su estado de cuenta actual
   (con la simulacion completa es el 2026-07-01, despues del XML), para que
   la cuenta tenga movimientos Y cierre el mismo dia.
     Prueba 1. Todo o nada: un retiro deja la cuenta sin saldo para los
               cargos del cierre. El cierre no se puede hacer (50307) y por
               eso tampoco se aplica el retiro.
     Prueba 2. Dia normal: 4 movimientos (se aplican 2; se rechazan 2: uno
               por saldo insuficiente y otro por tipo invalido) y el cierre.
     Prueba 3. Reanudacion: llamarlo otra vez no hace nada.
     Prueba 4. Un movimiento nuevo en un periodo ya cerrado: 50303.
     Prueba 5. Movimiento de una cuenta que no existe: se rechaza (50202),
               como antes.
   Al final sale una tabla con Esperado, Obtenido y Resultado (OK/ERROR).

   La prueba abre una transaccion SOLO para poder deshacer todo al final
   (como Pruebas_AltasDia.sql). En el sistema nadie llama al SP dentro de
   una transaccion: la simulacion no abre transacciones.

   Requiere: 14_MovimientoXml.sql, las dos funciones de Funciones/ y
   SPs/Sp_ProcesarCuentaDia.sql instalados, y la simulacion ya corrida
   (para que exista la cuenta).
   El ROLLBACK deja saltos en los Id de Comprobante y Movimiento: es normal
   en SQL Server.
*/
USE CuentaAhorrosTP2;
GO

DECLARE @true  BIT = 1;
DECLARE @false BIT = 0;
DECLARE @numeroCuenta VARCHAR(16) = '11000001';
DECLARE @cuentaInexistente VARCHAR(16) = '99999999';
DECLARE @idCuenta INT;
DECLARE @fechaCreacion DATE;
DECLARE @fecha DATE;
DECLARE @fechaTexto VARCHAR(10);
DECLARE @mesSiguiente DATE;
DECLARE @fechaFinEsperada DATE;
DECLARE @referenciaCierre VARCHAR(128);
DECLARE @ref1 VARCHAR(128);
DECLARE @ref2 VARCHAR(128);
DECLARE @ref3 VARCHAR(128);
DECLARE @ref4 VARCHAR(128);
DECLARE @idEstado INT;
DECLARE @base INT;
DECLARE @saldoAntes DECIMAL(18,2);
DECLARE @depositosAntes INT;
DECLARE @retirosAntes INT;
DECLARE @operacionesATMAntes INT;
DECLARE @retirosATMAntes INT;
DECLARE @operacionesHumanoAntes INT;
DECLARE @retirosHumanoAntes INT;
DECLARE @movimientosAntes INT;
DECLARE @estadosAntes INT;
DECLARE @comprobantesAntes INT;
DECLARE @errorBDAntes INT;
DECLARE @movimientosDespues INT;
DECLARE @saldoCuenta DECIMAL(18,2);
DECLARE @saldoFinalCerrado DECIMAL(18,2);
DECLARE @saldoInicialNuevo DECIMAL(18,2);
DECLARE @saldoUltimoMovimiento DECIMAL(18,2);
DECLARE @fechaInicioNueva DATE;
DECLARE @fechaFinNueva DATE;
DECLARE @codigo INT;
DECLARE @aplicados INT;
DECLARE @rechazados INT;
DECLARE @idNuevoEstado INT;
DECLARE @flagSigue BIT = 1;
DECLARE @resultados TABLE (
    Id       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Prueba   NVARCHAR(120) NOT NULL,
    Esperado NVARCHAR(60)  NOT NULL,
    Obtenido NVARCHAR(60)  NULL
);

SELECT
    @idCuenta = C.Id,
    @fechaCreacion = C.FechaCreacion,
    @saldoAntes = C.Saldo
FROM dbo.Cuenta AS C
WHERE C.NumeroCuenta = @numeroCuenta;

IF @idCuenta IS NULL
BEGIN
    PRINT 'No existe la cuenta ' + @numeroCuenta
        + ': corra primero la simulacion.';
    RETURN;
END;

-- Su estado de cuenta actual (el ultimo) y el dia en que vence
SELECT @fecha = MAX(E.FechaFin)
FROM dbo.EstadoCuenta AS E
WHERE E.IdCuenta = @idCuenta;

SELECT
    @idEstado = E.Id,
    @depositosAntes = E.CantDepositos,
    @retirosAntes = E.CantRetiros,
    @operacionesATMAntes = E.CantOperacionesATM,
    @retirosATMAntes = E.CantRetirosATM,
    @operacionesHumanoAntes = E.CantOperacionesHumano,
    @retirosHumanoAntes = E.CantRetirosHumano
FROM dbo.EstadoCuenta AS E
WHERE E.IdCuenta = @idCuenta
  AND E.FechaFin = @fecha;

SET @fechaTexto = CONVERT(VARCHAR(10), @fecha, 23);
SET @referenciaCierre = 'CIERRE:' + @numeroCuenta + ':'
                      + CONVERT(CHAR(8), @fecha, 112);

-- El estado nuevo debe vencer el dia de creacion del mes siguiente
SET @mesSiguiente = DATEADD(MONTH, 1, @fecha);

IF DAY(@fechaCreacion) > DAY(EOMONTH(@mesSiguiente))
    SET @fechaFinEsperada = EOMONTH(@mesSiguiente);
ELSE
    SET @fechaFinEsperada = DATEFROMPARTS(YEAR(@mesSiguiente),
                                          MONTH(@mesSiguiente),
                                          DAY(@fechaCreacion));

-- Secuencias libres para ese dia en MovimientoXml
SELECT @base = ISNULL(MAX(MX.Secuencia), 0)
FROM dbo.MovimientoXml AS MX
WHERE MX.FechaOperacion = @fecha;

SET @ref1 = @fechaTexto + '#' + CAST(@base + 1 AS VARCHAR(10));
SET @ref2 = @fechaTexto + '#' + CAST(@base + 2 AS VARCHAR(10));
SET @ref3 = @fechaTexto + '#' + CAST(@base + 3 AS VARCHAR(10));
SET @ref4 = @fechaTexto + '#' + CAST(@base + 4 AS VARCHAR(10));

SELECT @movimientosAntes = COUNT(*) FROM dbo.Movimiento;
SELECT @estadosAntes = COUNT(*) FROM dbo.EstadoCuenta;
SELECT @comprobantesAntes = COUNT(*) FROM dbo.Comprobante;
SELECT @errorBDAntes = COUNT(*) FROM dbo.ErrorBD;

PRINT 'Cuenta ' + @numeroCuenta + ', fecha de prueba ' + @fechaTexto;

BEGIN TRANSACTION;

-------------------------------------------------------------------------
-- Prueba 1. Todo o nada: el retiro deja 100 y el cierre no alcanza
-------------------------------------------------------------------------
INSERT INTO dbo.MovimientoXml (
    FechaOperacion, Secuencia, NumeroCuenta, TipoMovimiento, Monto,
    Descripcion
)
VALUES (
    @fecha, @base + 1, @numeroCuenta, 'Retiro Ventana', @saldoAntes - 100,
    N'Prueba 1: deja la cuenta sin saldo para el cierre'
);

EXEC dbo.sp_ProcesarCuentaDia
    @inNumeroCuenta = @numeroCuenta,
    @inFechaOperacion = @fecha,
    @outResultCode = @codigo OUTPUT,
    @outCantAplicados = @aplicados OUTPUT,
    @outCantRechazados = @rechazados OUTPUT,
    @outIdNuevoEstadoCuenta = @idNuevoEstado OUTPUT;

IF @@TRANCOUNT = 0
    SET @flagSigue = @false;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
VALUES (N'1. Codigo: el saldo no alcanza para el cierre', N'50307',
        CAST(@codigo AS NVARCHAR(60)));

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'1. El retiro sigue pendiente (FlagProcesado)', N'0',
       CAST(MX.FlagProcesado AS NVARCHAR(60))
FROM dbo.MovimientoXml AS MX
WHERE MX.FechaOperacion = @fecha
  AND MX.Secuencia = @base + 1;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'1. Saldo de la cuenta', CAST(@saldoAntes AS NVARCHAR(60)),
       CAST(C.Saldo AS NVARCHAR(60))
FROM dbo.Cuenta AS C
WHERE C.Id = @idCuenta;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'1. Movimientos nuevos', N'0',
       CAST(COUNT(*) - @movimientosAntes AS NVARCHAR(60))
FROM dbo.Movimiento;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'1. Estados de cuenta nuevos', N'0',
       CAST(COUNT(*) - @estadosAntes AS NVARCHAR(60))
FROM dbo.EstadoCuenta;

-------------------------------------------------------------------------
-- Prueba 2. Dia normal: 4 movimientos y el cierre
--   1 deposito en ventanilla de 50 000   -> se aplica
--   2 retiro en ventanilla sin saldo     -> rechazado 50206
--   3 retiro en ATM de 1 000             -> se aplica
--   4 tipo que no existe                 -> rechazado 50201
-------------------------------------------------------------------------
IF @flagSigue = @true
BEGIN
    DELETE FROM dbo.MovimientoXml
    WHERE FechaOperacion = @fecha
      AND Secuencia = @base + 1;

    INSERT INTO dbo.MovimientoXml (
        FechaOperacion, Secuencia, NumeroCuenta, TipoMovimiento, Monto,
        Descripcion
    )
    VALUES
        (@fecha, @base + 1, @numeroCuenta, 'Deposito Ventana', 50000,
         N'Prueba 2: deposito'),
        (@fecha, @base + 2, @numeroCuenta, 'Retiro Ventana',
         @saldoAntes + 51000, N'Prueba 2: retiro sin saldo'),
        (@fecha, @base + 3, @numeroCuenta, 'Retiro ATM', 1000,
         N'Prueba 2: retiro ATM'),
        (@fecha, @base + 4, @numeroCuenta, 'Transferencia', 500,
         N'Prueba 2: tipo invalido');

    EXEC dbo.sp_ProcesarCuentaDia
        @inNumeroCuenta = @numeroCuenta,
        @inFechaOperacion = @fecha,
        @outResultCode = @codigo OUTPUT,
        @outCantAplicados = @aplicados OUTPUT,
        @outCantRechazados = @rechazados OUTPUT,
        @outIdNuevoEstadoCuenta = @idNuevoEstado OUTPUT;

    IF @@TRANCOUNT = 0
        SET @flagSigue = @false;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES
        (N'2. Codigo', N'0', CAST(@codigo AS NVARCHAR(60))),
        (N'2. Movimientos aplicados', N'2',
         CAST(@aplicados AS NVARCHAR(60))),
        (N'2. Movimientos rechazados', N'2',
         CAST(@rechazados AS NVARCHAR(60))),
        (N'2. Hizo el cierre (devolvio el Id del estado nuevo)', N'Si',
         CASE WHEN @idNuevoEstado IS NULL THEN N'No' ELSE N'Si' END);

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Codigo en MovimientoXml del movimiento '
           + CAST(MX.Secuencia - @base AS NVARCHAR(10)),
           CASE MX.Secuencia - @base
               WHEN 1 THEN N'0'
               WHEN 2 THEN N'50206'
               WHEN 3 THEN N'0'
               ELSE N'50201'
           END,
           CAST(MX.CodigoResultado AS NVARCHAR(60))
    FROM dbo.MovimientoXml AS MX
    WHERE MX.FechaOperacion = @fecha
      AND MX.Secuencia BETWEEN @base + 1 AND @base + 4
    ORDER BY MX.Secuencia;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Movimientos del XML registrados (el 1 y el 3)', N'2',
           CAST(COUNT(*) AS NVARCHAR(60))
    FROM dbo.Movimiento AS MV
    WHERE MV.ReferenciaOrigen IN (@ref1, @ref3);

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Movimientos rechazados registrados (el 2 y el 4)', N'0',
           CAST(COUNT(*) AS NVARCHAR(60))
    FROM dbo.Movimiento AS MV
    WHERE MV.ReferenciaOrigen IN (@ref2, @ref4);

    -- Cada movimiento quedo con SU comprobante (vinculacion masiva)
    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Movimientos con su propio comprobante', N'2',
           CAST(COUNT(*) AS NVARCHAR(60))
    FROM dbo.Movimiento AS MV
    INNER JOIN dbo.Comprobante AS CO
        ON CO.Id = MV.IdComprobante
    INNER JOIN dbo.TipoMovimiento AS TM
        ON TM.Id = MV.IdTipoMovimiento
    WHERE MV.ReferenciaOrigen IN (@ref1, @ref3)
      AND CO.IdCuenta = @idCuenta
      AND CO.Asunto = TM.Nombre + N' en la cuenta ' + @numeroCuenta;

    -- El texto del correo lo arma dbo.fnTextoComprobante
    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Texto del comprobante del deposito', N'Si',
           CASE
               WHEN CO.TextoEmail LIKE N'Hola, %'
                AND CO.TextoEmail LIKE N'%Tipo de movimiento: Deposito%'
                AND CO.TextoEmail LIKE N'%Detalle: Prueba 2: deposito%'
                AND CO.TextoEmail LIKE N'%Nuevo saldo: %'
                AND CO.TextoEmail LIKE N'%No responda a este mensaje.'
                   THEN N'Si'
               ELSE N'No'
           END
    FROM dbo.Movimiento AS MV
    INNER JOIN dbo.Comprobante AS CO
        ON CO.Id = MV.IdComprobante
    WHERE MV.ReferenciaOrigen = @ref1;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Comprobantes nuevos', N'2',
           CAST(COUNT(*) - @comprobantesAntes AS NVARCHAR(60))
    FROM dbo.Comprobante;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Saldo despues del retiro ATM',
           CAST(@saldoAntes + 49000 AS NVARCHAR(60)),
           CAST(MV.SaldoPosterior AS NVARCHAR(60))
    FROM dbo.Movimiento AS MV
    WHERE MV.ReferenciaOrigen = @ref3
      AND MV.SecuenciaOrigen = 1;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Contadores (dep, ret, opATM, retATM, opVent, retVent)',
           N'1,1,1,1,1,0',
           CAST(E.CantDepositos - @depositosAntes AS NVARCHAR(10)) + N','
           + CAST(E.CantRetiros - @retirosAntes AS NVARCHAR(10)) + N','
           + CAST(E.CantOperacionesATM - @operacionesATMAntes
                  AS NVARCHAR(10)) + N','
           + CAST(E.CantRetirosATM - @retirosATMAntes AS NVARCHAR(10))
           + N','
           + CAST(E.CantOperacionesHumano - @operacionesHumanoAntes
                  AS NVARCHAR(10)) + N','
           + CAST(E.CantRetirosHumano - @retirosHumanoAntes
                  AS NVARCHAR(10))
    FROM dbo.EstadoCuenta AS E
    WHERE E.Id = @idEstado;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'2. Cargo mensual del cierre registrado', N'1',
           CAST(COUNT(*) AS NVARCHAR(60))
    FROM dbo.Movimiento AS MV
    WHERE MV.ReferenciaOrigen = @referenciaCierre
      AND MV.IdTipoMovimiento = 11;

    -- Estado nuevo y cadena de saldos
    SELECT @saldoCuenta = C.Saldo
    FROM dbo.Cuenta AS C
    WHERE C.Id = @idCuenta;

    SELECT @saldoFinalCerrado = E.SaldoFinal
    FROM dbo.EstadoCuenta AS E
    WHERE E.Id = @idEstado;

    SELECT
        @saldoInicialNuevo = E.SaldoInicial,
        @fechaInicioNueva = E.FechaInicio,
        @fechaFinNueva = E.FechaFin
    FROM dbo.EstadoCuenta AS E
    WHERE E.Id = @idNuevoEstado;

    SELECT @saldoUltimoMovimiento = MV.SaldoPosterior
    FROM dbo.Movimiento AS MV
    WHERE MV.Id = (SELECT MAX(M2.Id)
                   FROM dbo.Movimiento AS M2
                   WHERE M2.IdEstadoCuenta = @idEstado);

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES
        (N'2. Periodo del estado nuevo',
         CONVERT(NVARCHAR(10), DATEADD(DAY, 1, @fecha), 23) + N' a '
         + CONVERT(NVARCHAR(10), @fechaFinEsperada, 23),
         CONVERT(NVARCHAR(10), @fechaInicioNueva, 23) + N' a '
         + CONVERT(NVARCHAR(10), @fechaFinNueva, 23)),
        (N'2. Saldo cuenta = final del cerrado = inicial del nuevo '
         + N'= ultimo movimiento', N'Si',
         CASE
             WHEN @saldoCuenta = @saldoFinalCerrado
              AND @saldoCuenta = @saldoInicialNuevo
              AND @saldoCuenta = @saldoUltimoMovimiento
                 THEN N'Si'
             ELSE N'No'
         END);

    SELECT @movimientosDespues = COUNT(*) FROM dbo.Movimiento;
END;

-------------------------------------------------------------------------
-- Prueba 3. Reanudacion: la misma cuenta y fecha otra vez no hace nada
-------------------------------------------------------------------------
IF @flagSigue = @true
BEGIN
    EXEC dbo.sp_ProcesarCuentaDia
        @inNumeroCuenta = @numeroCuenta,
        @inFechaOperacion = @fecha,
        @outResultCode = @codigo OUTPUT,
        @outCantAplicados = @aplicados OUTPUT,
        @outCantRechazados = @rechazados OUTPUT,
        @outIdNuevoEstadoCuenta = @idNuevoEstado OUTPUT;

    IF @@TRANCOUNT = 0
        SET @flagSigue = @false;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES (N'3. Codigo, aplicados, rechazados, Id estado nuevo',
            N'0,0,0,NULL',
            CAST(@codigo AS NVARCHAR(10)) + N','
            + CAST(@aplicados AS NVARCHAR(10)) + N','
            + CAST(@rechazados AS NVARCHAR(10)) + N','
            + ISNULL(CAST(@idNuevoEstado AS NVARCHAR(10)), N'NULL'));

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'3. Movimientos nuevos', N'0',
           CAST(COUNT(*) - @movimientosDespues AS NVARCHAR(60))
    FROM dbo.Movimiento;
END;

-------------------------------------------------------------------------
-- Prueba 4. Movimiento nuevo en un periodo que ya se cerro: 50303
-------------------------------------------------------------------------
IF @flagSigue = @true
BEGIN
    INSERT INTO dbo.MovimientoXml (
        FechaOperacion, Secuencia, NumeroCuenta, TipoMovimiento, Monto,
        Descripcion
    )
    VALUES (
        @fecha, @base + 5, @numeroCuenta, 'Deposito ATM', 1000,
        N'Prueba 4: periodo cerrado'
    );

    EXEC dbo.sp_ProcesarCuentaDia
        @inNumeroCuenta = @numeroCuenta,
        @inFechaOperacion = @fecha,
        @outResultCode = @codigo OUTPUT,
        @outCantAplicados = @aplicados OUTPUT,
        @outCantRechazados = @rechazados OUTPUT,
        @outIdNuevoEstadoCuenta = @idNuevoEstado OUTPUT;

    IF @@TRANCOUNT = 0
        SET @flagSigue = @false;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES (N'4. Codigo: periodo ya cerrado', N'50303',
            CAST(@codigo AS NVARCHAR(60)));

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'4. El movimiento sigue pendiente (FlagProcesado)', N'0',
           CAST(MX.FlagProcesado AS NVARCHAR(60))
    FROM dbo.MovimientoXml AS MX
    WHERE MX.FechaOperacion = @fecha
      AND MX.Secuencia = @base + 5;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'4. Movimientos nuevos', N'0',
           CAST(COUNT(*) - @movimientosDespues AS NVARCHAR(60))
    FROM dbo.Movimiento;
END;

-------------------------------------------------------------------------
-- Prueba 5. Movimiento de una cuenta que no existe: rechazado (50202)
-------------------------------------------------------------------------
IF @flagSigue = @true
BEGIN
    INSERT INTO dbo.MovimientoXml (
        FechaOperacion, Secuencia, NumeroCuenta, TipoMovimiento, Monto,
        Descripcion
    )
    VALUES (
        @fecha, @base + 6, @cuentaInexistente, 'Deposito Ventana', 1000,
        N'Prueba 5: cuenta que no existe'
    );

    EXEC dbo.sp_ProcesarCuentaDia
        @inNumeroCuenta = @cuentaInexistente,
        @inFechaOperacion = @fecha,
        @outResultCode = @codigo OUTPUT,
        @outCantAplicados = @aplicados OUTPUT,
        @outCantRechazados = @rechazados OUTPUT,
        @outIdNuevoEstadoCuenta = @idNuevoEstado OUTPUT;

    IF @@TRANCOUNT = 0
        SET @flagSigue = @false;

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES (N'5. Codigo, aplicados, rechazados', N'0,0,1',
            CAST(@codigo AS NVARCHAR(10)) + N','
            + CAST(@aplicados AS NVARCHAR(10)) + N','
            + CAST(@rechazados AS NVARCHAR(10)));

    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    SELECT N'5. Codigo en MovimientoXml', N'50202',
           CAST(MX.CodigoResultado AS NVARCHAR(60))
    FROM dbo.MovimientoXml AS MX
    WHERE MX.FechaOperacion = @fecha
      AND MX.Secuencia = @base + 6;
END;

IF @flagSigue = @false
BEGIN
    INSERT INTO @resultados (Prueba, Esperado, Obtenido)
    VALUES (N'El SP fallo con un error de SQL (ver dbo.ErrorBD)', N'-',
            N'fallo');
END;

-- Deshace todo lo de la prueba
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
END;

-------------------------------------------------------------------------
-- Despues del ROLLBACK no queda nada
-------------------------------------------------------------------------
INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Filas de prueba en MovimientoXml', N'0',
       CAST(COUNT(*) AS NVARCHAR(60))
FROM dbo.MovimientoXml AS MX
WHERE MX.FechaOperacion = @fecha
  AND MX.Secuencia > @base;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Movimientos nuevos', N'0',
       CAST(COUNT(*) - @movimientosAntes AS NVARCHAR(60))
FROM dbo.Movimiento;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Estados de cuenta nuevos', N'0',
       CAST(COUNT(*) - @estadosAntes AS NVARCHAR(60))
FROM dbo.EstadoCuenta;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Comprobantes nuevos', N'0',
       CAST(COUNT(*) - @comprobantesAntes AS NVARCHAR(60))
FROM dbo.Comprobante;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Saldo de la cuenta', CAST(@saldoAntes AS NVARCHAR(60)),
       CAST(C.Saldo AS NVARCHAR(60))
FROM dbo.Cuenta AS C
WHERE C.Id = @idCuenta;

INSERT INTO @resultados (Prueba, Esperado, Obtenido)
SELECT N'Fin. Errores nuevos en ErrorBD', N'0',
       CAST(COUNT(*) - @errorBDAntes AS NVARCHAR(60))
FROM dbo.ErrorBD;

SELECT
    R.Prueba,
    R.Esperado,
    R.Obtenido,
    CASE
        WHEN R.Obtenido = R.Esperado THEN 'OK'
        ELSE 'ERROR'
    END AS Resultado
FROM @resultados AS R
ORDER BY R.Id;
GO