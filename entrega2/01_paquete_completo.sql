-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 2: Componentes PL/SQL (paquete, función, procedimiento y cursores)
-- Archivo: 01_paquete_completo.sql
-- Motor: Oracle Database Free 26ai, cliente SQL Developer.
-- Maria Jazmin Valencia Muñoz y Jhony Alexander Villanueva Ortiz
--
-- Requisito: haber corrido antes 01 DDL, 02 carga y 03 consultas de la Entrega 1.
--
-- Contenido:
--   1. Especificación del paquete pkg_turismouq
--   2. Cuerpo del paquete:
--        fn_valor_estadia                    (valor noche por noche, cruza temporadas)
--        sp_crear_reserva                    (excepciones propias -20002 a -20008)
--        sp_liquidacion_mensual_alojamiento  (cursores explícitos con parámetros)
--   3. Pruebas de cada componente (sirven de evidencia: capturar la salida)
--
-- Convenciones del curso: sp_ (procedimientos), fn_ (funciones), p_ (parámetros),
-- v_ (variables), c_ (cursores y constantes), tipos de parámetros sin tamaño.
--
-- Códigos de error propios (RAISE_APPLICATION_ERROR, rango -20000 a -20999):
--   -20002 checkout anterior o igual al checkin
--   -20003 capacidad excedida
--   -20004 habitación no disponible (cruce con otra reserva activa)
--   -20005 no existe tarifa para una noche de la estadía
--   -20006 el cliente no existe
--   -20007 la habitación no existe
--   -20008 número de huéspedes inválido
--   -20009 mes de liquidación inválido
--   (-20001 lo usa el disparador de solape, archivo 02)
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

--------------------------------------------------------------------------------
-- 1. ESPECIFICACIÓN DEL PAQUETE
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_turismouq IS

    -- Valor de una estadía: suma, noche por noche, la tarifa de la temporada
    -- vigente ese día. Si la estadía cruza dos temporadas, cada noche se cobra
    -- a la tarifa de la temporada a la que pertenece. La noche del check-out
    -- NO se cobra (se cobran las noches desde fecha_in hasta fecha_out - 1).
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- Crea una reserva de una habitación validando fechas, capacidad y
    -- disponibilidad. No hace COMMIT: la transacción la controla quien llama.
    PROCEDURE sp_crear_reserva (
        p_id_cliente     IN cliente.id_cliente%TYPE,
        p_id_habitacion  IN habitacion.id_habitacion%TYPE,
        p_fecha_checkin  IN DATE,
        p_fecha_checkout IN DATE,
        p_num_huespedes  IN NUMBER,
        p_id_reserva     OUT reserva.id_reserva%TYPE
    );

    -- Proceso masivo: liquidación de un mes para todos los alojamientos, o para
    -- uno solo si se pasa p_id_alojamiento. Imprime con DBMS_OUTPUT.
    PROCEDURE sp_liquidacion_mensual_alojamiento (
        p_anio           IN NUMBER,
        p_mes            IN NUMBER,
        p_id_alojamiento IN alojamiento.id_alojamiento%TYPE DEFAULT NULL
    );

END pkg_turismouq;
/
SHOW ERRORS

