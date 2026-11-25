/*
   Verificacion_TP3.sql
   Revisa una instalacion desde cero despues de correr Simulacion_TP3.sql.
   Solo hace consultas: no cambia ningun dato.

   El primer resultado es el resumen por rubro de la rubrica. La columna
   Revision dice OK si el valor obtenido es el esperado, REVISAR si no, e
   INFO cuando el dato solo se muestra.

   Los esperados salen de los XML del profesor (CargarCatalogos.sql y
   Simulacion_TP3.sql):
     - catalogos: 6 tipos de documento, 3 monedas, 8 parentescos,
       4 tipos de cuenta, 18 tipos de movimiento y 8 tipos de bitacora;
     - operaciones: 16 personas (incluye al administrador fquiros),
       10 cuentas, 11 beneficiarios, 11 usuarios, 11 permisos y
       100 movimientos, del 2026-03-01 al 2026-06-30. Los saldos finales de cada cuenta se calcularon aparte con las
   mismas reglas del enunciado.

   Requiere: instalacion completa (pasos del README) y la simulacion corrida.
*/
USE CuentaAhorrosTP2;
GO
SET NOCOUNT ON;

DECLARE @R TABLE (
    Orden INT IDENTITY(1,1) NOT NULL,
    Rubro VARCHAR(40) NOT NULL,
    Dato NVARCHAR(120) NOT NULL,
    Obtenido DECIMAL(18,2) NULL,
    Esperado DECIMAL(18,2) NULL
);

--------------------------------------------------------------------------
-- 1. Creacion de la base: tablas, procedimientos, funcion y trigger
--------------------------------------------------------------------------
DECLARE @Objeto TABLE (
    Nombre SYSNAME NOT NULL,
    Tipo VARCHAR(20) NOT NULL
);

INSERT INTO @Objeto (Nombre, Tipo)
VALUES
    ('TipoDocuIdentidad', 'Tabla'), ('TipoMoneda', 'Tabla'),
    ('Parentezco', 'Tabla'), ('TipoCuentaAhorro', 'Tabla'),
    ('TipoOperacionBitacora', 'Tabla'), ('Persona', 'Tabla'),
    ('Telefono', 'Tabla'), ('Cuenta', 'Tabla'), ('Beneficiario', 'Tabla'),
    ('EstadoCuenta', 'Tabla'), ('Usuario', 'Tabla'),
    ('UsuarioPuedeVer', 'Tabla'), ('Bitacora', 'Tabla'),
    ('TipoMovimiento', 'Tabla'), ('Movimiento', 'Tabla'),
    ('ErrorBD', 'Tabla'), ('CorridaSimulacion', 'Tabla'),
    ('ControlSimulacion', 'Tabla'), ('Comprobante', 'Tabla'),
    ('MovimientoXml', 'Tabla'),
    ('sp_RegistrarBitacora', 'Procedimiento'),
    ('sp_IniciarSesion', 'Procedimiento'),
    ('sp_ListarCuentasUsuario', 'Procedimiento'),
    ('sp_CerrarSesion', 'Procedimiento'),
    ('sp_ListarBeneficiarios', 'Procedimiento'),
    ('sp_AgregarBeneficiario', 'Procedimiento'),
    ('sp_ActualizarBeneficiario', 'Procedimiento'),
    ('sp_EliminarBeneficiario', 'Procedimiento'),
    ('sp_ListarParentezcos', 'Procedimiento'),
    ('sp_ListarTiposDocumento', 'Procedimiento'),
    ('sp_CargarCatalogos', 'Procedimiento'),
    ('sp_CargarAltasDia', 'Procedimiento'),
    ('sp_ProcesarCuentaDia', 'Procedimiento'),
    ('sp_ConsultarEstadosCuenta', 'Procedimiento'),
    ('sp_ConsultarMovimientosEstadoCuenta', 'Procedimiento'),
    ('sp_ConsultarControlSimulacion', 'Procedimiento'),
    ('sp_ConsultarComprobantes', 'Procedimiento'),
    ('sp_RegistrarEnvioComprobante', 'Procedimiento'),
    ('fnTextoMonto', 'Funcion'),
    ('fnTextoComprobante', 'Funcion'),
    ('fnFechaFinEstadoCuenta', 'Funcion'),
    ('tr_Cuenta_AperturaEstadoCuenta', 'Trigger');

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '1 Creacion de la BD', N'Objetos esperados que existen', COUNT(*), 42
FROM @Objeto AS O
WHERE OBJECT_ID(N'dbo.' + O.Nombre) IS NOT NULL;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '1 Creacion de la BD', N'Llaves foraneas (FK)', COUNT(*), NULL
FROM sys.foreign_keys;

