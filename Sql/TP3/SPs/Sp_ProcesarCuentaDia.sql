/*
    Procesa lo de una cuenta en una fecha de la simulacion: aplica sus
    movimientos pendientes del dia (lo de sp_AplicarMovimiento) y, si su
    estado de cuenta vence ese dia, lo cierra y abre el del siguiente
    periodo (lo de sp_CerrarYAbrirEstadoCuenta).
    Primero valida y calcula todo, sin transaccion. Solo si todo esta bien
    abre UNA transaccion, que solo registra lo calculado: lo de la cuenta
    en ese dia queda completo o no queda nada.
    Como antes, un movimiento que no se puede aplicar se rechaza y los
    demas siguen; queda marcado en dbo.MovimientoXml con su codigo. Si no
    hay nada pendiente, devuelve 0 sin hacer nada (sirve para reanudar).
    Los calculos puros estan en las funciones dbo.fnTextoComprobante y
    dbo.fnFechaFinEstadoCuenta, que no escriben ni abren transacciones.
    Codigos de resultado (el detalle esta junto a cada validacion):
        0                   Operacion exitosa (o no habia nada que hacer).
        50200               Parametros invalidos.
        50203-50205, 50210  Validaciones de la cuenta en la fecha.
        50303, 50305-50308  Validaciones del cierre.
        Otro                Error de SQL Server (queda en dbo.ErrorBD).
    Rechazo de un movimiento (MovimientoXml.CodigoResultado):
        50200-50209         Los mismos de sp_AplicarMovimiento.
    Ejemplo de ejecucion (solo en una base de pruebas):
    DECLARE @Codigo INT, @Aplicados INT, @Rechazados INT, @IdEstado INT;
    EXEC dbo.sp_ProcesarCuentaDia
        @inNumeroCuenta = 'NUMERO_CUENTA',
        @inFechaOperacion = '2026-03-31',
        @outResultCode = @Codigo OUTPUT,
        @outCantAplicados = @Aplicados OUTPUT,
        @outCantRechazados = @Rechazados OUTPUT,
        @outIdNuevoEstadoCuenta = @IdEstado OUTPUT;
    SELECT @Codigo, @Aplicados, @Rechazados, @IdEstado;
*/
USE CuentaAhorrosTP2;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarCuentaDia
    @inNumeroCuenta VARCHAR(16),
    @inFechaOperacion DATE,
    @outResultCode INT OUTPUT,
    @outCantAplicados INT OUTPUT,
    @outCantRechazados INT OUTPUT,
    @outIdNuevoEstadoCuenta INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @true BIT = 1, @false BIT = 0;

    -- Cuenta, dueno y tipo de cuenta
    DECLARE @IdCuenta INT, @FechaCreacion DATE, @SaldoCuenta DECIMAL(18,2),
        @EmailDueno VARCHAR(128), @NombreDueno VARCHAR(64),
        @SimboloMoneda NVARCHAR(4), @LimiteSinpe DECIMAL(18,2),
        @ComisionSinpe DECIMAL(18,2), @TasaInteresAnual DECIMAL(5,2),
        @SaldoMinimoRequerido DECIMAL(18,2), @MultaSaldoMin DECIMAL(18,2),
        @CargoMensual DECIMAL(18,2), @MaxOperacionesATM INT,
        @MaxOperacionesHumano INT, @ComisionATM DECIMAL(18,2),
        @ComisionHumano DECIMAL(18,2);

    -- Estado de cuenta vigente (saldos y contadores en memoria)
    DECLARE @IdEstadoCuenta INT, @CantidadEstados INT,
        @SaldoPeriodo DECIMAL(18,2), @SaldoMinimoPeriodo DECIMAL(18,2),
        @InteresesAcumulados DECIMAL(18,2), @CantRetiros INT,
        @CantDepositos INT, @CantSinpeEntrantes INT, @CantSinpeSalientes INT,
        @OperacionesATM INT, @RetirosATM INT, @OperacionesHumano INT,
        @RetirosHumano INT;

    -- Validaciones de la cuenta en la fecha
    DECLARE @FlagCierre BIT = 0, @FlagPeriodoCerrado BIT = 0,
        @CantPendientes INT, @CantDuplicados INT, @CantTiposCierre INT,
        @CantMovimientosCierre INT, @IdTipoComision INT,
        @ReferenciaOrigen VARCHAR(128), @FechaInicioNueva DATE;

    -- Cada movimiento del dia
    DECLARE @SecuenciaXml INT, @Referencia VARCHAR(128),
        @TipoTexto VARCHAR(64), @Monto DECIMAL(18,2),
        @Descripcion NVARCHAR(256), @CodigoMovimiento INT,
        @IdTipoMovimiento INT, @Accion VARCHAR(7),
        @FlagGeneraComprobante BIT, @NombreTipoMovimiento VARCHAR(64),
        @SaldoActual DECIMAL(18,2), @SaldoPrincipal DECIMAL(18,2),
        @SaldoFinal DECIMAL(18,2), @MontoComision DECIMAL(18,2),
        @TotalSinpeAnterior DECIMAL(18,2), @Orden INT = 0,
        @SecComprobante INT = 0, @CantAplicados INT = 0,
        @CantRechazados INT = 0;

    -- Cierre
    DECLARE @SaldoTrabajo DECIMAL(18,2), @SaldoMinimoFinal DECIMAL(18,2),
        @MontoIntereses DECIMAL(18,2), @MontoExcesoATM DECIMAL(18,2),
        @MontoExcesoHumano DECIMAL(18,2), @MontoMulta DECIMAL(18,2),
        @TotalCargos DECIMAL(18,2), @FechaFinNueva DATE, @Secuencia TINYINT,
        @TipoMovimiento INT, @MontoMovimiento DECIMAL(18,2),
        @DescripcionMovimiento NVARCHAR(256), @IdUltimoComprobante INT;

    -- Movimientos pendientes del dia y lo que se va a registrar
    DECLARE @MovimientosDia TABLE (
        Secuencia INT PRIMARY KEY, IdMovimientoXml INT NOT NULL,
        ReferenciaOrigen VARCHAR(128) NOT NULL,
        TipoMovimiento VARCHAR(64) NOT NULL, Monto DECIMAL(18,2) NOT NULL,
        Descripcion NVARCHAR(256) NOT NULL, CodigoResultado INT NULL
    );

    DECLARE @ComprobantesNuevos TABLE (
        SecComprobante INT PRIMARY KEY, Asunto NVARCHAR(128) NOT NULL,
        TextoEmail NVARCHAR(2000) NOT NULL
    );

    DECLARE @MovimientosNuevos TABLE (
        Orden INT PRIMARY KEY, IdTipoMovimiento INT NOT NULL,
        Monto DECIMAL(18,2) NOT NULL, Descripcion NVARCHAR(256) NOT NULL,
        SaldoPosterior DECIMAL(18,2) NOT NULL,
        ReferenciaOrigen VARCHAR(128) NOT NULL,
        SecuenciaOrigen TINYINT NOT NULL,
        SecComprobante INT NULL  -- NULL: sin comprobante
    );

    SET @outResultCode = 0;
    SET @outCantAplicados = 0;
    SET @outCantRechazados = 0;
    SET @outIdNuevoEstadoCuenta = NULL;

    -- Validar parametros.
    IF @inNumeroCuenta IS NULL
       OR LTRIM(RTRIM(@inNumeroCuenta)) = ''
       OR @inFechaOperacion IS NULL
    BEGIN
        SET @outResultCode = 50200;
        RETURN;
    END;

    BEGIN TRY

        -- 1. VALIDACIONES (sin transaccion)

        SELECT
            @IdCuenta = C.Id, @FechaCreacion = C.FechaCreacion,
            @SaldoCuenta = C.Saldo, @EmailDueno = P.Email,
            @NombreDueno = P.Nombre, @SimboloMoneda = TMO.Simbolo,
            @LimiteSinpe = T.MontoMaxSinpeDiario,
            @ComisionSinpe = T.ComisionSinpe,
            @TasaInteresAnual = T.TasaInteresAnual,
            @SaldoMinimoRequerido = T.SaldoMinimo,
            @MultaSaldoMin = T.MultaSaldoMin,
            @CargoMensual = T.CargoMensual,
            @MaxOperacionesATM = T.NumRetirosAutomatico,
            @MaxOperacionesHumano = T.NumRetirosHumano,
            @ComisionATM = T.ComisionAutomatico,
            @ComisionHumano = T.ComisionHumano
        FROM dbo.Cuenta AS C
        INNER JOIN dbo.Persona AS P ON P.Id = C.IdPersona
        INNER JOIN dbo.TipoCuentaAhorro AS T ON T.Id = C.IdTipoCuentaAhorro
        INNER JOIN dbo.TipoMoneda AS TMO ON TMO.Id = T.IdTipoMoneda
        WHERE C.NumeroCuenta = @inNumeroCuenta;

        -- Como antes, el movimiento de una cuenta que no existe se rechaza
        -- (50202) y la simulacion sigue. Es una sola actualizacion: no
        -- necesita transaccion.
        IF @IdCuenta IS NULL
        BEGIN
            UPDATE dbo.MovimientoXml
            SET FlagProcesado = @true, CodigoResultado = 50202
            WHERE FechaOperacion = @inFechaOperacion
              AND NumeroCuenta = @inNumeroCuenta
              AND FlagProcesado = @false;

            SET @outCantRechazados = @@ROWCOUNT;
            RETURN;
        END;

        -- Movimientos pendientes del dia. La referencia es la fecha y la
        -- posicion del movimiento en el dia: '2026-04-20#3'.
        INSERT INTO @MovimientosDia (Secuencia, IdMovimientoXml,
            ReferenciaOrigen, TipoMovimiento, Monto, Descripcion)
        SELECT MX.Secuencia, MX.Id,
            CONVERT(VARCHAR(10), @inFechaOperacion, 23) + '#'
                + CAST(MX.Secuencia AS VARCHAR(10)),
            MX.TipoMovimiento, MX.Monto, MX.Descripcion
        FROM dbo.MovimientoXml AS MX
        WHERE MX.FechaOperacion = @inFechaOperacion
          AND MX.NumeroCuenta = @inNumeroCuenta
          AND MX.FlagProcesado = @false;

        SET @CantPendientes = @@ROWCOUNT;

        -- Cierra hoy si un estado suyo vence hoy; si ya existe el estado
        -- del siguiente periodo, el cierre ya se hizo
        SET @FechaInicioNueva = DATEADD(DAY, 1, @inFechaOperacion);

        IF EXISTS (SELECT 1 FROM dbo.EstadoCuenta AS E
                   WHERE E.IdCuenta = @IdCuenta
                     AND E.FechaFin = @inFechaOperacion)
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.EstadoCuenta AS E
                       WHERE E.IdCuenta = @IdCuenta
                         AND E.FechaInicio = @FechaInicioNueva)
                SET @FlagPeriodoCerrado = @true;
            ELSE
                SET @FlagCierre = @true;
        END;

        -- Nada que hacer (ya se proceso en una corrida anterior)
        IF @CantPendientes = 0 AND @FlagCierre = @false
            RETURN;

        -- Localiza el unico estado correspondiente a la fecha
        SELECT @IdEstadoCuenta = MIN(E.Id), @CantidadEstados = COUNT(*)
        FROM dbo.EstadoCuenta AS E
        WHERE E.IdCuenta = @IdCuenta
          AND @inFechaOperacion BETWEEN E.FechaInicio AND E.FechaFin;

        SELECT
            @SaldoPeriodo = E.SaldoFinal, @SaldoMinimoPeriodo = E.SaldoMinimo,
            @InteresesAcumulados = E.InteresesAcumulados,
            @CantRetiros = E.CantRetiros, @CantDepositos = E.CantDepositos,
            @CantSinpeEntrantes = E.CantSinpeEntrantes,
            @CantSinpeSalientes = E.CantSinpeSalientes,
            @OperacionesATM = E.CantOperacionesATM,
            @RetirosATM = E.CantRetirosATM,
            @OperacionesHumano = E.CantOperacionesHumano,
            @RetirosHumano = E.CantRetirosHumano
        FROM dbo.EstadoCuenta AS E
        WHERE E.Id = @IdEstadoCuenta;

        -- Movimientos pendientes que ya estan registrados
        SELECT @CantDuplicados = COUNT(*)
        FROM @MovimientosDia AS MD
        INNER JOIN dbo.Movimiento AS M
            ON M.ReferenciaOrigen = MD.ReferenciaOrigen;

        -- Movimientos del cierre ya registrados (referencia estable,
        -- diferente para cada cuenta y fecha)
        SET @ReferenciaOrigen = 'CIERRE:' + @inNumeroCuenta + ':'
            + CONVERT(CHAR(8), @inFechaOperacion, 112);

        SELECT @CantMovimientosCierre = COUNT(*)
        FROM dbo.Movimiento AS M
        WHERE M.ReferenciaOrigen = @ReferenciaOrigen;

        -- Tipos de movimiento automatico del cierre
        SELECT @CantTiposCierre = COUNT(*)
        FROM dbo.TipoMovimiento AS TM
        WHERE (TM.Id = 12 AND TM.Nombre = 'Intereses Mensuales'
               AND TM.Accion = 'Credito')
           OR (TM.Id = 7 AND TM.Nombre = 'Comision Exceso ATM'
               AND TM.Accion = 'Debito')
           OR (TM.Id = 6 AND TM.Nombre = 'Comision Exceso Ventana'
               AND TM.Accion = 'Debito')
           OR (TM.Id = 16 AND TM.Nombre = 'Multa Saldo Minimo'
               AND TM.Accion = 'Debito')
           OR (TM.Id = 11 AND TM.Nombre = 'Cargo Servicio Mensual'
               AND TM.Accion = 'Debito');

        -- Las mismas validaciones de los SP anteriores, en el mismo orden
        SET @outResultCode = CASE
            WHEN @FlagPeriodoCerrado = @true
                THEN 50303  -- quedan movimientos de un periodo ya cerrado
            WHEN @CantidadEstados <> 1
                THEN 50204  -- no hay un unico estado para la fecha
            WHEN @OperacionesATM IS NULL OR @RetirosATM IS NULL
                 OR @OperacionesHumano IS NULL OR @RetirosHumano IS NULL
                THEN 50205  -- contadores sin inicializar
            WHEN @SaldoCuenta <> @SaldoPeriodo
                THEN 50305  -- los saldos no coinciden
            WHEN @CantDuplicados > 0
                THEN 50203  -- un movimiento ya estaba registrado
            WHEN @FlagCierre = @true AND @CantTiposCierre <> 5
                THEN 50306  -- faltan tipos de movimiento del cierre
            WHEN @FlagCierre = @true AND @CantMovimientosCierre > 0
                THEN 50308  -- ya existen movimientos del cierre
            ELSE 0
        END;

        IF @outResultCode <> 0
            RETURN;

        -- Tipo de la comision SINPE y lo enviado por SINPE ese dia antes
        -- de estos movimientos (normalmente nada)
        SELECT @IdTipoComision = TM.Id
        FROM dbo.TipoMovimiento AS TM
        WHERE TM.Id = 10 AND TM.Nombre = 'Comision Sinpe'
          AND TM.Accion = 'Debito';

        SELECT @TotalSinpeAnterior = ISNULL(SUM(M.Monto), 0)
        FROM dbo.Movimiento AS M
        INNER JOIN dbo.EstadoCuenta AS E ON E.Id = M.IdEstadoCuenta
        WHERE E.IdCuenta = @IdCuenta
          AND M.FechaMovimiento = @inFechaOperacion
          AND M.IdTipoMovimiento = 9;


        -- 2. MOVIMIENTOS DEL DIA (lo de sp_AplicarMovimiento), uno por uno
        -- en el orden del XML. Solo se calculan: se registran en el paso 4.

        SET @SaldoActual = @SaldoCuenta;

        SELECT @SecuenciaXml = MIN(MD.Secuencia)
        FROM @MovimientosDia AS MD;

        WHILE @SecuenciaXml IS NOT NULL
        BEGIN
            SELECT @Referencia = MD.ReferenciaOrigen,
                @TipoTexto = MD.TipoMovimiento, @Monto = MD.Monto,
                @Descripcion = MD.Descripcion
            FROM @MovimientosDia AS MD
            WHERE MD.Secuencia = @SecuenciaXml;

            -- Solo movimientos operativos del XML
            SET @IdTipoMovimiento = NULL;
            SET @Accion = NULL;

            SELECT @IdTipoMovimiento = TM.Id, @Accion = TM.Accion,
                @FlagGeneraComprobante = TM.flagGeneraComprobante,
                @NombreTipoMovimiento = TM.Nombre
            FROM dbo.TipoMovimiento AS TM
            WHERE TM.Nombre = @TipoTexto
              AND TM.Id IN (1, 2, 3, 4, 5, 8, 9);

            -- Saldo despues del movimiento y comision si lo enviado por
            -- SINPE en el dia pasa el maximo del tipo de cuenta
            SET @SaldoPrincipal = @SaldoActual
                + CASE WHEN @Accion = 'Credito' THEN @Monto ELSE -@Monto END;

            SET @MontoComision = CASE
                WHEN @IdTipoMovimiento = 9
                 AND @TotalSinpeAnterior + @Monto > @LimiteSinpe
                    THEN @ComisionSinpe
                ELSE 0
            END;

            SET @SaldoFinal = @SaldoPrincipal - @MontoComision;

            -- Las mismas validaciones de sp_AplicarMovimiento, en orden
            SET @CodigoMovimiento = CASE
                WHEN @Monto <= 0 OR LTRIM(RTRIM(@Descripcion)) = ''
                    THEN 50200  -- monto o descripcion invalidos
                WHEN @IdTipoMovimiento IS NULL
                    THEN 50201  -- tipo de movimiento invalido
                WHEN @SaldoPrincipal < 0
                    THEN 50206  -- saldo insuficiente
                WHEN @IdTipoMovimiento = 9
                     AND (@LimiteSinpe IS NULL OR @ComisionSinpe IS NULL)
                    THEN 50207  -- falta la configuracion SINPE
                WHEN @SaldoFinal < 0
                    THEN 50208  -- no alcanza para la comision
                WHEN @MontoComision > 0 AND @IdTipoComision IS NULL
                    THEN 50209  -- no existe el tipo Comision Sinpe
                ELSE 0
            END;

            IF @CodigoMovimiento = 0
            BEGIN
                -- Comprobante (la comision SINPE va en este mismo)
                IF @FlagGeneraComprobante = @true
                BEGIN
                    SET @SecComprobante = @SecComprobante + 1;

                    INSERT INTO @ComprobantesNuevos (SecComprobante, Asunto,
                        TextoEmail)
                    VALUES (@SecComprobante,
                        @NombreTipoMovimiento + N' en la cuenta '
                            + @inNumeroCuenta,
                        dbo.fnTextoComprobante(@NombreDueno, @inNumeroCuenta,
                            @NombreTipoMovimiento, @inFechaOperacion,
                            @Descripcion,
                            CASE WHEN @Accion = 'Debito' THEN -@Monto
                                 ELSE @Monto END,
                            @SaldoPrincipal, @MontoComision, @SaldoFinal,
                            @SimboloMoneda));
                END;

                -- El movimiento y, si hay, la comision SINPE como segundo
                -- movimiento con la misma referencia (sin comprobante)
                SET @Orden = @Orden + 1;

                INSERT INTO @MovimientosNuevos (Orden, IdTipoMovimiento,
                    Monto, Descripcion, SaldoPosterior, ReferenciaOrigen,
                    SecuenciaOrigen, SecComprobante)
                VALUES (@Orden, @IdTipoMovimiento, @Monto, @Descripcion,
                    @SaldoPrincipal, @Referencia, 1,
                    CASE WHEN @FlagGeneraComprobante = @true
                         THEN @SecComprobante END);

                IF @MontoComision > 0
                BEGIN
                    SET @Orden = @Orden + 1;

                    INSERT INTO @MovimientosNuevos (Orden, IdTipoMovimiento,
                        Monto, Descripcion, SaldoPosterior,
                        ReferenciaOrigen, SecuenciaOrigen)
                    VALUES (@Orden, @IdTipoComision, @MontoComision,
                        N'Comision por exceder el limite diario SINPE',
                        @SaldoFinal, @Referencia, 2);
                END;

                -- Saldo, saldo minimo y lo enviado por SINPE en el dia
                SET @SaldoActual = @SaldoFinal;

                IF @SaldoFinal < @SaldoMinimoPeriodo
                    SET @SaldoMinimoPeriodo = @SaldoFinal;

                IF @IdTipoMovimiento = 9
                    SET @TotalSinpeAnterior = @TotalSinpeAnterior + @Monto;

                SET @CantAplicados = @CantAplicados + 1;
            END
            ELSE
                SET @CantRechazados = @CantRechazados + 1;

            UPDATE @MovimientosDia
            SET CodigoResultado = @CodigoMovimiento
            WHERE Secuencia = @SecuenciaXml;

            SELECT @SecuenciaXml = MIN(MD.Secuencia)
            FROM @MovimientosDia AS MD
            WHERE MD.Secuencia > @SecuenciaXml;
        END;

        -- Contadores del estado, de una vez: los mismos tipos
        SELECT
            @CantDepositos = @CantDepositos
              + COUNT(CASE WHEN MN.IdTipoMovimiento IN (1, 2, 8) THEN 1 END),
            @CantRetiros = @CantRetiros
              + COUNT(CASE WHEN MN.IdTipoMovimiento IN (3, 4, 5, 9) THEN 1 END),
            @CantSinpeEntrantes = @CantSinpeEntrantes
              + COUNT(CASE WHEN MN.IdTipoMovimiento = 8 THEN 1 END),
            @CantSinpeSalientes = @CantSinpeSalientes
              + COUNT(CASE WHEN MN.IdTipoMovimiento = 9 THEN 1 END),
            @OperacionesATM = @OperacionesATM
              + COUNT(CASE WHEN MN.IdTipoMovimiento IN (2, 4) THEN 1 END),
            @RetirosATM = @RetirosATM
              + COUNT(CASE WHEN MN.IdTipoMovimiento = 4 THEN 1 END),
            @OperacionesHumano = @OperacionesHumano
              + COUNT(CASE WHEN MN.IdTipoMovimiento IN (1, 5) THEN 1 END),
            @RetirosHumano = @RetirosHumano
              + COUNT(CASE WHEN MN.IdTipoMovimiento = 5 THEN 1 END)
        FROM @MovimientosNuevos AS MN;

        -- 3. CIERRE (lo de sp_CerrarYAbrirEstadoCuenta), con lo que dejaron
        -- los movimientos del dia. Tambien solo se calcula.

        SET @SaldoTrabajo = @SaldoActual;
        SET @SaldoMinimoFinal = @SaldoMinimoPeriodo;

        IF @FlagCierre = @true
        BEGIN
            -- La tasa del catalogo se divide entre 12; NumRetiros es el
            -- limite de operaciones gratis por periodo
            SET @MontoIntereses = ROUND(
                @SaldoMinimoPeriodo * @TasaInteresAnual / 1200.0, 2);

            SET @MontoExcesoATM = CASE
                WHEN @OperacionesATM > @MaxOperacionesATM
                    THEN (@OperacionesATM - @MaxOperacionesATM) * @ComisionATM
                ELSE 0 END;

            SET @MontoExcesoHumano = CASE
                WHEN @OperacionesHumano > @MaxOperacionesHumano
                    THEN (@OperacionesHumano - @MaxOperacionesHumano)
                         * @ComisionHumano
                ELSE 0 END;

            SET @MontoMulta = CASE
                WHEN @SaldoMinimoPeriodo < @SaldoMinimoRequerido
                    THEN @MultaSaldoMin
                ELSE 0 END;

            SET @TotalCargos = @MontoExcesoATM + @MontoExcesoHumano
                + @MontoMulta + @CargoMensual;

            -- No saldos negativos: si no alcanza, no se aplica nada de la
            -- cuenta en el dia 
            IF @SaldoTrabajo + @MontoIntereses < @TotalCargos
            BEGIN
                SET @outResultCode = 50307;
                RETURN;
            END;

            -- Registra en orden los movimientos del cierre
            SET @Secuencia = 1;

            WHILE @Secuencia <= 5
            BEGIN
                SELECT
                    @TipoMovimiento = CASE @Secuencia WHEN 1 THEN 12
                        WHEN 2 THEN 7 WHEN 3 THEN 6 WHEN 4 THEN 16 ELSE 11 END,
                    @MontoMovimiento = CASE @Secuencia
                        WHEN 1 THEN @MontoIntereses WHEN 2 THEN @MontoExcesoATM
                        WHEN 3 THEN @MontoExcesoHumano WHEN 4 THEN @MontoMulta
                        ELSE @CargoMensual END,
                    @DescripcionMovimiento = CASE @Secuencia
                        WHEN 1 THEN N'Intereses mensuales'
                        WHEN 2 THEN N'Comision por exceso de operaciones ATM'
                        WHEN 3 THEN N'Comision por exceso de operaciones '
                                    + N'en ventanilla'
                        WHEN 4 THEN N'Multa por saldo minimo'
                        ELSE N'Cargo por servicio mensual' END;

                IF @MontoMovimiento > 0
                BEGIN
                    IF @Secuencia = 1
                        SET @SaldoTrabajo = @SaldoTrabajo + @MontoMovimiento;
                    ELSE
                        SET @SaldoTrabajo = @SaldoTrabajo - @MontoMovimiento;

                    SET @Orden = @Orden + 1;

                    INSERT INTO @MovimientosNuevos (Orden, IdTipoMovimiento,
                        Monto, Descripcion, SaldoPosterior,
                        ReferenciaOrigen, SecuenciaOrigen)
                    VALUES (@Orden, @TipoMovimiento, @MontoMovimiento,
                        @DescripcionMovimiento, @SaldoTrabajo,
                        @ReferenciaOrigen, @Secuencia);

                    IF @SaldoTrabajo < @SaldoMinimoFinal
                        SET @SaldoMinimoFinal = @SaldoTrabajo;
                END;

                SET @Secuencia = @Secuencia + 1;
            END;

            SET @InteresesAcumulados = @MontoIntereses;
            SET @FechaFinNueva = dbo.fnFechaFinEstadoCuenta(@FechaCreacion,
                @inFechaOperacion);
        END;

        -- Justo antes de la transaccion: lo que se leyo al inicio no cambio
        -- mientras se calculaba
        IF (SELECT C.Saldo FROM dbo.Cuenta AS C
            WHERE C.Id = @IdCuenta) <> @SaldoCuenta
           OR (SELECT COUNT(*) FROM dbo.MovimientoXml AS MX
               WHERE MX.FechaOperacion = @inFechaOperacion
                 AND MX.NumeroCuenta = @inNumeroCuenta
                 AND MX.FlagProcesado = @false) <> @CantPendientes
           OR (@FlagCierre = @true
               AND EXISTS (SELECT 1 FROM dbo.EstadoCuenta AS E
                           WHERE E.IdCuenta = @IdCuenta
                             AND E.FechaInicio = @FechaInicioNueva))
        BEGIN
            SET @outResultCode = 50210;
            RETURN;
        END;

        -- 4. TRANSACCION: solo registra lo calculado, de lo menos a lo mas
        -- importante (comprobante, movimiento, estado y al final el saldo)
        BEGIN TRANSACTION;

        INSERT INTO dbo.Comprobante (IdCuenta, FechaOperacion, EmailDestino,
            Asunto, TextoEmail)
        SELECT @IdCuenta, @inFechaOperacion, @EmailDueno, CN.Asunto,
            CN.TextoEmail
        FROM @ComprobantesNuevos AS CN
        ORDER BY CN.SecComprobante;

        SET @IdUltimoComprobante = SCOPE_IDENTITY();

        -- Cada movimiento con su comprobante: Id = ultimo Id insertado -
        -- cantidad de comprobantes + secuencia 
        INSERT INTO dbo.Movimiento (IdEstadoCuenta, IdTipoMovimiento,
            FechaMovimiento, Monto, Descripcion, SaldoPosterior,
            ReferenciaOrigen, SecuenciaOrigen, IdComprobante)
        SELECT @IdEstadoCuenta, MN.IdTipoMovimiento, @inFechaOperacion,
            MN.Monto, MN.Descripcion, MN.SaldoPosterior, MN.ReferenciaOrigen,
            MN.SecuenciaOrigen,
            @IdUltimoComprobante - @SecComprobante + MN.SecComprobante
        FROM @MovimientosNuevos AS MN
        ORDER BY MN.Orden;

        -- Movimientos del XML procesados (aplicados o rechazados)
        UPDATE MX
        SET FlagProcesado = @true, CodigoResultado = MD.CodigoResultado
        FROM dbo.MovimientoXml AS MX
        INNER JOIN @MovimientosDia AS MD ON MD.IdMovimientoXml = MX.Id;

        UPDATE dbo.EstadoCuenta
        SET SaldoFinal = @SaldoTrabajo, SaldoMinimo = @SaldoMinimoFinal,
            InteresesAcumulados = @InteresesAcumulados,
            CantRetiros = @CantRetiros, CantDepositos = @CantDepositos,
            CantSinpeEntrantes = @CantSinpeEntrantes,
            CantSinpeSalientes = @CantSinpeSalientes,
            CantOperacionesATM = @OperacionesATM,
            CantRetirosATM = @RetirosATM,
            CantOperacionesHumano = @OperacionesHumano,
            CantRetirosHumano = @RetirosHumano
        WHERE Id = @IdEstadoCuenta;

        -- Estado del siguiente periodo, solo si la cuenta cierra hoy: en vez
        -- de un IF, el filtro va en el WHERE
        INSERT INTO dbo.EstadoCuenta (IdCuenta, FechaInicio, FechaFin,
            SaldoInicial, SaldoMinimo, SaldoFinal, InteresesAcumulados,
            CantRetiros, CantDepositos, CantSinpeEntrantes,
            CantSinpeSalientes, CantOperacionesATM, CantRetirosATM,
            CantOperacionesHumano, CantRetirosHumano)
        SELECT @IdCuenta, @FechaInicioNueva, @FechaFinNueva, @SaldoTrabajo,
            @SaldoTrabajo, @SaldoTrabajo, 0, 0, 0, 0, 0, 0, 0, 0, 0
        WHERE @FlagCierre = @true;

        SET @outIdNuevoEstadoCuenta = CASE WHEN @FlagCierre = @true
            THEN SCOPE_IDENTITY() END;

        UPDATE dbo.Cuenta
        SET Saldo = @SaldoTrabajo
        WHERE Id = @IdCuenta;

        COMMIT TRANSACTION;

        SET @outCantAplicados = @CantAplicados;
        SET @outCantRechazados = @CantRechazados;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        INSERT INTO dbo.ErrorBD (NumeroError, Severidad, Estado,
            Procedimiento, Linea, Mensaje)
        VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());

        SET @outResultCode = ERROR_NUMBER();
        SET @outCantAplicados = 0;
        SET @outCantRechazados = 0;
        SET @outIdNuevoEstadoCuenta = NULL;
    END CATCH;
END;
GO