--------------------------------------------------------------------------------
-- 2. CUERPO DEL PAQUETE
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_turismouq IS

    ----------------------------------------------------------------------------
    -- fn_valor_estadia
    -- Recorre cada noche de la estadía, busca la temporada que la contiene y
    -- suma la tarifa de esa habitación en esa temporada.
    -- Ejemplo: del 12 al 17 de junio de 2025 son 5 noches: 12, 13 y 14 caen en
    -- temporada MEDIA y 15 y 16 en ALTA (la alta empieza el 15), así que el
    -- valor es 3 x tarifa media + 2 x tarifa alta.
    ----------------------------------------------------------------------------
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_total  NUMBER := 0;
        v_noche  DATE;
        v_fin    DATE;
        v_precio tarifa.precio_noche%TYPE;
    BEGIN
        IF p_fecha_in IS NULL OR p_fecha_out IS NULL
           OR TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
            RETURN 0;
        END IF;

        v_noche := TRUNC(p_fecha_in);
        v_fin   := TRUNC(p_fecha_out);

        WHILE v_noche < v_fin LOOP
            BEGIN
                SELECT tf.precio_noche
                  INTO v_precio
                  FROM tarifa tf
                  JOIN temporada t ON t.id_temporada = tf.id_temporada
                 WHERE tf.id_habitacion = p_id_habitacion
                   AND v_noche BETWEEN t.fecha_inicio AND t.fecha_fin;

                v_total := v_total + v_precio;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20005,
                        'No existe tarifa para la habitación ' || p_id_habitacion ||
                        ' en la fecha ' || TO_CHAR(v_noche, 'YYYY-MM-DD'));
            END;
            v_noche := v_noche + 1;
        END LOOP;

        RETURN v_total;
    END fn_valor_estadia;


    ----------------------------------------------------------------------------
    -- sp_crear_reserva
    -- Orden de validaciones: fechas, huéspedes, cliente, habitación, capacidad y
    -- disponibilidad. Solo si todas pasan se insertan RESERVA y RESERVA_HABITACION.
    -- "Ocupada" = otra reserva PENDIENTE, CONFIRMADA o COMPLETADA que cruza el
    -- rango (la noche del check-out queda libre para el siguiente huésped).
    ----------------------------------------------------------------------------
    PROCEDURE sp_crear_reserva (
        p_id_cliente     IN cliente.id_cliente%TYPE,
        p_id_habitacion  IN habitacion.id_habitacion%TYPE,
        p_fecha_checkin  IN DATE,
        p_fecha_checkout IN DATE,
        p_num_huespedes  IN NUMBER,
        p_id_reserva     OUT reserva.id_reserva%TYPE
    ) IS
        v_in        DATE := TRUNC(p_fecha_checkin);
        v_out       DATE := TRUNC(p_fecha_checkout);
        v_capacidad habitacion.capacidad_maxima%TYPE;
        v_existe    NUMBER;
        v_cruces    NUMBER;
    BEGIN
        -- Excepción: checkout anterior o igual al checkin
        IF v_in IS NULL OR v_out IS NULL OR v_out <= v_in THEN
            RAISE_APPLICATION_ERROR(-20002,
                'La fecha de checkout debe ser posterior a la fecha de checkin.');
        END IF;

        IF p_num_huespedes IS NULL OR p_num_huespedes < 1 THEN
            RAISE_APPLICATION_ERROR(-20008,
                'El número de huéspedes debe ser mayor que cero.');
        END IF;

        SELECT COUNT(*) INTO v_existe FROM cliente WHERE id_cliente = p_id_cliente;
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20006, 'El cliente ' || p_id_cliente || ' no existe.');
        END IF;

        BEGIN
            SELECT capacidad_maxima INTO v_capacidad
              FROM habitacion
             WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20007,
                    'La habitación ' || p_id_habitacion || ' no existe.');
        END;

        -- Excepción: capacidad excedida
        IF p_num_huespedes > v_capacidad THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Capacidad excedida: la habitación soporta máximo ' || v_capacidad ||
                ' huéspedes y se pidieron ' || p_num_huespedes || '.');
        END IF;

        -- Excepción: habitación no disponible (cruce de fechas)
        SELECT COUNT(*)
          INTO v_cruces
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = p_id_habitacion
           AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
           AND v_in  < rh.fecha_checkout
           AND v_out > rh.fecha_checkin;

        IF v_cruces > 0 THEN
            RAISE_APPLICATION_ERROR(-20004,
                'La habitación ' || p_id_habitacion ||
                ' no está disponible entre ' || TO_CHAR(v_in, 'YYYY-MM-DD') ||
                ' y ' || TO_CHAR(v_out, 'YYYY-MM-DD') || '.');
        END IF;

        -- Registro de la cabecera y del detalle
        INSERT INTO reserva (fecha_checkin, fecha_checkout, estado, id_cliente)
        VALUES (v_in, v_out, 'CONFIRMADA', p_id_cliente)
        RETURNING id_reserva INTO p_id_reserva;

        INSERT INTO reserva_habitacion (fecha_checkin, fecha_checkout, num_huespedes,
                                        id_reserva, id_habitacion)
        VALUES (v_in, v_out, p_num_huespedes, p_id_reserva, p_id_habitacion);
    END sp_crear_reserva;


    ----------------------------------------------------------------------------
    -- sp_liquidacion_mensual_alojamiento
    -- Proceso masivo con TRES cursores explícitos, todos con parámetros:
    --   c_alojamientos(p_id)            alojamientos a liquidar (todos o uno)
    --   c_estadias(aloj, desde, hasta)  reservas, noches y valor de estadía
    --   c_servicios(aloj, desde, hasta) valor de los servicios contratados
    -- c_alojamientos se recorre con cursor FOR (OPEN/FETCH/CLOSE automáticos);
    -- c_estadias y c_servicios se manejan con OPEN/FETCH/CLOSE explícitos porque
    -- cada uno devuelve una sola fila agregada (por eso un FETCH, sin LOOP).
    -- Nota de rendimiento: fn_valor_estadia se ejecuta una vez por línea de
    -- reserva; es aceptable en un proceso mensual por alojamiento, pero para un
    -- reporte masivo conviene el JOIN + GROUP BY de la consulta 5 de la Entrega 1.
    -- Se liquidan las líneas de reserva CONFIRMADA/COMPLETADA cuyo check-in cae
    -- en el mes (el mismo criterio de la consulta 5 de la Entrega 1).
    ----------------------------------------------------------------------------
    PROCEDURE sp_liquidacion_mensual_alojamiento (
        p_anio           IN NUMBER,
        p_mes            IN NUMBER,
        p_id_alojamiento IN alojamiento.id_alojamiento%TYPE DEFAULT NULL
    ) IS
        c_fmt CONSTANT VARCHAR2(30) := 'FM999G999G999G999';

        CURSOR c_alojamientos (p_id NUMBER) IS
            SELECT a.id_alojamiento, a.nombre_comercial, m.nombre AS municipio
              FROM alojamiento a
              JOIN municipio m ON m.id_municipio = a.id_municipio
             WHERE p_id IS NULL OR a.id_alojamiento = p_id
             ORDER BY m.nombre, a.nombre_comercial;

        CURSOR c_estadias (p_aloj NUMBER, p_desde DATE, p_hasta DATE) IS
            SELECT COUNT(DISTINCT r.id_reserva) AS reservas,
                   NVL(SUM(rh.fecha_checkout - rh.fecha_checkin), 0) AS noches,
                   NVL(SUM(pkg_turismouq.fn_valor_estadia(rh.id_habitacion,
                                                          rh.fecha_checkin,
                                                          rh.fecha_checkout)), 0) AS valor_estadia
              FROM reserva_habitacion rh
              JOIN reserva r    ON r.id_reserva = rh.id_reserva
              JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
             WHERE h.id_alojamiento = p_aloj
               AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
               AND rh.fecha_checkin >= p_desde
               AND rh.fecha_checkin <  p_hasta;

        CURSOR c_servicios (p_aloj NUMBER, p_desde DATE, p_hasta DATE) IS
            SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0) AS valor_servicios
              FROM reserva_servicio rs
              JOIN servicio s ON s.id_servicio = rs.id_servicio
              JOIN reserva r  ON r.id_reserva = rs.id_reserva
             WHERE s.id_alojamiento = p_aloj
               AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
               AND r.fecha_checkin >= p_desde
               AND r.fecha_checkin <  p_hasta;

        v_est        c_estadias%ROWTYPE;
        v_serv       NUMBER;
        v_desde      DATE;
        v_hasta      DATE;
        v_impresos   NUMBER := 0;
        v_t_reservas NUMBER := 0;
        v_t_noches   NUMBER := 0;
        v_t_estadia  NUMBER := 0;
        v_t_serv     NUMBER := 0;
    BEGIN
        IF p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 OR p_anio IS NULL THEN
            RAISE_APPLICATION_ERROR(-20009, 'Mes o año de liquidación inválido.');
        END IF;

        v_desde := TO_DATE(p_anio || '-' || LPAD(p_mes, 2, '0') || '-01', 'YYYY-MM-DD');
        v_hasta := ADD_MONTHS(v_desde, 1);

        DBMS_OUTPUT.PUT_LINE('LIQUIDACIÓN MENSUAL ' || LPAD(p_mes, 2, '0') || '/' || p_anio);
        DBMS_OUTPUT.PUT_LINE(RPAD('Alojamiento', 26) || RPAD('Municipio', 13) ||
                             LPAD('Reservas', 9) || LPAD('Noches', 8) ||
                             LPAD('Estadía', 16) || LPAD('Servicios', 14) || LPAD('Total', 16));
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 102, '-'));

        FOR a IN c_alojamientos(p_id_alojamiento) LOOP
            OPEN c_estadias(a.id_alojamiento, v_desde, v_hasta);
            FETCH c_estadias INTO v_est;
            CLOSE c_estadias;

            OPEN c_servicios(a.id_alojamiento, v_desde, v_hasta);
            FETCH c_servicios INTO v_serv;
            CLOSE c_servicios;

            -- En la liquidación general solo se muestran los alojamientos con movimiento
            IF v_est.reservas > 0 OR p_id_alojamiento IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE(
                    RPAD(a.nombre_comercial, 26) || RPAD(a.municipio, 13) ||
                    LPAD(v_est.reservas, 9) || LPAD(v_est.noches, 8) ||
                    LPAD(TO_CHAR(v_est.valor_estadia, c_fmt), 16) ||
                    LPAD(TO_CHAR(v_serv, c_fmt), 14) ||
                    LPAD(TO_CHAR(v_est.valor_estadia + v_serv, c_fmt), 16));
                v_impresos   := v_impresos + 1;
                v_t_reservas := v_t_reservas + v_est.reservas;
                v_t_noches   := v_t_noches + v_est.noches;
                v_t_estadia  := v_t_estadia + v_est.valor_estadia;
                v_t_serv     := v_t_serv + v_serv;
            END IF;
        END LOOP;

        IF v_impresos = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Sin alojamientos o movimientos para el período pedido.');
        ELSE
            DBMS_OUTPUT.PUT_LINE(RPAD('-', 102, '-'));
            DBMS_OUTPUT.PUT_LINE(
                RPAD('TOTAL (' || v_impresos || ' alojamientos)', 39) ||
                LPAD(v_t_reservas, 9) || LPAD(v_t_noches, 8) ||
                LPAD(TO_CHAR(v_t_estadia, c_fmt), 16) ||
                LPAD(TO_CHAR(v_t_serv, c_fmt), 14) ||
                LPAD(TO_CHAR(v_t_estadia + v_t_serv, c_fmt), 16));
        END IF;
    END sp_liquidacion_mensual_alojamiento;