--------------------------------------------------------------------------
-- 2. Migracion de catalogos
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Tipos de documento', COUNT(*), 6 FROM dbo.TipoDocuIdentidad;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Monedas', COUNT(*), 3 FROM dbo.TipoMoneda;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Parentescos', COUNT(*), 8 FROM dbo.Parentezco;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Tipos de cuenta', COUNT(*), 4 FROM dbo.TipoCuentaAhorro;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Tipos de movimiento', COUNT(*), 18 FROM dbo.TipoMovimiento;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '2 Catalogos', N'Tipos de operacion de bitacora', COUNT(*), 8
FROM dbo.TipoOperacionBitacora;

--------------------------------------------------------------------------
-- 3. Trigger: cada cuenta abre su primer estado el dia de su creacion
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '3 Trigger', N'Cuentas sin primer estado desde su fecha de creacion', COUNT(*), 0
FROM dbo.Cuenta AS C
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.EstadoCuenta AS E
    WHERE E.IdCuenta = C.Id
        AND E.FechaInicio = C.FechaCreacion
        AND E.SaldoInicial = 0
);

--------------------------------------------------------------------------
-- 4. Proceso masivo (5a): todas las fechas, en orden y una sola vez
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '4 Proceso masivo (5a)', N'Fechas registradas en ControlSimulacion', COUNT(*), 122
FROM dbo.ControlSimulacion;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '4 Proceso masivo (5a)', N'Fechas terminadas', COUNT(*), 122
FROM dbo.ControlSimulacion
WHERE FlagTerminada = 1;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '4 Proceso masivo (5a)', N'Fechas fuera de 2026-03-01 a 2026-06-30', COUNT(*), 0
FROM dbo.ControlSimulacion
WHERE FechaOperacion < '2026-03-01'
    OR FechaOperacion > '2026-06-30';

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '4 Proceso masivo (5a)', N'Corridas que terminaron con error (codigo 2)', COUNT(*), 0
FROM dbo.CorridaSimulacion
WHERE CodigoResultado = 2;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '4 Proceso masivo (5a)', N'Corridas registradas', COUNT(*), NULL
FROM dbo.CorridaSimulacion;

--------------------------------------------------------------------------
-- 5. Altas (5b): personas, cuentas, beneficiarios y usuarios
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Personas (16 del XML, con el administrador)', COUNT(*), 16 FROM dbo.Persona;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Telefonos (2 por persona)', COUNT(*), 32 FROM dbo.Telefono;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Cuentas', COUNT(*), 10 FROM dbo.Cuenta;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Beneficiarios', COUNT(*), 11 FROM dbo.Beneficiario;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Usuarios (11 del XML, con el administrador)', COUNT(*), 11 FROM dbo.Usuario;
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '5 Altas (5b)', N'Permisos UsuarioPuedeVer', COUNT(*), 11 FROM dbo.UsuarioPuedeVer;

--------------------------------------------------------------------------
-- 6. Movimientos y contadores (5c)
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos en total', COUNT(*), 161 FROM dbo.Movimiento;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos del XML aplicados', COUNT(*), 100
FROM dbo.Movimiento
WHERE SecuenciaOrigen = 1
    AND ReferenciaOrigen NOT LIKE 'CIERRE:%';

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos del XML rechazados', ISNULL(SUM(CantMovimientosRechazados), 0), 0
FROM dbo.ControlSimulacion;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Comisiones por exceso de SINPE', COUNT(*), 4
FROM dbo.Movimiento
WHERE IdTipoMovimiento = 10;

