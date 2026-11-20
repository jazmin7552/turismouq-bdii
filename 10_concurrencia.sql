-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 3: Concurrencia - guion del experimento con dos sesiones
-- Archivo: 02_concurrencia_guion.sql
-- Conexión: Proyecto (usuario TURISMOUQ), en DOS hojas de trabajo
--
-- ESTE ARCHIVO NO SE EJECUTA CON F5. Es el guion de las instrucciones que se
-- ejecutan UNA A UNA con Ctrl+Enter, alternando entre las dos sesiones, tal
-- como en clase. De cada paso se toma la captura para el documento del
-- escenario de concurrencia (Word o PDF).
--
-- Preparación (igual que en clase):
--   * Autocommit apagado: Herramientas > Preferencias > Base de datos > Avanzada >
--     "Confirmación automática" sin marcar.
--   * Sesión A = la hoja normal de Proyecto.
--   * Sesión B = hoja no compartida: Ctrl+Shift+N (misma conexión, otra sesión).
--   * En las dos: SET SERVEROUTPUT ON
--
-- Escenario: dos recepcionistas intentan reservar LA MISMA habitación (la 1) en
-- las MISMAS noches (2028-03-10 al 2028-03-13) al mismo tiempo.
--   Cliente 1 lo atiende la sesión A; cliente 2 lo atiende la sesión B.
-- =============================================================================

-- #############################################################################
-- PASO 0 · Comprobación inicial (sesión A)
-- La habitación 1 no debe tener reservas en esas fechas: resultado esperado 0.
-- #############################################################################
SELECT COUNT(*) AS reservas_en_esas_noches
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = 1
   AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
   AND DATE '2028-03-10' < rh.fecha_checkout
   AND DATE '2028-03-13' > rh.fecha_checkin;

-- #############################################################################
-- PARTE 1 · ANTES: SIN BLOQUEO (condición de carrera)
-- sp_crear_reserva valida la disponibilidad y luego inserta, pero NO hace COMMIT.
-- Mientras A no confirme, B no ve la reserva de A y también la encuentra libre.
-- #############################################################################

-- [A1] Sesión A: reserva la habitación 1 para el cliente 1 (sin COMMIT)
DECLARE
    v_id reserva.id_reserva%TYPE;