END pkg_turismouq;
/
SHOW ERRORS

--------------------------------------------------------------------------------
-- 3. PRUEBAS (evidencia). Capturar la pestaña "Salida DBMS" / "Salida de script".
--------------------------------------------------------------------------------

-- 3.1 fn_valor_estadia: estadía que cruza temporadas (12 al 17 de junio de 2025).
--     Se compara la función (noche por noche) con un cálculo independiente por
--     SQL (noches por temporada x tarifa). Deben dar lo mismo.
DECLARE
    v_fn  NUMBER;
    v_ref NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 3.1 fn_valor_estadia, habitación 1, del 2025-06-12 al 2025-06-17 ---');
    FOR x IN (SELECT t.nombre, t.nivel, tf.precio_noche,
                     LEAST(DATE '2025-06-17', t.fecha_fin + 1)
                       - GREATEST(DATE '2025-06-12', t.fecha_inicio) AS noches
                FROM tarifa tf
                JOIN temporada t ON t.id_temporada = tf.id_temporada
               WHERE tf.id_habitacion = 1
                 AND t.fecha_inicio < DATE '2025-06-17'
                 AND t.fecha_fin   >= DATE '2025-06-12'
               ORDER BY t.fecha_inicio) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(x.nombre, 28) || RPAD(x.nivel, 7) ||
                             x.noches || ' noches x ' || TO_CHAR(x.precio_noche, 'FM999G999G999'));
    END LOOP;

    v_fn := pkg_turismouq.fn_valor_estadia(1, DATE '2025-06-12', DATE '2025-06-17');
    SELECT SUM((LEAST(DATE '2025-06-17', t.fecha_fin + 1)
                - GREATEST(DATE '2025-06-12', t.fecha_inicio)) * tf.precio_noche)
      INTO v_ref
      FROM tarifa tf
      JOIN temporada t ON t.id_temporada = tf.id_temporada
     WHERE tf.id_habitacion = 1
       AND t.fecha_inicio < DATE '2025-06-17'
       AND t.fecha_fin   >= DATE '2025-06-12';

    DBMS_OUTPUT.PUT_LINE('  Valor con la función : ' || TO_CHAR(v_fn, 'FM999G999G999'));
    DBMS_OUTPUT.PUT_LINE('  Valor por SQL (ref.) : ' || TO_CHAR(v_ref, 'FM999G999G999'));
    DBMS_OUTPUT.PUT_LINE('  Resultado: ' || CASE WHEN v_fn = v_ref THEN 'OK, coinciden' ELSE 'ERROR, no coinciden' END);

    -- Una fecha sin temporada definida debe fallar con -20005
    BEGIN
        v_fn := pkg_turismouq.fn_valor_estadia(1, DATE '2027-03-01', DATE '2027-03-03');
        DBMS_OUTPUT.PUT_LINE('  Sin tarifa: ERROR, no lanzó excepción');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  Sin tarifa (esperado -20005): ' || SQLERRM);
    END;
