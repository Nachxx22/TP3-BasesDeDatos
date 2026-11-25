/*
     Toma el XML de operaciones completo y una fecha. Busca el nodo
     FechaOperacion de esa fecha e inserta, en este orden:
        Persona -> Telefono (x2) -> Cuenta -> Beneficiario
        -> Usuario -> UsuarioPuedeVer
     El trigger dbo.tr_Cuenta_AperturaEstadoCuenta abre solo el primer
     estado de cuenta cuando se inserta la Cuenta.
     NO procesa los nodos Movimientos (los aplica sp_ProcesarCuentaDia).
     Si la fecha no tiene nodo FechaOperacion no hace nada y devuelve 0
     (el simulador igual recorre todas las fechas).

   Pasos:
     1. Lee los nodos de la fecha UNA sola vez con nodes() y los pasa a
        tablas variables (sin transaccion).
     2. Valida todo antes de abrir la transaccion: que lo nuevo no exista
        ya, que cada cuenta empiece en saldo 0, y que cada cuenta,
        beneficiario, usuario y permiso apunte a algo que existe en la base
        o que llega ese mismo dia.
     3. Solo si todo esta bien abre UNA transaccion, que solo inserta (en el
        orden de las llaves foraneas): o entra todo el dia o no entra nada.
        Ahi mismo marca el dia como hecho en dbo.ControlSimulacion
        (FlagAltasProcesadas): si la insercion se deshace, la marca tampoco
        queda, asi una reanudacion de la simulacion nunca repite ni salta
        este paso. Si no existe la fila de control de esa fecha (por
        ejemplo en Pruebas_AltasDia.sql), el UPDATE no cambia nada.
   No llama a otros SP. Los errores se guardan en dbo.ErrorBD desde aqui.

   Codigos de salida (@outResultCode):
     0      OK
     50400  XML nulo
     50401  fecha nula
     50410  una persona ya existe
     50411  una persona no trae sus dos telefonos
     50412  una cuenta ya existe, no empieza en saldo 0 o su dueno no existe
     50413  un beneficiario apunta a una cuenta o a una persona que no existe
     50414  un usuario ya existe o su persona no existe
     50415  un permiso apunta a un usuario o a una cuenta que no existe
     50000  error de SQL (algo repetido en el mismo dia, CHECK, FK...).
            Detalle en dbo.ErrorBD

   Ejemplo de ejecucion:
     DECLARE @x XML = N'<Operaciones>...</Operaciones>';
     DECLARE @r INT;
     EXEC dbo.sp_CargarAltasDia
          @inXml = @x,
          @inFecha = '2026-03-01',
          @outResultCode = @r OUTPUT;
     SELECT @r;
*/