-- Cada saldo posterior = saldo posterior anterior de la misma cuenta
-- (0 en el primer movimiento) mas o menos el monto.
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos cuyo saldo no cuadra con el anterior', COUNT(*), 0
FROM dbo.Movimiento AS M
INNER JOIN dbo.EstadoCuenta AS E
    ON E.Id = M.IdEstadoCuenta
INNER JOIN dbo.TipoMovimiento AS T
    ON T.Id = M.IdTipoMovimiento
WHERE M.SaldoPosterior <> ISNULL((
        SELECT MA.SaldoPosterior
        FROM dbo.Movimiento AS MA
        WHERE MA.Id = (
            SELECT MAX(M2.Id)
            FROM dbo.Movimiento AS M2
            INNER JOIN dbo.EstadoCuenta AS E2
                ON E2.Id = M2.IdEstadoCuenta
            WHERE E2.IdCuenta = E.IdCuenta
                AND M2.Id < M.Id
        )
    ), 0)
    + CASE WHEN T.Accion = 'Credito' THEN M.Monto ELSE -M.Monto END;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Cuentas cuyo saldo no es el de su ultimo movimiento', COUNT(*), 0
FROM dbo.Cuenta AS C
WHERE C.Saldo <> ISNULL((
    SELECT M.SaldoPosterior
    FROM dbo.Movimiento AS M
    WHERE M.Id = (
        SELECT MAX(M2.Id)
        FROM dbo.Movimiento AS M2
        INNER JOIN dbo.EstadoCuenta AS E2
            ON E2.Id = M2.IdEstadoCuenta
        WHERE E2.IdCuenta = C.Id
    )
), 0);

-- Saldo final de cada cuenta, calculado aparte desde el XML
DECLARE @SaldoEsperado TABLE (
    NumeroCuenta VARCHAR(16) NOT NULL,
    Saldo DECIMAL(18,2) NOT NULL
);

INSERT INTO @SaldoEsperado (NumeroCuenta, Saldo)
VALUES
    ('11000001', 594249.01), ('11000002', 1863670.06),
    ('11000003', 235740.42), ('11000004', 14684.22),
    ('11000005', 2071540.00), ('21000001', 1516.24),
    ('11000007', 1449066.54), ('11000008', 177753.69),
    ('11000009', 956886.88), ('11000010', 57600.00);

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Cuentas con saldo final distinto al calculado', COUNT(*), 0
FROM @SaldoEsperado AS S
LEFT JOIN dbo.Cuenta AS C
    ON C.NumeroCuenta = S.NumeroCuenta
WHERE C.Id IS NULL
    OR C.Saldo <> S.Saldo;

-- Contadores del estado = cantidad de movimientos de cada tipo en el estado
-- (1 Deposito Ventana, 2 Deposito ATM, 3 Compra, 4 Retiro ATM,
--  5 Retiro Ventana, 8 Deposito Sinpe, 9 Retiro Sinpe)
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Estados con contadores distintos a sus movimientos', COUNT(*), 0
FROM dbo.EstadoCuenta AS E
WHERE ISNULL(E.CantDepositos, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento IN (1, 2, 8))
    OR ISNULL(E.CantRetiros, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento IN (3, 4, 5, 9))
    OR ISNULL(E.CantSinpeEntrantes, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento = 8)
    OR ISNULL(E.CantSinpeSalientes, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento = 9)
    OR ISNULL(E.CantOperacionesATM, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento IN (2, 4))
    OR ISNULL(E.CantRetirosATM, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento = 4)
    OR ISNULL(E.CantOperacionesHumano, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento IN (1, 5))
    OR ISNULL(E.CantRetirosHumano, -1) <> (SELECT COUNT(*) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = E.Id AND M.IdTipoMovimiento = 5);

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos del XML en MovimientoXml', COUNT(*), 100
FROM dbo.MovimientoXml;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos del XML sin procesar', COUNT(*), 0
FROM dbo.MovimientoXml
WHERE FlagProcesado = 0;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos del XML rechazados', COUNT(*), 0
FROM dbo.MovimientoXml
WHERE CodigoResultado <> 0;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Comprobantes generados', COUNT(*), 100 FROM dbo.Comprobante;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos que debian generar comprobante y no lo tienen', COUNT(*), 0
FROM dbo.Movimiento AS M
INNER JOIN dbo.TipoMovimiento AS T
    ON T.Id = M.IdTipoMovimiento