BEGIN
    pkg_turismouq.sp_crear_reserva(1, 1, DATE '2028-03-10', DATE '2028-03-13', 1, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva creada con id ' || v_id || ' (sin confirmar)');
END;
/
-- Esperado: "Sesión A: reserva creada con id ... (sin confirmar)"

-- [B1] Sesión B: intenta la MISMA habitación en las MISMAS noches para el cliente 2
DECLARE
    v_id reserva.id_reserva%TYPE;
BEGIN
    pkg_turismouq.sp_crear_reserva(2, 1, DATE '2028-03-10', DATE '2028-03-13', 1, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva creada con id ' || v_id || ' (sin confirmar)');
END;
/
-- Esperado: se ejecuta AL INSTANTE y también crea la reserva. No hay bloqueo:
-- cada sesión inserta filas distintas y B no puede ver lo que A no ha confirmado.
-- (Captura: las dos salidas.)

-- [A2] Sesión A:
COMMIT;
-- [B2] Sesión B:
COMMIT;

-- [A3] Sesión A: consulta de verificación del resultado - DOBLE RESERVA
SELECT r.id_reserva, r.id_cliente, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE rh.id_habitacion = 1
   AND rh.fecha_checkin = DATE '2028-03-10';
-- Esperado: 2 filas (cliente 1 y cliente 2): la misma habitación vendida dos
-- veces. Ni la validación del procedimiento ni el disparador lo evitaron,
-- porque cada sesión validó antes de que la otra confirmara.

-- [A4] Sesión A: limpieza antes de la parte 2
DELETE FROM reserva_habitacion
 WHERE id_habitacion = 1 AND fecha_checkin = DATE '2028-03-10' AND fecha_checkout = DATE '2028-03-13';
DELETE FROM reserva
 WHERE id_cliente IN (1, 2) AND fecha_checkin = DATE '2028-03-10' AND fecha_checkout = DATE '2028-03-13';
COMMIT;
-- Esperado: 2 filas y 2 filas eliminadas; el PASO 0 vuelve a dar 0.


-- #############################################################################
-- PARTE 2 · DESPUÉS: CON SELECT ... FOR UPDATE
-- Antes de validar y reservar, cada sesión aparta (bloquea) la fila de la
-- habitación. Quien llega segundo espera hasta que el primero confirme y
-- entonces sí ve su reserva.
-- #############################################################################

-- [A5] Sesión A: aparta la habitación 1
SELECT id_habitacion, numero FROM habitacion WHERE id_habitacion = 1 FOR UPDATE;
-- Esperado: 1 fila. Desde aquí A tiene el candado sobre la fila de la habitación.

-- [B3] Sesión B: pregunta si está libre, sin esperar
SELECT id_habitacion, numero FROM habitacion WHERE id_habitacion = 1 FOR UPDATE NOWAIT;
-- Esperado: ORA-00054: resource busy and acquire with NOWAIT specified
-- (Captura: el BLOQUEO. La habitación está apartada por A.)

-- [B4] Sesión B: ahora espera 5 segundos en la fila
SELECT id_habitacion, numero FROM habitacion WHERE id_habitacion = 1 FOR UPDATE WAIT 5;
-- Esperado: a los 5 segundos ORA-30006: resource busy; acquire with WAIT timeout expired

-- [B5] Sesión B: espera sin límite (aquí se ve el bloqueo real: la hoja queda
-- "ejecutando" y no devuelve nada). NO la detenga; siga con el paso A6.
SELECT id_habitacion, numero FROM habitacion WHERE id_habitacion = 1 FOR UPDATE;
-- Esperado: la sentencia se queda esperando. (Captura: B "ejecutando".)

-- [A6] Sesión A (cambie a su hoja): reserva y confirma
DECLARE
    v_id reserva.id_reserva%TYPE;
BEGIN
    pkg_turismouq.sp_crear_reserva(1, 1, DATE '2028-03-10', DATE '2028-03-13', 1, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva creada con id ' || v_id);
END;
/
COMMIT;
-- Esperado: reserva creada. Al hacer COMMIT se libera el candado y la sentencia
-- de B (paso B5) termina sola, devolviendo la fila.

-- [B6] Sesión B: ya tiene la habitación apartada; ahora intenta reservar
DECLARE
    v_id reserva.id_reserva%TYPE;
BEGIN
    pkg_turismouq.sp_crear_reserva(2, 1, DATE '2028-03-10', DATE '2028-03-13', 1, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva creada con id ' || v_id);
END;
/
-- Esperado: ORA-20004: La habitación 1 no está disponible entre 2028-03-10 y 2028-03-13.
-- B ya ve la reserva confirmada de A. No hay doble reserva.

-- [B7] Sesión B:
ROLLBACK;

-- [A7] Sesión A: verificación final
SELECT r.id_reserva, r.id_cliente, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE rh.id_habitacion = 1
   AND rh.fecha_checkin = DATE '2028-03-10';
-- Esperado: 1 sola fila (cliente 1).

-- [A8] Sesión A: limpieza final
DELETE FROM reserva_habitacion
 WHERE id_habitacion = 1 AND fecha_checkin = DATE '2028-03-10' AND fecha_checkout = DATE '2028-03-13';
DELETE FROM reserva
 WHERE id_cliente IN (1, 2) AND fecha_checkin = DATE '2028-03-10' AND fecha_checkout = DATE '2028-03-13';
COMMIT;


-- =============================================================================
-- COMPARACIÓN para el documento
--   ANTES (sin FOR UPDATE): las dos sesiones validan a la vez, las dos reservan
--     y quedan 2 reservas de la misma habitación en las mismas noches. No hubo
--     ningún bloqueo, porque cada sesión insertó filas distintas.
--   DESPUÉS (con FOR UPDATE sobre la habitación): B se bloquea (ORA-00054 con
--     NOWAIT, ORA-30006 con WAIT 5, o espera sin límite) hasta que A confirma;
--     al continuar, la validación de B ve la reserva de A y la rechaza con -20004.
--     Queda 1 sola reserva.
--   Regla: validar y modificar en la misma transacción exige apartar antes la
--     fila que protege el recurso (aquí, la habitación).
-- =============================================================================
