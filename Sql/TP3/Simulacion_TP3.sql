/*
   Lee el XML de operaciones desde su archivo (OperacionesTarea3.xml del
   profesor) y pasa todos sus movimientos, una sola vez, a la tabla variable
   @movimientosXml. Luego recorre TODAS las fechas del XML, una por una y en
   orden ascendente (aunque la fecha no tenga nodo FechaOperacion).
   Por cada dia:
      1. Altas:       EXEC dbo.sp_CargarAltasDia
                      (Persona -> Cuenta -> Beneficiario -> Usuario -> PuedeVer)
      2. Movimientos: los de esa fecha en @movimientosXml, uno por uno y en
                      el orden del XML, con EXEC dbo.sp_AplicarMovimiento
      3. Cierres:     cuentas cuyo estado vence ese dia, en orden de Id (PK),
                      con EXEC dbo.sp_CerrarYAbrirEstadoCuenta

   Control, con dbo.CorridaSimulacion y
   dbo.ControlSimulacion (12_ControlSimulacion.sql):
     - No se corre mas de una vez: una fecha terminada no se vuelve a
       procesar. Si todas estan terminadas, el script no hace nada.
     - No se brinca una fecha: empieza siempre por la fecha pendiente mas
       antigua, y antes de procesar una fecha revisa que la anterior este
       terminada.
     - Si falla sin terminar, la siguiente corrida reanuda esa fecha desde lo
       ultimo procesado: no repite las altas, sigue con el movimiento que
       sigue al ultimo procesado, y con la cuenta (PK) que sigue a la ultima
       cerrada.

   Si falla un alta o un cierre, la corrida SE DETIENE en esa fecha y deja el
   error en dbo.ErrorBD; se corrige la causa y se vuelve a correr (reanuda).
   Si un movimiento es rechazado (fondos insuficientes, etc.) se registra en
   dbo.ErrorBD y la simulacion continua con el siguiente.
*/
USE CuentaAhorrosTP2;
GO
SET NOCOUNT ON;

-- Constantes
DECLARE @true  BIT = 1;
DECLARE @false BIT = 0;
DECLARE @resultadoCompleta      INT = 0;
DECLARE @resultadoSinPendientes INT = 1;
DECLARE @resultadoError         INT = 2;
DECLARE @resultadoPrueba        INT = 3;
DECLARE @codigoMovYaRegistrado  INT = 50203;  -- de sp_AplicarMovimiento
DECLARE @codigoPeriodoCerrado   INT = 50303;  -- de sp_CerrarYAbrirEstadoCuenta

-- SOLO PARA LA PRUEBA DE REANUDACION (Pruebas/Prueba_ReanudarSimulacion.sql):
-- detienen la corrida a proposito, como si fallara. En una corrida normal
-- las tres quedan en NULL.
DECLARE @pruebaFechaDetener           DATE = Null;  -- ej. '2026-04-01'
DECLARE @pruebaDetenerTrasMovimientos INT  = Null;  -- ej. 3
DECLARE @pruebaDetenerTrasCierres     INT  = Null;  -- ej. 1

-- XML DE OPERACIONES: se lee del archivo del profesor (OperacionesTarea3.xml).
-- La ruta es de la computadora donde corre SQL Server. Para usar otra
-- ubicacion se cambia SOLO la ruta de OPENROWSET (tiene que ir escrita ahi).
-- SINGLE_BLOB lee el archivo tal cual, y al convertirlo a XML SQL Server
-- respeta su encoding="UTF-8" (las tildes y enes quedan bien).
DECLARE @xmlOperaciones XML;

-- TABLA DE MOVIMIENTOS: todos los movimientos del XML se leen UNA sola vez
-- con nodes() (SQL masivo). Despues cada fecha toma los suyos de aqui, sin
-- volver a recorrer el XML.
DECLARE @movimientosXml TABLE (
    FechaOperacion DATE          NOT NULL,
    Secuencia      INT           NOT NULL,  -- posicion dentro de su fecha
    NumeroCuenta   VARCHAR(16)   NOT NULL,
    TipoMovimiento VARCHAR(64)   NOT NULL,
    Monto          DECIMAL(18,2) NOT NULL,
    Descripcion    NVARCHAR(256) NOT NULL,
    PRIMARY KEY (FechaOperacion, Secuencia)
);

