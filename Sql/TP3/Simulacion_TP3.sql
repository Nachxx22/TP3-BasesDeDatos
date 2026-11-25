/*
   Lee el XML de operaciones desde su archivo (OperacionesTarea3.xml del
   profesor) y pasa todos sus movimientos, una sola vez, a la tabla de
   movimientos dbo.MovimientoXml. Luego recorre TODAS las fechas del XML,
   una por una y en orden ascendente (aunque la fecha no tenga nodo
   FechaOperacion).
   Por cada dia:
      1. Altas:    EXEC dbo.sp_CargarAltasDia
                   (Persona -> Cuenta -> Beneficiario -> Usuario -> PuedeVer)
      2. Cuentas:  lista de las cuentas del dia: primero las que cierran ese
                   dia (su estado de cuenta vence) y despues las demas que
                   tienen movimientos, cada grupo por Id (PK). Por cada una,
                   EXEC dbo.sp_ProcesarCuentaDia, que aplica sus movimientos
                   del dia y, si cierra, el cierre, TODO en una sola
                   transaccion. Este script no abre transacciones.
      3. Totales:  aplicados, rechazados y cierres del dia, calculados desde
                   los datos.

   Control, con dbo.CorridaSimulacion y
   dbo.ControlSimulacion (12_ControlSimulacion.sql):
     - No se corre mas de una vez: una fecha terminada no se vuelve a
       procesar. Si todas estan terminadas, el script no hace nada.
     - No se brinca una fecha: empieza siempre por la fecha pendiente mas
       antigua, y antes de procesar una fecha revisa que la anterior este
       terminada.
     - Si falla sin terminar, la siguiente corrida reanuda esa fecha desde lo
       ultimo procesado: no repite las altas y sigue con la cuenta que va
       despues de la ultima procesada, guardada por su PK
       (IdUltimaCuentaProcesada). Aunque esa marca quedara atrasada, no se
       repite nada: sp_ProcesarCuentaDia no hace nada si la cuenta ya se
       proceso ese dia.

   Si fallan las altas o una cuenta, la corrida SE DETIENE en esa fecha y
   deja el error en dbo.ErrorBD (con la fecha y la cuenta); se corrige la
   causa y se vuelve a correr (reanuda). Si un movimiento es rechazado
   (fondos insuficientes, etc.) queda marcado en dbo.MovimientoXml, se
   anota en dbo.ErrorBD y la simulacion continua.
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

-- SOLO PARA LA PRUEBA DE REANUDACION (Pruebas/Prueba_ReanudarSimulacion.sql):
-- detienen la corrida a proposito, como si fallara, en la fecha indicada y
-- despues de procesar esa cantidad de cuentas del dia. En una corrida
-- normal las dos quedan en NULL.
DECLARE @pruebaFechaDetener       DATE = NULL;  -- ej. '2026-04-01'
DECLARE @pruebaDetenerTrasCuentas INT  = NULL;  -- ej. 1

-- XML DE OPERACIONES: se lee del archivo del profesor (OperacionesTarea3.xml).
-- La ruta es de la computadora donde corre SQL Server. Para usar otra
-- ubicacion se cambia SOLO la ruta de OPENROWSET (tiene que ir escrita ahi).
-- SINGLE_BLOB lee el archivo tal cual, y al convertirlo a XML SQL Server
-- respeta su encoding="UTF-8" (las tildes y enes quedan bien).
DECLARE @xmlOperaciones XML;

-- Movimientos tal como se leen del XML. Sec (IDENTITY) los numera en el
-- orden en que vienen.
DECLARE @movimientosLeidos TABLE (
    Sec            INT IDENTITY(1,1) PRIMARY KEY,
    FechaOperacion DATE,
    NumeroCuenta   VARCHAR(16),
    TipoMovimiento VARCHAR(64),
    Monto          DECIMAL(18,2),
    Descripcion    NVARCHAR(256)
);

-- Movimientos en la tabla sin ninguna fecha en el control: quedaron de otra
-- simulacion, hay que correr antes Limpiar_DatosTP3.sql
IF (NOT EXISTS (SELECT 1 FROM dbo.ControlSimulacion)
    AND EXISTS (SELECT 1 FROM dbo.MovimientoXml))
BEGIN
    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
    VALUES (50502, N'Simulacion_TP3', N'MovimientoXml con datos de otra '
            + N'simulacion: correr Limpiar_DatosTP3.sql.');
    PRINT N'MovimientoXml con datos de otra simulacion.';
    RETURN;
END;

BEGIN TRY
    SELECT @xmlOperaciones = CAST(Archivo.BulkColumn AS XML)
    FROM OPENROWSET(
        BULK N'C:\Users\Nacho\Downloads\OperacionesTarea3.xml',
        SINGLE_BLOB
    ) AS Archivo;

    -- TABLA DE MOVIMIENTOS: todos los movimientos del XML se pasan UNA sola
    -- vez (SQL masivo). Si ya tiene filas, es una corrida que se reanuda y
    -- no se vuelve a llenar.
    IF NOT EXISTS (SELECT 1 FROM dbo.MovimientoXml)
    BEGIN
        -- Una sola lectura del XML: todos los nodos Movimientos, en orden.
        -- La fecha es el atributo Fecha del nodo padre (FechaOperacion).
        INSERT INTO @movimientosLeidos (
            FechaOperacion,
            NumeroCuenta,
            TipoMovimiento,
            Monto,
            Descripcion
        )
        SELECT
            T.Nodo.value('(../@Fecha)[1]', 'DATE'),
            T.Nodo.value('@CodigoCuenta', 'VARCHAR(16)'),
            T.Nodo.value('@Tipo', 'VARCHAR(64)'),
            T.Nodo.value('@Monto', 'DECIMAL(18,2)'),
            T.Nodo.value('@Descripcion', 'NVARCHAR(256)')
        FROM @xmlOperaciones.nodes('/Operaciones/FechaOperacion/Movimientos')
            AS T(Nodo);

        -- Secuencia = posicion del movimiento dentro de su fecha:
        -- Sec - (primer Sec de esa fecha) + 1. Conserva el orden del XML,
        -- que importa para el saldo y para la comision SINPE.
        INSERT INTO dbo.MovimientoXml (
            FechaOperacion,
            Secuencia,
            NumeroCuenta,
            TipoMovimiento,
            Monto,
            Descripcion
        )
        SELECT
            ML.FechaOperacion,
            ML.Sec - (SELECT MIN(M2.Sec)
                      FROM @movimientosLeidos AS M2
                      WHERE M2.FechaOperacion = ML.FechaOperacion) + 1,
            ML.NumeroCuenta,
            ML.TipoMovimiento,
            ML.Monto,
            ML.Descripcion
        FROM @movimientosLeidos AS ML
        ORDER BY ML.Sec;
    END;
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

-- Variables
DECLARE @idCorrida INT;
DECLARE @fechaInicio DATE;
DECLARE @fechaFin DATE;
DECLARE @fecha DATE;
DECLARE @fechaTexto VARCHAR(10);
DECLARE @flagDetener BIT = @false;
DECLARE @flagAltas BIT;
DECLARE @idUltimaCuenta INT;
DECLARE @idCuenta INT;
DECLARE @numeroCuenta VARCHAR(16);
DECLARE @posicion INT;
DECLARE @primeraPosicion INT;
DECLARE @codigo INT;
DECLARE @codigoResultado INT = NULL;
DECLARE @aplicados INT;
DECLARE @rechazados INT;
DECLARE @idEstadoNuevo INT;
DECLARE @mensaje NVARCHAR(256);
DECLARE @movOk INT = 0;
DECLARE @movRechazados INT = 0;
DECLARE @cierresOk INT = 0;
DECLARE @fechasTerminadas INT = 0;

-- Cuentas a procesar en la fecha, en orden. Posicion sigue creciendo de una
-- fecha a otra; la posicion dentro del dia es Posicion - @primeraPosicion + 1.
-- IdCuenta es la PK de la cuenta (NULL si la cuenta no existe).
DECLARE @cuentasDia TABLE (
    Posicion     INT IDENTITY(1,1) PRIMARY KEY,
    NumeroCuenta VARCHAR(16) NOT NULL,
    IdCuenta     INT NULL
);

-- Rango de fechas: de la primera a la ultima fecha del XML
SELECT
    @fechaInicio = MIN(T.Nodo.value('@Fecha', 'DATE')),
    @fechaFin    = MAX(T.Nodo.value('@Fecha', 'DATE'))
FROM @xmlOperaciones.nodes('/Operaciones/FechaOperacion') AS T(Nodo);

-- Sin fechas (XML vacio o sin nodos FechaOperacion): no hay que simular
IF (@fechaInicio IS NULL)
BEGIN
    INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
    VALUES (50501, N'Simulacion_TP3',
            N'El XML de operaciones esta vacio o no trae fechas.');
    PRINT N'El XML de operaciones esta vacio o no trae fechas.';
    RETURN;
END;

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
                SELECT @fecha, @idCorrida, COUNT(*)
                FROM dbo.MovimientoXml AS MX
                WHERE MX.FechaOperacion = @fecha;
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
                @flagAltas      = CS.FlagAltasProcesadas,
                @idUltimaCuenta = CS.IdUltimaCuentaProcesada
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

            -- 2. CUENTAS DEL DIA. La lista se arma siempre igual (tambien al
            -- reanudar), asi la posicion de cada cuenta no cambia.
            DELETE FROM @cuentasDia;

            -- Primero las que cierran hoy (su estado de cuenta vence hoy)
            INSERT INTO @cuentasDia (NumeroCuenta, IdCuenta)
            SELECT C.NumeroCuenta, C.Id
            FROM dbo.Cuenta AS C
            INNER JOIN dbo.EstadoCuenta AS E
                ON E.IdCuenta = C.Id
            WHERE E.FechaFin = @fecha
            ORDER BY C.Id;

            -- Despues las demas que tienen movimientos hoy (una cuenta que
            -- no existe va primero: el SP rechaza sus movimientos)
            INSERT INTO @cuentasDia (NumeroCuenta, IdCuenta)
            SELECT MX.NumeroCuenta, C.Id
            FROM dbo.MovimientoXml AS MX
            LEFT OUTER JOIN dbo.Cuenta AS C
                ON C.NumeroCuenta = MX.NumeroCuenta
            WHERE MX.FechaOperacion = @fecha
              AND NOT EXISTS (SELECT 1
                              FROM @cuentasDia AS CD
                              WHERE CD.NumeroCuenta = MX.NumeroCuenta)
            GROUP BY MX.NumeroCuenta, C.Id
            ORDER BY C.Id, MX.NumeroCuenta;

            SELECT @primeraPosicion = MIN(CD.Posicion)
            FROM @cuentasDia AS CD;

            -- Se empieza despues de la ultima cuenta procesada, buscada por
            -- su PK (reanudacion). Si no hay ninguna, desde la primera.
            SELECT @posicion = MIN(CD.Posicion)
            FROM @cuentasDia AS CD
            WHERE CD.Posicion > ISNULL((SELECT U.Posicion
                                        FROM @cuentasDia AS U
                                        WHERE U.IdCuenta = @idUltimaCuenta),
                                       0);

            WHILE (@posicion IS NOT NULL AND @flagDetener = @false)
            BEGIN
                SELECT
                    @numeroCuenta = CD.NumeroCuenta,
                    @idCuenta     = CD.IdCuenta
                FROM @cuentasDia AS CD
                WHERE CD.Posicion = @posicion;

                EXEC dbo.sp_ProcesarCuentaDia
                    @inNumeroCuenta = @numeroCuenta,
                    @inFechaOperacion = @fecha,
                    @outResultCode = @codigo OUTPUT,
                    @outCantAplicados = @aplicados OUTPUT,
                    @outCantRechazados = @rechazados OUTPUT,
                    @outIdNuevoEstadoCuenta = @idEstadoNuevo OUTPUT;

                IF (@codigo = 0)
                BEGIN
                    SET @movOk = @movOk + @aplicados;
                    SET @movRechazados = @movRechazados + @rechazados;

                    IF (@idEstadoNuevo IS NOT NULL)
                        SET @cierresOk = @cierresOk + 1;

                    -- Los rechazos quedan en MovimientoXml; se anotan tambien
                    -- en ErrorBD, como antes
                    IF (@rechazados > 0)
                    BEGIN
                        INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento,
                            Mensaje)
                        SELECT MX.CodigoResultado, N'Simulacion_TP3',
                            N'Movimiento rechazado ' + @fechaTexto + N'#'
                            + CAST(MX.Secuencia AS NVARCHAR(10))
                            + N' cuenta ' + MX.NumeroCuenta
                            + N' tipo ' + MX.TipoMovimiento
                            + N' monto ' + CAST(MX.Monto AS NVARCHAR(30))
                            + N' codigo '
                            + CAST(MX.CodigoResultado AS NVARCHAR(10))
                        FROM dbo.MovimientoXml AS MX
                        WHERE MX.FechaOperacion = @fecha
                          AND MX.NumeroCuenta = @numeroCuenta
                          AND MX.CodigoResultado <> 0;
                    END;

                    -- Ultima llave procesada: la PK de la cuenta. Una cuenta
                    -- que no existe no tiene PK y no mueve la marca (si se
                    -- vuelve a pasar por ella, el SP ya no encuentra nada).
                    UPDATE dbo.ControlSimulacion
                    SET IdUltimaCuentaProcesada = @idCuenta
                    WHERE FechaOperacion = @fecha
                      AND @idCuenta IS NOT NULL;

                    -- Prueba de reanudacion: detenerse a proposito
                    IF (@fecha = @pruebaFechaDetener
                        AND @posicion - @primeraPosicion + 1
                            = @pruebaDetenerTrasCuentas)
                    BEGIN
                        SET @mensaje = N'Detenida a proposito (prueba) en '
                                     + @fechaTexto + N' tras la cuenta '
                                     + @numeroCuenta;
                        PRINT @mensaje;
                        SET @codigoResultado = @resultadoPrueba;
                        SET @flagDetener = @true;
                    END;
                END
                ELSE
                BEGIN
                    SET @mensaje = N'Detenida en ' + @fechaTexto
                                 + N': la cuenta ' + @numeroCuenta
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

                SELECT @posicion = MIN(CD.Posicion)
                FROM @cuentasDia AS CD
                WHERE CD.Posicion > @posicion;
            END;

            -- 3. TOTALES DEL DIA, desde los datos (quedan bien aunque la
            -- corrida se haya cortado)
            UPDATE dbo.ControlSimulacion
            SET CantMovimientosAplicados = (SELECT COUNT(*)
                    FROM dbo.MovimientoXml AS MX
                    WHERE MX.FechaOperacion = @fecha
                      AND MX.CodigoResultado = 0),
                CantMovimientosRechazados = (SELECT COUNT(*)
                    FROM dbo.MovimientoXml AS MX
                    WHERE MX.FechaOperacion = @fecha
                      AND MX.CodigoResultado <> 0),
                CantCierres = (SELECT COUNT(*)
                    FROM dbo.EstadoCuenta AS E
                    INNER JOIN dbo.EstadoCuenta AS EN
                        ON EN.IdCuenta = E.IdCuenta
                       AND EN.FechaInicio = DATEADD(DAY, 1, @fecha)
                    WHERE E.FechaFin = @fecha)
            WHERE FechaOperacion = @fecha;

            -- Antes de dar la fecha por terminada: ningun movimiento del dia
            -- puede quedar pendiente
            IF (@flagDetener = @false
                AND EXISTS (SELECT 1
                            FROM dbo.MovimientoXml AS MX
                            WHERE MX.FechaOperacion = @fecha
                              AND MX.FlagProcesado = @false))
            BEGIN
                SET @codigo = 50503;
                SET @mensaje = N'Detenida en ' + @fechaTexto
                             + N': quedaron movimientos sin procesar.';
                UPDATE dbo.ControlSimulacion
                SET CodigoError = @codigo
                WHERE FechaOperacion = @fecha;
                INSERT INTO dbo.ErrorBD (NumeroError, Procedimiento, Mensaje)
                VALUES (@codigo, N'Simulacion_TP3', @mensaje);
                PRINT @mensaje;
                SET @codigoResultado = @resultadoError;
                SET @flagDetener = @true;
            END;

            -- LA FECHA QUEDA TERMINADA
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