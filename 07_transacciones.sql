-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 3: Transacciones (reserva + pago atómicos con SAVEPOINT)
-- Archivo: 01_transacciones_savepoint.sql
-- Motor: Oracle Database Free | Cliente: Oracle SQL Developer (F5 = Ejecutar script)
-- Conexión: Proyecto (usuario TURISMOUQ)
--
-- Requisito: haber corrido la Entrega 1 y la Entrega 2 (usa pkg_turismouq).
--
-- Contenido:
--   1. sp_reservar_y_pagar: registra la reserva y su pago como una sola unidad
--   2. Pruebas (evidencia): caso exitoso, rollback PARCIAL y rollback TOTAL
--   3. Limpieza de los datos de prueba
--
-- Regla de negocio de la transacción:
--   Una reserva nunca queda CONFIRMADA sin su pago EXITOSO.
--   * Si falla la reserva (fechas, capacidad, disponibilidad, tarifa) -> se
--     deshace TODO (ROLLBACK) y se vuelve a lanzar el error.
--   * Si la reserva se creó pero falla el pago -> se deshace solo lo posterior
--     al SAVEPOINT (ROLLBACK TO sv_reserva_creada): la reserva se conserva en
--     estado PENDIENTE para que el cliente pueda reintentar el pago.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

--------------------------------------------------------------------------------
-- 1. PROCEDIMIENTO sp_reservar_y_pagar
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
    p_id_cliente     IN  cliente.id_cliente%TYPE,
    p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
    p_fecha_checkin  IN  DATE,
    p_fecha_checkout IN  DATE,
    p_num_huespedes  IN  NUMBER,
    p_metodo         IN  pago.metodo%TYPE,
    p_id_reserva     OUT reserva.id_reserva%TYPE,
    p_id_pago        OUT pago.id_pago%TYPE,
    p_resultado      OUT VARCHAR2
) IS
    v_monto pago.monto%TYPE;
BEGIN
    p_id_reserva := NULL;
    p_id_pago    := NULL;

    -- 1. Reserva: valida fechas, capacidad y disponibilidad (errores -20002 a -20008)
    pkg_turismouq.sp_crear_reserva(p_id_cliente, p_id_habitacion, p_fecha_checkin,
                                   p_fecha_checkout, p_num_huespedes, p_id_reserva);

    -- Mientras no haya pago, la reserva queda PENDIENTE
    UPDATE reserva SET estado = 'PENDIENTE' WHERE id_reserva = p_id_reserva;

    -- 2. Valor a pagar: tarifa de cada noche según su temporada (si falta tarifa: -20005)
    v_monto := pkg_turismouq.fn_valor_estadia(p_id_habitacion, p_fecha_checkin, p_fecha_checkout);

    -- Punto de guardado: lo anterior (la reserva) se conserva si falla lo que sigue
    SAVEPOINT sv_reserva_creada;

    -- 3. Confirmación y pago, que deben ocurrir juntos
    BEGIN
        UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = p_id_reserva;

        INSERT INTO pago (fecha, monto, metodo, estado, id_reserva)
        VALUES (SYSDATE, v_monto, p_metodo, 'EXITOSO', p_id_reserva)
        RETURNING id_pago INTO p_id_pago;

        p_resultado := 'OK: reserva CONFIRMADA y pago EXITOSO por ' || v_monto;
    EXCEPTION
        WHEN OTHERS THEN
            -- Rollback PARCIAL: deshace la confirmación, la reserva sigue PENDIENTE
            ROLLBACK TO sv_reserva_creada;
            p_id_pago   := NULL;
            p_resultado := 'PAGO RECHAZADO, reserva PENDIENTE (' || SUBSTR(SQLERRM, 1, 120) || ')';
    END;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Falló la reserva o su valor: se deshace todo y quien llamó se entera
        ROLLBACK;
        p_id_reserva := NULL;
        p_id_pago    := NULL;
        RAISE;
END sp_reservar_y_pagar;
/
SHOW ERRORS