BEGIN TRY
    SELECT @xmlOperaciones = CAST(Archivo.BulkColumn AS XML)
    FROM OPENROWSET(
        BULK N'C:\Users\Nacho\Downloads\OperacionesTarea3.xml',
        SINGLE_BLOB
    ) AS Archivo;

    -- Secuencia = cuantos Movimientos hay antes de este en la misma fecha,
    -- mas 1. Conserva el orden del XML, que importa para el saldo y para la
    -- comision SINPE.
    INSERT INTO @movimientosXml (
        FechaOperacion,
        Secuencia,
        NumeroCuenta,
        TipoMovimiento,
        Monto,
        Descripcion
    )
    SELECT
        T.Nodo.value('(../@Fecha)[1]', 'DATE'),
        T.Nodo.value('let $m := . return count(../Movimientos[. << $m]) + 1',
                     'INT'),
        T.Nodo.value('@CodigoCuenta', 'VARCHAR(16)'),
        T.Nodo.value('@Tipo', 'VARCHAR(64)'),
        T.Nodo.value('@Monto', 'DECIMAL(18,2)'),
        T.Nodo.value('@Descripcion', 'NVARCHAR(256)')
    FROM @xmlOperaciones.nodes('/Operaciones/FechaOperacion/Movimientos')
        AS T(Nodo);
END TRY
BEGIN CATCH
    INSERT INTO dbo.ErrorBD (
        NumeroError, Severidad, Estado, Procedimiento, Linea, Mensaje
    )
    VALUES (
        ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
        N'Simulacion_TP3', ERROR_LINE(), ERROR_MESSAGE()
    );
    PRINT N'No se pudo leer el XML de operaciones: ' + ERROR_MESSAGE();
    RETURN;
END CATCH;

IF (@xmlOperaciones IS NULL
    OR @xmlOperaciones.exist('/Operaciones/FechaOperacion') = 0)
BEGIN
    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
    VALUES (50501, N'Simulacion_TP3',
            N'El XML de operaciones esta vacio o no trae fechas.');
    PRINT N'El XML de operaciones esta vacio o no trae fechas.';
    RETURN;
END;

-- Variables
DECLARE @idCorrida INT;
DECLARE @fechaInicio DATE;
DECLARE @fechaFin DATE;
DECLARE @fecha DATE;
DECLARE @fechaTexto VARCHAR(10);
DECLARE @flagDetener BIT = @false;
DECLARE @flagAltas BIT;
DECLARE @ultimoMov INT;
DECLARE @ultimaCuenta INT;
DECLARE @codigo INT;
DECLARE @codigoResultado INT = NULL;
DECLARE @idMovimiento INT;
DECLARE @idEstadoNuevo INT;
DECLARE @i INT;
DECLARE @cantMov INT;
DECLARE @idCuenta INT;
DECLARE @cierresHoy INT;
DECLARE @numeroCuenta VARCHAR(16);
DECLARE @tipoMov VARCHAR(64);
DECLARE @monto DECIMAL(18,2);
DECLARE @descripcion NVARCHAR(256);
DECLARE @referencia VARCHAR(128);
DECLARE @mensaje NVARCHAR(256);
DECLARE @movOk INT = 0;
DECLARE @movRechazados INT = 0;
DECLARE @cierresOk INT = 0;
DECLARE @fechasTerminadas INT = 0;

-- Rango de fechas: de la primera a la ultima fecha del XML
SELECT
    @fechaInicio = MIN(T.Nodo.value('@Fecha', 'DATE')),
    @fechaFin    = MAX(T.Nodo.value('@Fecha', 'DATE'))
FROM @xmlOperaciones.nodes('/Operaciones/FechaOperacion') AS T(Nodo);

-- Una corrida anterior que nunca llego al final quedo interrumpida
UPDATE dbo.CorridaSimulacion
SET CodigoResultado = @resultadoError,
    Mensaje = N'Interrumpida: no llego al final del script.'
WHERE FechaHoraFin IS NULL
  AND CodigoResultado IS NULL;