WHERE T.flagGeneraComprobante = 1
    AND M.IdComprobante IS NULL;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Movimientos con comprobante que no debian tenerlo', COUNT(*), 0
FROM dbo.Movimiento AS M
INNER JOIN dbo.TipoMovimiento AS T
    ON T.Id = M.IdTipoMovimiento
WHERE T.flagGeneraComprobante = 0
    AND M.IdComprobante IS NOT NULL;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '6 Movimientos (5c)', N'Comprobantes marcados como enviados', COUNT(*), NULL
FROM dbo.Comprobante
WHERE FlagEnviado = 1;

--------------------------------------------------------------------------
-- 7. Cierre y apertura de estados de cuenta (5d)
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '7 Cierre y apertura (5d)', N'Estados de cuenta', COUNT(*), 37 FROM dbo.EstadoCuenta;

-- Un estado esta cerrado si ya existe el estado que empieza al dia siguiente
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '7 Cierre y apertura (5d)', N'Cierres', COUNT(*), 27
FROM dbo.EstadoCuenta AS E
WHERE EXISTS (
    SELECT 1
    FROM dbo.EstadoCuenta AS N
    WHERE N.IdCuenta = E.IdCuenta
        AND N.FechaInicio = DATEADD(DAY, 1, E.FechaFin)
);

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '7 Cierre y apertura (5d)', N'Cuentas sin exactamente un estado abierto', COUNT(*), 0
FROM dbo.Cuenta AS C
WHERE (
    SELECT COUNT(*)
    FROM dbo.EstadoCuenta AS E
    WHERE E.IdCuenta = C.Id
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.EstadoCuenta AS N
            WHERE N.IdCuenta = E.IdCuenta
                AND N.FechaInicio = DATEADD(DAY, 1, E.FechaFin)
        )
) <> 1;

-- El estado siguiente empieza con el saldo final del cerrado
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '7 Cierre y apertura (5d)', N'Aperturas que no empiezan con el saldo del cierre', COUNT(*), 0
FROM dbo.EstadoCuenta AS E
INNER JOIN dbo.EstadoCuenta AS N
    ON N.IdCuenta = E.IdCuenta
    AND N.FechaInicio = DATEADD(DAY, 1, E.FechaFin)
WHERE N.SaldoInicial <> E.SaldoFinal;

-- Montos del cierre recalculados con las reglas del enunciado
DECLARE @Cierre TABLE (
    IdEstado INT NOT NULL,
    NumeroCuenta VARCHAR(16) NOT NULL,
    FechaCierre DATE NOT NULL,
    IdTipoCuenta INT NOT NULL,
    OpsATM INT NULL,
    OpsVentana INT NULL,
    SaldoMinimoPeriodo DECIMAL(18,2) NOT NULL
);

INSERT INTO @Cierre (
    IdEstado, NumeroCuenta, FechaCierre, IdTipoCuenta,
    OpsATM, OpsVentana, SaldoMinimoPeriodo
)
SELECT
    E.Id, C.NumeroCuenta, E.FechaFin, C.IdTipoCuentaAhorro,
    E.CantOperacionesATM, E.CantOperacionesHumano, E.SaldoInicial
FROM dbo.EstadoCuenta AS E
INNER JOIN dbo.Cuenta AS C
    ON C.Id = E.IdCuenta