--------------------------------------------------------------------------------
-- 2. PRUEBAS (evidencia). Capturar la salida del script.
--    Se usa la habitación 1 en diciembre de 2026 - enero de 2027, el rango que
--    tiene tarifas definidas; el bloque busca por sí solo noches libres.
--------------------------------------------------------------------------------
DECLARE
    v_ini1   DATE;
    v_ini2   DATE;
    v_res1   reserva.id_reserva%TYPE;
    v_pag1   pago.id_pago%TYPE;
    v_res2   reserva.id_reserva%TYPE;
    v_pag2   pago.id_pago%TYPE;
    v_res3   reserva.id_reserva%TYPE;
    v_pag3   pago.id_pago%TYPE;
    v_msg    VARCHAR2(400);
    v_antes  NUMBER;
    v_despues NUMBER;

    -- Primer día libre de la habitación 1 con 3 noches seguidas, desde p_desde
    FUNCTION f_ventana (p_desde DATE) RETURN DATE IS
        v_d DATE := p_desde;
        v_n NUMBER;
    BEGIN
        WHILE v_d <= DATE '2027-01-10' LOOP
            SELECT COUNT(*) INTO v_n
              FROM reserva_habitacion rh
              JOIN reserva r ON r.id_reserva = rh.id_reserva
             WHERE rh.id_habitacion = 1
               AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
               AND v_d < rh.fecha_checkout
               AND v_d + 3 > rh.fecha_checkin;
            IF v_n = 0 THEN
                RETURN v_d;
            END IF;
            v_d := v_d + 1;
        END LOOP;
        RAISE_APPLICATION_ERROR(-20050, 'No hay 3 noches libres en la habitación 1 para la prueba.');
    END f_ventana;

    PROCEDURE sp_estado (p_titulo VARCHAR2, p_reserva NUMBER) IS
        v_estado reserva.estado%TYPE;
        v_pagos  NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_pagos FROM pago WHERE id_reserva = p_reserva;
        BEGIN
            SELECT estado INTO v_estado FROM reserva WHERE id_reserva = p_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_estado := '(no existe)';
        END;
        DBMS_OUTPUT.PUT_LINE('   ' || p_titulo || ': reserva ' || NVL(TO_CHAR(p_reserva), '-') ||
                             ' estado ' || v_estado || ' | pagos registrados: ' || v_pagos);
    END sp_estado;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Prueba 1: reserva + pago exitosos (todo se confirma) ===');
    v_ini1 := f_ventana(DATE '2026-12-02');
    sp_reservar_y_pagar(1, 1, v_ini1, v_ini1 + 3, 1, 'TARJETA_CREDITO', v_res1, v_pag1, v_msg);
    DBMS_OUTPUT.PUT_LINE('   Resultado: ' || v_msg);
    sp_estado('Después', v_res1);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Prueba 2: el pago falla -> ROLLBACK PARCIAL al SAVEPOINT ===');
    DBMS_OUTPUT.PUT_LINE('   (método de pago "CHEQUE": no está permitido, el INSERT en PAGO falla)');
    v_ini2 := f_ventana(v_ini1 + 3);
    sp_reservar_y_pagar(1, 1, v_ini2, v_ini2 + 3, 1, 'CHEQUE', v_res2, v_pag2, v_msg);
    DBMS_OUTPUT.PUT_LINE('   Resultado: ' || v_msg);
    sp_estado('Después', v_res2);
    DBMS_OUTPUT.PUT_LINE('   -> La confirmación se deshizo (PENDIENTE), el pago no existe y la reserva se conservó.');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Prueba 3: la reserva falla -> ROLLBACK TOTAL ===');
    DBMS_OUTPUT.PUT_LINE('   (99 huéspedes: excede la capacidad de la habitación)');
    SELECT COUNT(*) INTO v_antes FROM reserva;
    BEGIN
        sp_reservar_y_pagar(1, 1, v_ini2 + 3, v_ini2 + 6, 99, 'PSE', v_res3, v_pag3, v_msg);
        DBMS_OUTPUT.PUT_LINE('   ERROR: no lanzó la excepción esperada');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Error recibido: ' || SQLERRM);
    END;
    SELECT COUNT(*) INTO v_despues FROM reserva;
    DBMS_OUTPUT.PUT_LINE('   Reservas antes: ' || v_antes || ' | después: ' || v_despues ||
                         CASE WHEN v_antes = v_despues THEN '  (OK, no quedó nada a medias)' ELSE '  (ERROR)' END);

    -- 3. Limpieza de los datos de prueba (orden de llaves foráneas)
    DELETE FROM pago WHERE id_reserva IN (v_res1, v_res2);
    DELETE FROM reserva_habitacion WHERE id_reserva IN (v_res1, v_res2);
    DELETE FROM reserva WHERE id_reserva IN (v_res1, v_res2);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '(datos de prueba eliminados)');
END;
/