-- Registro de esta corrida
INSERT INTO dbo.CorridaSimulacion (FechaInicioXml, FechaFinXml)
VALUES (@fechaInicio, @fechaFin);

SET @idCorrida = SCOPE_IDENTITY();

-- Primera fecha pendiente: la mas antigua que no este terminada
SET @fecha = @fechaInicio;

WHILE (@fecha <= @fechaFin
       AND EXISTS (SELECT 1
                   FROM dbo.ControlSimulacion AS CS
                   WHERE CS.FechaOperacion = @fecha
                     AND CS.FlagTerminada = @true))
BEGIN
    SET @fecha = DATEADD(DAY, 1, @fecha);
END;

IF (@fecha > @fechaFin)
BEGIN
    SET @codigoResultado = @resultadoSinPendientes;
    SET @mensaje = N'Nada pendiente: todas las fechas ya estaban '
                 + N'procesadas. No se repitio nada.';
    PRINT @mensaje;
END;

BEGIN TRY
    WHILE (@fecha <= @fechaFin AND @flagDetener = @false)
    BEGIN
        SET @fechaTexto = CONVERT(VARCHAR(10), @fecha, 23);   -- yyyy-mm-dd

        -- Una fecha ya terminada no se vuelve a procesar
        IF NOT EXISTS (SELECT 1
                       FROM dbo.ControlSimulacion AS CS
                       WHERE CS.FechaOperacion = @fecha
                         AND CS.FlagTerminada = @true)
        BEGIN
            -- No se brinca una fecha: la anterior debe estar terminada
            IF (@fecha > @fechaInicio
                AND NOT EXISTS (SELECT 1
                                FROM dbo.ControlSimulacion AS CS
                                WHERE CS.FechaOperacion = DATEADD(DAY, -1, @fecha)
                                  AND CS.FlagTerminada = @true))
            BEGIN
                SET @codigo = 50500;
                SET @mensaje = N'Detenida: no se puede procesar ' + @fechaTexto
                             + N' porque la fecha anterior no esta terminada.';
                INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
                VALUES (@codigo, N'Simulacion_TP3', @mensaje);
                PRINT @mensaje;
                SET @codigoResultado = @resultadoError;
                SET @flagDetener = @true;
            END;
        END;

        IF (@flagDetener = @false
            AND NOT EXISTS (SELECT 1
                            FROM dbo.ControlSimulacion AS CS
                            WHERE CS.FechaOperacion = @fecha
                              AND CS.FlagTerminada = @true))
        BEGIN
            SELECT @cantMov = COUNT(*)
            FROM @movimientosXml AS MX
            WHERE MX.FechaOperacion = @fecha;

            -- Fila de control de la fecha: nueva, o reanudacion
            IF NOT EXISTS (SELECT 1
                           FROM dbo.ControlSimulacion AS CS
                           WHERE CS.FechaOperacion = @fecha)
            BEGIN
                INSERT INTO dbo.ControlSimulacion (
                    FechaOperacion,
                    IdCorridaSimulacion,
                    CantMovimientosXml
                )
                VALUES (@fecha, @idCorrida, @cantMov);
            END
            ELSE
            BEGIN
                UPDATE dbo.ControlSimulacion
                SET CantIntentos = CantIntentos + 1,
                    IdCorridaSimulacion = @idCorrida,
                    CodigoError = NULL
                WHERE FechaOperacion = @fecha;

                PRINT N'Reanudando la fecha ' + @fechaTexto;
            END;

            UPDATE dbo.CorridaSimulacion
            SET FechaDesde = @fecha
            WHERE Id = @idCorrida
              AND FechaDesde IS NULL;

            SELECT
                @flagAltas    = CS.FlagAltasProcesadas,
                @ultimoMov    = CS.UltimoMovimientoProcesado,
                @ultimaCuenta = CS.UltimaCuentaCerrada
            FROM dbo.ControlSimulacion AS CS
            WHERE CS.FechaOperacion = @fecha;

            -- 1. ALTAS DEL DIA (solo si no se hicieron antes)
            IF (@flagAltas = @false)
            BEGIN
                EXEC dbo.sp_CargarAltasDia
                    @inXml = @xmlOperaciones,
                    @inFecha = @fecha,
                    @outResultCode = @codigo OUTPUT;

                IF (@codigo = 0)
                BEGIN
                    -- Si el dia traia altas, el SP ya dejo esta marca dentro
                    -- de su transaccion; aqui queda para los dias sin altas.
                    UPDATE dbo.ControlSimulacion
                    SET FlagAltasProcesadas = @true
                    WHERE FechaOperacion = @fecha;
                END
                ELSE
                BEGIN
                    SET @mensaje = N'Detenida en ' + @fechaTexto
                                 + N': las altas fallaron con codigo '
                                 + ISNULL(CAST(@codigo AS NVARCHAR(10)), N'?');
                    UPDATE dbo.ControlSimulacion
                    SET CodigoError = @codigo
                    WHERE FechaOperacion = @fecha;
                    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
                    VALUES (@codigo, N'Simulacion_TP3', @mensaje);
                    PRINT @mensaje;
                    SET @codigoResultado = @resultadoError;
                    SET @flagDetener = @true;
                END;
            END;

            -- 2. MOVIMIENTOS DEL DIA, desde el que sigue al ultimo procesado
            SET @i = @ultimoMov + 1;

            WHILE (@i <= @cantMov AND @flagDetener = @false)
            BEGIN
                -- Referencia estable: fecha + posicion dentro del dia
                SET @referencia = @fechaTexto + '#' + CAST(@i AS VARCHAR(10));

                -- Si ya esta en dbo.Movimiento (se aplico pero la corrida no
                -- alcanzo a marcarlo en el control), no se vuelve a aplicar.
                IF EXISTS (SELECT 1
                           FROM dbo.Movimiento AS M
                           WHERE M.ReferenciaOrigen = @referencia)
                BEGIN
                    SET @codigo = @codigoMovYaRegistrado;
                END
                ELSE
                BEGIN
                    SELECT
                        @numeroCuenta = MX.NumeroCuenta,
                        @tipoMov      = MX.TipoMovimiento,
                        @monto        = MX.Monto,
                        @descripcion  = MX.Descripcion
                    FROM @movimientosXml AS MX
                    WHERE MX.FechaOperacion = @fecha
                      AND MX.Secuencia = @i;

                    EXEC dbo.sp_AplicarMovimiento
                        @inNumeroCuenta = @numeroCuenta,
                        @inTipoMovimiento = @tipoMov,
                        @inFechaMovimiento = @fecha,
                        @inMonto = @monto,
                        @inDescripcion = @descripcion,
                        @inReferenciaOrigen = @referencia,
                        @outResultCode = @codigo OUTPUT,
                        @outIdMovimiento = @idMovimiento OUTPUT;
                END;

                IF (@codigo = 0 OR @codigo = @codigoMovYaRegistrado)
                BEGIN
                    SET @movOk = @movOk + 1;
                    UPDATE dbo.ControlSimulacion
                    SET UltimoMovimientoProcesado = @i,
                        CantMovimientosAplicados = CantMovimientosAplicados + 1
                    WHERE FechaOperacion = @fecha;
                END
                ELSE
                BEGIN
                    SET @movRechazados = @movRechazados + 1;
                    SET @mensaje = N'Movimiento rechazado ' + @referencia
                                 + N' cuenta ' + ISNULL(@numeroCuenta, N'?')
                                 + N' tipo ' + ISNULL(@tipoMov, N'?')
                                 + N' monto '
                                 + ISNULL(CAST(@monto AS NVARCHAR(30)), N'?')
                                 + N' codigo '
                                 + ISNULL(CAST(@codigo AS NVARCHAR(10)), N'?');
                    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
                    VALUES (@codigo, N'Simulacion_TP3', @mensaje);
                    UPDATE dbo.ControlSimulacion
                    SET UltimoMovimientoProcesado = @i,
                        CantMovimientosRechazados = CantMovimientosRechazados + 1
                    WHERE FechaOperacion = @fecha;
                END;

                -- Prueba de reanudacion: detenerse a proposito
                IF (@fecha = @pruebaFechaDetener
                    AND @i = @pruebaDetenerTrasMovimientos)
                BEGIN
                    SET @mensaje = N'Detenida a proposito (prueba) en '
                                 + @fechaTexto + N' tras el movimiento '
                                 + CAST(@i AS NVARCHAR(10));
                    PRINT @mensaje;
                    SET @codigoResultado = @resultadoPrueba;
                    SET @flagDetener = @true;
                END;

                SET @i = @i + 1;
            END;

            -- CIERRES DEL DIA: cuentas cuyo estado vence hoy, por Id (PK),
            --    empezando por la que sigue a la ultima cerrada
            SET @cierresHoy = 0;

            SELECT @idCuenta = MIN(E.IdCuenta)
            FROM dbo.EstadoCuenta AS E
            WHERE E.FechaFin = @fecha
              AND E.IdCuenta > @ultimaCuenta;

            WHILE (@idCuenta IS NOT NULL AND @flagDetener = @false)
            BEGIN
                SELECT @numeroCuenta = C.NumeroCuenta
                FROM dbo.Cuenta AS C
                WHERE C.Id = @idCuenta;

                -- Si ya existe el estado del periodo siguiente, este cierre ya
                -- se hizo (la corrida anterior no alcanzo a marcarlo).
                IF EXISTS (SELECT 1
                           FROM dbo.EstadoCuenta AS E
                           WHERE E.IdCuenta = @idCuenta
                             AND E.FechaInicio = DATEADD(DAY, 1, @fecha))
                BEGIN
                    SET @codigo = @codigoPeriodoCerrado;
                END
                ELSE
                BEGIN
                    EXEC dbo.sp_CerrarYAbrirEstadoCuenta
                        @inNumeroCuenta = @numeroCuenta,
                        @inFechaCierre = @fecha,
                        @outResultCode = @codigo OUTPUT,
                        @outIdNuevoEstadoCuenta = @idEstadoNuevo OUTPUT;
                END;

                IF (@codigo = 0 OR @codigo = @codigoPeriodoCerrado)
                BEGIN
                    SET @cierresOk = @cierresOk + 1;
                    SET @cierresHoy = @cierresHoy + 1;
                    UPDATE dbo.ControlSimulacion
                    SET UltimaCuentaCerrada = @idCuenta,
                        CantCierres = CantCierres + 1
                    WHERE FechaOperacion = @fecha;

                    -- Prueba de reanudacion: detenerse a proposito
                    IF (@fecha = @pruebaFechaDetener
                        AND @cierresHoy = @pruebaDetenerTrasCierres)
                    BEGIN
                        SET @mensaje = N'Detenida a proposito (prueba) en '
                                     + @fechaTexto + N' tras cerrar la cuenta '
                                     + @numeroCuenta;
                        PRINT @mensaje;
                        SET @codigoResultado = @resultadoPrueba;
                        SET @flagDetener = @true;
                    END;
                END
                ELSE
                BEGIN
                    SET @mensaje = N'Detenida en ' + @fechaTexto
                                 + N': el cierre de la cuenta '
                                 + ISNULL(@numeroCuenta, N'?')
                                 + N' fallo con codigo '
                                 + ISNULL(CAST(@codigo AS NVARCHAR(10)), N'?');
                    UPDATE dbo.ControlSimulacion
                    SET CodigoError = @codigo
                    WHERE FechaOperacion = @fecha;
                    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
                    VALUES (@codigo, N'Simulacion_TP3', @mensaje);
                    PRINT @mensaje;
                    SET @codigoResultado = @resultadoError;
                    SET @flagDetener = @true;
                END;

                SELECT @idCuenta = MIN(E.IdCuenta)
                FROM dbo.EstadoCuenta AS E
                WHERE E.FechaFin = @fecha
                  AND E.IdCuenta > @idCuenta;
            END;

            --LA FECHA QUEDA TERMINADA
            IF (@flagDetener = @false)
            BEGIN
                UPDATE dbo.ControlSimulacion
                SET FlagTerminada = @true,
                    FechaHoraFin = SYSDATETIME()
                WHERE FechaOperacion = @fecha;

                SET @fechasTerminadas = @fechasTerminadas + 1;

                UPDATE dbo.CorridaSimulacion
                SET FechaHasta = @fecha,
                    CantFechasTerminadas = @fechasTerminadas
                WHERE Id = @idCorrida;
            END;
        END;

        IF (@flagDetener = @false)
        BEGIN
            SET @fecha = DATEADD(DAY, 1, @fecha);
        END;
    END;