END;
/

-- 3.2 sp_crear_reserva: un caso que funciona y un caso por cada excepción.
--     Todo se deshace con ROLLBACK al final del bloque.
DECLARE
    v_cap  habitacion.capacidad_maxima%TYPE;
    v_hab  NUMBER;
    v_in   DATE;
    v_out  DATE;

    PROCEDURE probar (p_caso VARCHAR2, p_cli NUMBER, p_hab NUMBER,
                      p_in DATE, p_out DATE, p_huespedes NUMBER) IS
        v_id reserva.id_reserva%TYPE;
    BEGIN
        pkg_turismouq.sp_crear_reserva(p_cli, p_hab, p_in, p_out, p_huespedes, v_id);
        DBMS_OUTPUT.PUT_LINE(RPAD(p_caso, 34) || '-> OK, reserva creada con id ' || v_id);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(RPAD(p_caso, 34) || '-> ' || SQLERRM);
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 3.2 sp_crear_reserva ---');
    SELECT capacidad_maxima INTO v_cap FROM habitacion WHERE id_habitacion = 1;

    -- Una reserva CONFIRMADA real, para forzar el choque de fechas
    SELECT id_habitacion, fecha_checkin, fecha_checkout
      INTO v_hab, v_in, v_out
      FROM (SELECT rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout
              FROM reserva_habitacion rh
              JOIN reserva r ON r.id_reserva = rh.id_reserva
             WHERE r.estado = 'CONFIRMADA'
             ORDER BY rh.id_reserva_habitacion)
     WHERE ROWNUM = 1;

    probar('Reserva válida (2027-02)',       1, 1, DATE '2027-02-01', DATE '2027-02-05', 1);
    probar('Checkout = checkin (-20002)',    1, 1, DATE '2027-03-01', DATE '2027-03-01', 1);
    probar('Checkout < checkin (-20002)',    1, 1, DATE '2027-03-05', DATE '2027-03-01', 1);
    probar('Capacidad excedida (-20003)',    1, 1, DATE '2027-04-01', DATE '2027-04-03', v_cap + 1);
    probar('No disponible (-20004), hab ' || v_hab, 1, v_hab, v_in, v_out, 1);
    probar('Cliente inexistente (-20006)', 999999, 1, DATE '2027-05-01', DATE '2027-05-03', 1);
    probar('Habitación inexistente (-20007)', 1, 999999, DATE '2027-05-01', DATE '2027-05-03', 1);
    probar('Huéspedes inválidos (-20008)',   1, 1, DATE '2027-05-01', DATE '2027-05-03', 0);

    ROLLBACK;
END;
/

-- 3.3 Cursores: liquidación de un alojamiento y de todos.
--     La liquidación del alojamiento 15 para junio de 2025 debe coincidir con su
--     fila en la consulta 5 de la Entrega 1 (reservas, noches y valor de estadía).
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 3.3a Liquidación junio 2025, alojamiento 15 ---');
    pkg_turismouq.sp_liquidacion_mensual_alojamiento(2025, 6, 15);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- 3.3b Liquidación diciembre 2025, todos los alojamientos ---');
    pkg_turismouq.sp_liquidacion_mensual_alojamiento(2025, 12);
END;
/

ROLLBACK;