WHERE EXISTS (
    SELECT 1
    FROM dbo.EstadoCuenta AS N
    WHERE N.IdCuenta = E.IdCuenta
        AND N.FechaInicio = DATEADD(DAY, 1, E.FechaFin)
);

-- Saldo minimo del periodo ANTES del cierre: el menor entre el saldo
-- inicial y los saldos de los movimientos del periodo
UPDATE X
SET SaldoMinimoPeriodo = MP.SaldoMinimo
FROM @Cierre AS X
INNER JOIN (
    SELECT M.IdEstadoCuenta, MIN(M.SaldoPosterior) AS SaldoMinimo
    FROM dbo.Movimiento AS M
    WHERE M.ReferenciaOrigen NOT LIKE 'CIERRE:%'
    GROUP BY M.IdEstadoCuenta
) AS MP
    ON MP.IdEstadoCuenta = X.IdEstado
WHERE MP.SaldoMinimo < X.SaldoMinimoPeriodo;

DECLARE @CierreRevision TABLE (
    NumeroCuenta VARCHAR(16) NOT NULL,
    FechaCierre DATE NOT NULL,
    SaldoMinimoPeriodo DECIMAL(18,2) NOT NULL,
    InteresEsperado DECIMAL(18,2) NOT NULL,
    InteresAplicado DECIMAL(18,2) NOT NULL,
    ExcesoATMEsperado DECIMAL(18,2) NOT NULL,
    ExcesoATMAplicado DECIMAL(18,2) NOT NULL,
    ExcesoVentanaEsperado DECIMAL(18,2) NOT NULL,
    ExcesoVentanaAplicado DECIMAL(18,2) NOT NULL,
    MultaEsperada DECIMAL(18,2) NOT NULL,
    MultaAplicada DECIMAL(18,2) NOT NULL,
    CargoEsperado DECIMAL(18,2) NOT NULL,
    CargoAplicado DECIMAL(18,2) NOT NULL
);

INSERT INTO @CierreRevision (
    NumeroCuenta, FechaCierre, SaldoMinimoPeriodo,
    InteresEsperado, InteresAplicado,
    ExcesoATMEsperado, ExcesoATMAplicado,
    ExcesoVentanaEsperado, ExcesoVentanaAplicado,
    MultaEsperada, MultaAplicada,
    CargoEsperado, CargoAplicado
)
SELECT
    X.NumeroCuenta,
    X.FechaCierre,
    X.SaldoMinimoPeriodo,
    ROUND(X.SaldoMinimoPeriodo * T.TasaInteresAnual / 1200.0, 2),
    ISNULL((SELECT SUM(M.Monto) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = X.IdEstado AND M.ReferenciaOrigen LIKE 'CIERRE:%'
            AND M.IdTipoMovimiento = 12), 0),
    CASE WHEN X.OpsATM > T.NumRetirosAutomatico
        THEN (X.OpsATM - T.NumRetirosAutomatico) * T.ComisionAutomatico
        ELSE 0 END,
    ISNULL((SELECT SUM(M.Monto) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = X.IdEstado AND M.ReferenciaOrigen LIKE 'CIERRE:%'
            AND M.IdTipoMovimiento = 7), 0),
    CASE WHEN X.OpsVentana > T.NumRetirosHumano
        THEN (X.OpsVentana - T.NumRetirosHumano) * T.ComisionHumano
        ELSE 0 END,
    ISNULL((SELECT SUM(M.Monto) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = X.IdEstado AND M.ReferenciaOrigen LIKE 'CIERRE:%'
            AND M.IdTipoMovimiento = 6), 0),
    CASE WHEN X.SaldoMinimoPeriodo < T.SaldoMinimo
        THEN T.MultaSaldoMin
        ELSE 0 END,
    ISNULL((SELECT SUM(M.Monto) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = X.IdEstado AND M.ReferenciaOrigen LIKE 'CIERRE:%'
            AND M.IdTipoMovimiento = 16), 0),
    T.CargoMensual,
    ISNULL((SELECT SUM(M.Monto) FROM dbo.Movimiento AS M
        WHERE M.IdEstadoCuenta = X.IdEstado AND M.ReferenciaOrigen LIKE 'CIERRE:%'
            AND M.IdTipoMovimiento = 11), 0)