END TRY
BEGIN CATCH
    IF (@@TRANCOUNT > 0)
        ROLLBACK TRANSACTION;

    INSERT INTO dbo.ErrorBD (
        NumeroError, Severidad, Estado, Procedimiento, Linea, Mensaje
    )
    VALUES (
        ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
        ISNULL(ERROR_PROCEDURE(), N'Simulacion_TP3'), ERROR_LINE(),
        ERROR_MESSAGE()
    );

    UPDATE dbo.ControlSimulacion
    SET CodigoError = ERROR_NUMBER()
    WHERE FechaOperacion = @fecha;

    SET @mensaje = N'Detenida por error inesperado en '
                 + CONVERT(NVARCHAR(10), @fecha, 23) + N'. Ver dbo.ErrorBD.';
    PRINT @mensaje;
    SET @codigoResultado = @resultadoError;
    SET @flagDetener = @true;
END CATCH;

IF (@codigoResultado IS NULL)
BEGIN
    SET @codigoResultado = @resultadoCompleta;
    SET @mensaje = N'Completa: termino ' + CAST(@fechasTerminadas AS NVARCHAR(10))
                 + N' fechas, hasta ' + CONVERT(NVARCHAR(10), @fechaFin, 23) + N'.';
    PRINT @mensaje;
END;