USE CuentaAhorrosTP2;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CargarAltasDia
    @inXml          XML,
    @inFecha        DATE,
    @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Constantes
    DECLARE @true BIT = 1;

    -- Variables
    DECLARE @fechaTexto VARCHAR(10);
    DECLARE @cantNodos INT = 0;

    -- Nodos de la fecha, leidos una sola vez (Sec conserva el orden del XML)
    DECLARE @personas TABLE (
        Sec                     INT IDENTITY(1,1) PRIMARY KEY,
        IdTipoDocuIdentidad     INT,
        Nombre                  VARCHAR(64),
        ValorDocumentoIdentidad VARCHAR(32),
        FechaNacimiento         DATE,
        Email                   VARCHAR(128),
        Telefono1               VARCHAR(16),
        Telefono2               VARCHAR(16)
    );

    DECLARE @cuentas TABLE (
        Sec                INT IDENTITY(1,1) PRIMARY KEY,
        ValorDocCliente    VARCHAR(32),
        IdTipoCuentaAhorro INT,
        NumeroCuenta       VARCHAR(16),
        FechaCreacion      DATE,
        Saldo              DECIMAL(18,2)
    );

    DECLARE @beneficiarios TABLE (
        Sec                  INT IDENTITY(1,1) PRIMARY KEY,
        NumeroCuenta         VARCHAR(16),
        ValorDocBeneficiario VARCHAR(32),
        IdParentezco         INT,
        Porcentaje           INT
    );

    DECLARE @usuarios TABLE (
        Sec             INT IDENTITY(1,1) PRIMARY KEY,
        NombreUsuario   VARCHAR(64),
        Clave           VARCHAR(128),
        EsAdministrador BIT,
        ValorDocPersona VARCHAR(32)
    );

    DECLARE @puedeVer TABLE (
        Sec           INT IDENTITY(1,1) PRIMARY KEY,
        NombreUsuario VARCHAR(64),
        NumeroCuenta  VARCHAR(16)
    );

    SET @outResultCode = 0;

    -- Validar parametros
    IF (@inXml IS NULL)
    BEGIN
        SET @outResultCode = 50400;
        RETURN;
    END;

    IF (@inFecha IS NULL)
    BEGIN
        SET @outResultCode = 50401;
        RETURN;
    END;

    SET @fechaTexto = CONVERT(VARCHAR(10), @inFecha, 23);  -- yyyy-mm-dd

    BEGIN TRY
        -- 1. LECTURA DEL XML: cada tipo de nodo de la fecha, una sola vez
        INSERT INTO @personas (IdTipoDocuIdentidad, Nombre,
            ValorDocumentoIdentidad, FechaNacimiento, Email, Telefono1,
            Telefono2)
        SELECT
            T.Nodo.value('@TipoDocuIdentidad', 'INT'),
            T.Nodo.value('@Nombre', 'VARCHAR(64)'),
            T.Nodo.value('@ValorDocumentoIdentidad', 'VARCHAR(32)'),
            T.Nodo.value('@FechaNacimiento', 'DATE'),
            T.Nodo.value('@Email', 'VARCHAR(128)'),
            T.Nodo.value('@telefono1', 'VARCHAR(16)'),
            T.Nodo.value('@telefono2', 'VARCHAR(16)')
        FROM @inXml.nodes(
            '/Operaciones/FechaOperacion[@Fecha=sql:variable("@fechaTexto")]/Persona'
        ) AS T(Nodo);

        SET @cantNodos = @cantNodos + @@ROWCOUNT;

        INSERT INTO @cuentas (ValorDocCliente, IdTipoCuentaAhorro,
            NumeroCuenta, FechaCreacion, Saldo)
        SELECT
            T.Nodo.value('@ValorDocumentoIdentidadDelCliente', 'VARCHAR(32)'),
            T.Nodo.value('@TipoCuentaId', 'INT'),
            T.Nodo.value('@NumeroCuenta', 'VARCHAR(16)'),
            T.Nodo.value('@FechaCreacion', 'DATE'),
            T.Nodo.value('@Saldo', 'DECIMAL(18,2)')
        FROM @inXml.nodes(
            '/Operaciones/FechaOperacion[@Fecha=sql:variable("@fechaTexto")]/Cuenta'
        ) AS T(Nodo);

        SET @cantNodos = @cantNodos + @@ROWCOUNT;

        INSERT INTO @beneficiarios (NumeroCuenta, ValorDocBeneficiario,
            IdParentezco, Porcentaje)
        SELECT
            T.Nodo.value('@NumeroCuenta', 'VARCHAR(16)'),
            T.Nodo.value('@ValorDocumentoIdentidadBeneficiario', 'VARCHAR(32)'),
            T.Nodo.value('@IdParentezco', 'INT'),
            T.Nodo.value('@Porcentaje', 'INT')
        FROM @inXml.nodes(
            '/Operaciones/FechaOperacion[@Fecha=sql:variable("@fechaTexto")]/Beneficiario'
        ) AS T(Nodo);

        SET @cantNodos = @cantNodos + @@ROWCOUNT;

        INSERT INTO @usuarios (NombreUsuario, Clave, EsAdministrador,
            ValorDocPersona)
        SELECT
            T.Nodo.value('@User', 'VARCHAR(64)'),
            T.Nodo.value('@Pass', 'VARCHAR(128)'),
            T.Nodo.value('@EsAdministrador', 'BIT'),
            T.Nodo.value('@ValorDocId', 'VARCHAR(32)')
        FROM @inXml.nodes(
            '/Operaciones/FechaOperacion[@Fecha=sql:variable("@fechaTexto")]/Usuario'
        ) AS T(Nodo);

        SET @cantNodos = @cantNodos + @@ROWCOUNT;

        INSERT INTO @puedeVer (NombreUsuario, NumeroCuenta)
        SELECT
            T.Nodo.value('@User', 'VARCHAR(64)'),
            T.Nodo.value('@NumeroCuenta', 'VARCHAR(16)')
        FROM @inXml.nodes(
            '/Operaciones/FechaOperacion[@Fecha=sql:variable("@fechaTexto")]/UsuarioPuedeVer'
        ) AS T(Nodo);

        SET @cantNodos = @cantNodos + @@ROWCOUNT;

        -- La fecha no trae personas, cuentas, beneficiarios ni usuarios
        IF (@cantNodos = 0)
        BEGIN
            RETURN;
        END;

        -- 2. VALIDACIONES (sin transaccion), en el orden de los inserts.
        -- Lo que se referencia puede estar en la base o llegar este mismo dia.
        SET @outResultCode = CASE
            -- Las personas son nuevas
            WHEN EXISTS (SELECT 1
                         FROM @personas AS PX
                         INNER JOIN dbo.Persona AS P
                             ON P.ValorDocumentoIdentidad
                                = PX.ValorDocumentoIdentidad)
                THEN 50410
            -- Cada persona trae sus dos telefonos
            WHEN EXISTS (SELECT 1
                         FROM @personas AS PX
                         WHERE PX.Telefono1 IS NULL
                            OR PX.Telefono2 IS NULL)
                THEN 50411
            -- Las cuentas son nuevas, empiezan en saldo 0 y su dueno existe
            WHEN EXISTS (SELECT 1
                         FROM @cuentas AS CX
                         LEFT JOIN dbo.Cuenta AS C
                             ON C.NumeroCuenta = CX.NumeroCuenta
                         LEFT JOIN dbo.Persona AS P
                             ON P.ValorDocumentoIdentidad = CX.ValorDocCliente
                         LEFT JOIN @personas AS PX
                             ON PX.ValorDocumentoIdentidad = CX.ValorDocCliente
                         WHERE CX.Saldo <> 0
                            OR C.Id IS NOT NULL
                            OR (P.Id IS NULL AND PX.Sec IS NULL))
                THEN 50412
            -- La cuenta y la persona de cada beneficiario existen
            WHEN EXISTS (SELECT 1
                         FROM @beneficiarios AS BX
                         LEFT JOIN dbo.Cuenta AS C
                             ON C.NumeroCuenta = BX.NumeroCuenta
                         LEFT JOIN @cuentas AS CX
                             ON CX.NumeroCuenta = BX.NumeroCuenta
                         WHERE C.Id IS NULL
                           AND CX.Sec IS NULL)
              OR EXISTS (SELECT 1
                         FROM @beneficiarios AS BX
                         LEFT JOIN dbo.Persona AS P
                             ON P.ValorDocumentoIdentidad
                                = BX.ValorDocBeneficiario
                         LEFT JOIN @personas AS PX
                             ON PX.ValorDocumentoIdentidad
                                = BX.ValorDocBeneficiario
                         WHERE P.Id IS NULL
                           AND PX.Sec IS NULL)
                THEN 50413
            -- Los usuarios son nuevos y su persona existe
            WHEN EXISTS (SELECT 1
                         FROM @usuarios AS UX
                         LEFT JOIN dbo.Usuario AS U
                             ON U.NombreUsuario = UX.NombreUsuario
                         LEFT JOIN dbo.Persona AS P
                             ON P.ValorDocumentoIdentidad = UX.ValorDocPersona
                         LEFT JOIN @personas AS PX
                             ON PX.ValorDocumentoIdentidad = UX.ValorDocPersona
                         WHERE U.Id IS NOT NULL
                            OR (P.Id IS NULL AND PX.Sec IS NULL))
                THEN 50414
            -- El usuario y la cuenta de cada permiso existen
            WHEN EXISTS (SELECT 1
                         FROM @puedeVer AS VX
                         LEFT JOIN dbo.Usuario AS U
                             ON U.NombreUsuario = VX.NombreUsuario
                         LEFT JOIN @usuarios AS UX
                             ON UX.NombreUsuario = VX.NombreUsuario
                         WHERE U.Id IS NULL
                           AND UX.Sec IS NULL)
              OR EXISTS (SELECT 1
                         FROM @puedeVer AS VX
                         LEFT JOIN dbo.Cuenta AS C
                             ON C.NumeroCuenta = VX.NumeroCuenta
                         LEFT JOIN @cuentas AS CX
                             ON CX.NumeroCuenta = VX.NumeroCuenta
                         WHERE C.Id IS NULL
                           AND CX.Sec IS NULL)
                THEN 50415
            ELSE 0
        END;

        IF (@outResultCode <> 0)
        BEGIN
            RETURN;
        END;

        -- 3. TRANSACCION: solo inserts, en el orden de las llaves foraneas
        BEGIN TRANSACTION;

        -- Marca de control de la simulacion (lo menos importante primero)
        UPDATE dbo.ControlSimulacion
        SET FlagAltasProcesadas = @true
        WHERE FechaOperacion = @inFecha;

        INSERT INTO dbo.Persona (IdTipoDocuIdentidad, Nombre,
            ValorDocumentoIdentidad, FechaNacimiento, Email)
        SELECT PX.IdTipoDocuIdentidad, PX.Nombre, PX.ValorDocumentoIdentidad,
            PX.FechaNacimiento, PX.Email
        FROM @personas AS PX
        ORDER BY PX.Sec;

        -- Telefonos: primero el telefono1 de cada persona y luego el telefono2
        INSERT INTO dbo.Telefono (IdPersona, Numero)
        SELECT P.Id, PX.Telefono1
        FROM @personas AS PX
        INNER JOIN dbo.Persona AS P
            ON P.ValorDocumentoIdentidad = PX.ValorDocumentoIdentidad
        ORDER BY PX.Sec;

        INSERT INTO dbo.Telefono (IdPersona, Numero)
        SELECT P.Id, PX.Telefono2
        FROM @personas AS PX
        INNER JOIN dbo.Persona AS P
            ON P.ValorDocumentoIdentidad = PX.ValorDocumentoIdentidad
        ORDER BY PX.Sec;

        -- Cuentas (el trigger abre el primer estado de cuenta)
        INSERT INTO dbo.Cuenta (IdPersona, IdTipoCuentaAhorro, NumeroCuenta,
            FechaCreacion, Saldo)
        SELECT P.Id, CX.IdTipoCuentaAhorro, CX.NumeroCuenta, CX.FechaCreacion,
            CX.Saldo
        FROM @cuentas AS CX
        INNER JOIN dbo.Persona AS P
            ON P.ValorDocumentoIdentidad = CX.ValorDocCliente
        ORDER BY CX.Sec;

        INSERT INTO dbo.Beneficiario (IdCuenta, IdPersona, IdParentezco,
            Porcentaje)
        SELECT C.Id, P.Id, BX.IdParentezco, BX.Porcentaje
        FROM @beneficiarios AS BX
        INNER JOIN dbo.Cuenta AS C
            ON C.NumeroCuenta = BX.NumeroCuenta
        INNER JOIN dbo.Persona AS P
            ON P.ValorDocumentoIdentidad = BX.ValorDocBeneficiario
        ORDER BY BX.Sec;

        INSERT INTO dbo.Usuario (NombreUsuario, Clave, EsAdministrador,
            IdPersona)
        SELECT UX.NombreUsuario, UX.Clave, UX.EsAdministrador, P.Id
        FROM @usuarios AS UX
        INNER JOIN dbo.Persona AS P
            ON P.ValorDocumentoIdentidad = UX.ValorDocPersona
        ORDER BY UX.Sec;

        -- Permisos de visualizacion
        INSERT INTO dbo.UsuarioPuedeVer (IdUsuario, IdCuenta)
        SELECT U.Id, C.Id
        FROM @puedeVer AS VX
        INNER JOIN dbo.Usuario AS U
            ON U.NombreUsuario = VX.NombreUsuario
        INNER JOIN dbo.Cuenta AS C
            ON C.NumeroCuenta = VX.NumeroCuenta
        ORDER BY VX.Sec;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

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