FROM @Cierre AS X
INNER JOIN dbo.TipoCuentaAhorro AS T
    ON T.Id = X.IdTipoCuenta;

INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '7 Cierre y apertura (5d)', N'Cierres con montos distintos a las reglas', COUNT(*), 0
FROM @CierreRevision
WHERE InteresEsperado <> InteresAplicado
    OR ExcesoATMEsperado <> ExcesoATMAplicado
    OR ExcesoVentanaEsperado <> ExcesoVentanaAplicado
    OR MultaEsperada <> MultaAplicada
    OR CargoEsperado <> CargoAplicado;

--------------------------------------------------------------------------
-- 8. Errores
--------------------------------------------------------------------------
INSERT INTO @R (Rubro, Dato, Obtenido, Esperado)
SELECT '8 Errores', N'Filas en ErrorBD', COUNT(*), NULL
FROM dbo.ErrorBD;

--------------------------------------------------------------------------
-- RESULTADOS
--------------------------------------------------------------------------

-- Resultado 1: resumen por rubro
SELECT
    Rubro,
    Dato,
    Obtenido,
    Esperado,
    CASE
        WHEN Esperado IS NULL THEN 'INFO'
        WHEN Obtenido = Esperado THEN 'OK'
        ELSE 'REVISAR'
    END AS Revision
FROM @R
ORDER BY Orden;

-- Resultado 2: objetos que faltan (vacio = todo instalado)
SELECT O.Tipo, O.Nombre AS ObjetoQueFalta
FROM @Objeto AS O
WHERE OBJECT_ID(N'dbo.' + O.Nombre) IS NULL;

-- Resultado 3: detalle de los cierres (27 filas)
SELECT
    NumeroCuenta, FechaCierre, SaldoMinimoPeriodo,
    InteresEsperado, InteresAplicado,
    ExcesoATMEsperado, ExcesoATMAplicado,
    ExcesoVentanaEsperado, ExcesoVentanaAplicado,
    MultaEsperada, MultaAplicada,
    CargoEsperado, CargoAplicado
FROM @CierreRevision
ORDER BY FechaCierre, NumeroCuenta;

-- Resultado 4: saldo final por cuenta
SELECT
    S.NumeroCuenta,
    C.Saldo AS SaldoObtenido,
    S.Saldo AS SaldoEsperado
FROM @SaldoEsperado AS S
LEFT JOIN dbo.Cuenta AS C
    ON C.NumeroCuenta = S.NumeroCuenta
ORDER BY S.NumeroCuenta;

-- Resultado 5: movimientos por tipo
SELECT T.Id, T.Nombre, COUNT(M.Id) AS Cantidad
FROM dbo.TipoMovimiento AS T
LEFT JOIN dbo.Movimiento AS M
    ON M.IdTipoMovimiento = T.Id
GROUP BY T.Id, T.Nombre
ORDER BY T.Id;

-- Resultado 6: corridas de la simulacion
SELECT
    Id, FechaHoraInicio, FechaHoraFin, FechaDesde, FechaHasta,
    CantFechasTerminadas, CodigoResultado, Mensaje
FROM dbo.CorridaSimulacion
ORDER BY Id;

-- Resultado 7: bitacora por tipo de operacion (despues de probar la web)
SELECT T.Id, T.Nombre, COUNT(B.Id) AS Cantidad
FROM dbo.TipoOperacionBitacora AS T
LEFT JOIN dbo.Bitacora AS B
    ON B.IdTipoOperacion = T.Id
GROUP BY T.Id, T.Nombre
ORDER BY T.Id;

-- Resultado 8: ultimos errores registrados
SELECT TOP (20)
    Id, FechaHora, NumeroError, Procedimiento, Linea, Mensaje
FROM dbo.ErrorBD
ORDER BY Id DESC;
GO