UPDATE dbo.CorridaSimulacion
SET FechaHoraFin = SYSDATETIME(),
    CodigoResultado = @codigoResultado,
    Mensaje = @mensaje
WHERE Id = @idCorrida;

-- RESUMEN DE ESTA CORRIDA
SELECT
    CR.Id                   AS Corrida,
    CR.FechaDesde,
    CR.FechaHasta,
    CR.CantFechasTerminadas AS FechasTerminadas,
    @movOk                  AS MovimientosAplicados,
    @movRechazados          AS MovimientosRechazados,
    @cierresOk              AS Cierres,
    CR.CodigoResultado,
    CR.Mensaje
FROM dbo.CorridaSimulacion AS CR
WHERE CR.Id = @idCorrida;

-- TOTALES DE LA SIMULACION (todas las corridas juntas)
SELECT
    DATEDIFF(DAY, @fechaInicio, @fechaFin) + 1 AS FechasXml,
    (SELECT COUNT(*)
     FROM dbo.ControlSimulacion AS CS
     WHERE CS.FlagTerminada = @true)           AS FechasTerminadas,
    (SELECT MIN(CS.FechaOperacion)
     FROM dbo.ControlSimulacion AS CS
     WHERE CS.FlagTerminada = @false)          AS FechaAMedias,
    (SELECT ISNULL(SUM(CS.CantMovimientosAplicados), 0)
     FROM dbo.ControlSimulacion AS CS)         AS MovimientosAplicados,
    (SELECT ISNULL(SUM(CS.CantMovimientosRechazados), 0)
     FROM dbo.ControlSimulacion AS CS)         AS MovimientosRechazados,
    (SELECT ISNULL(SUM(CS.CantCierres), 0)
     FROM dbo.ControlSimulacion AS CS)         AS Cierres;

SELECT C.NumeroCuenta, C.FechaCreacion, C.Saldo,
       (SELECT COUNT(*) FROM dbo.EstadoCuenta E WHERE E.IdCuenta = C.Id) AS Estados
FROM dbo.Cuenta AS C
ORDER BY C.Id;

SELECT TM.Nombre AS TipoMovimiento, COUNT(*) AS Cantidad
FROM dbo.Movimiento AS M
INNER JOIN dbo.TipoMovimiento AS TM
    ON TM.Id = M.IdTipoMovimiento
GROUP BY TM.Nombre 
ORDER BY TM.Nombre;

SELECT TOP (20) Id, NumeroError, Mensaje FROM dbo.ErrorBD ORDER BY Id DESC;