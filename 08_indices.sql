-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 3: Índices (3 consultas lentas, plan de ejecución antes y después)
-- Archivo: 03_indices.sql
-- Motor: Oracle Database Free | Cliente: Oracle SQL Developer (F5 = Ejecutar script)
-- Conexión: Proyecto (usuario TURISMOUQ)
--
-- Requisito: haber corrido la Entrega 1 (datos de carga).
--
-- Contenido:
--   0. Estado inicial: sin índices propios y con estadísticas al día
--   1. Las 3 consultas lentas (plan ANTES y tiempo)
--   2. Creación de los índices (compuesto, basado en función, simple)
--   3. Las mismas 3 consultas (plan DESPUÉS y tiempo)
--   4. Caso donde el índice NO ayuda (con su explicación)
--
-- Cómo se mide (como en clase):
--   * Plan de ejecución: EXPLAIN PLAN FOR + DBMS_XPLAN.DISPLAY. Se mira la forma
--     del plan (TABLE ACCESS FULL / INDEX RANGE SCAN) y la columna Cost.
--   * Tiempo: sp_medir_consultas ejecuta cada consulta 100 veces y reporta los
--     centisegundos transcurridos. Es un procedimiento auxiliar de este script.
--
-- Las tres consultas salen de operaciones reales de TurismoUQ:
--   C1 Disponibilidad de una habitación en un rango (la usan sp_crear_reserva y
--      el disparador anti-solape cada vez que se reserva).
--   C2 Pagos recibidos en un día (cierre de caja).
--   C3 Reservas de un cliente (historial al atenderlo).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100

--------------------------------------------------------------------------------
-- 0. ESTADO INICIAL
--    Se eliminan los índices de este script (si existen) para poder repetirlo, y
--    se calculan estadísticas: el optimizador decide por costo y las necesita.
--------------------------------------------------------------------------------
DECLARE
    v_n NUMBER;
BEGIN
    FOR i IN (SELECT column_value AS nombre
                FROM TABLE(SYS.ODCIVARCHAR2LIST('IDX_RESHAB_HAB_FECHAS', 'FX_PAGO_DIA',
                                                'IDX_RESERVA_CLIENTE', 'IDX_RESERVA_ESTADO'))) LOOP
        SELECT COUNT(*) INTO v_n FROM user_indexes WHERE index_name = i.nombre;
        IF v_n > 0 THEN
            EXECUTE IMMEDIATE 'DROP INDEX ' || i.nombre;
        END IF;
    END LOOP;

    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
    DBMS_OUTPUT.PUT_LINE('Índices anteriores eliminados y estadísticas calculadas.');
END;
/

-- Tamaño de las tablas y los únicos índices que existen (los de PK y UNIQUE)
SELECT 'RESERVA_HABITACION' AS tabla, COUNT(*) AS filas FROM reserva_habitacion UNION ALL
SELECT 'PAGO', COUNT(*) FROM pago UNION ALL
SELECT 'RESERVA', COUNT(*) FROM reserva;

SELECT table_name, index_name, uniqueness
  FROM user_indexes
 WHERE table_name IN ('RESERVA_HABITACION', 'PAGO', 'RESERVA')
 ORDER BY table_name, index_name;

--------------------------------------------------------------------------------
-- Procedimiento auxiliar de medición: mismas 4 consultas, 100 ejecuciones cada una
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_medir_consultas (p_etapa IN VARCHAR2) IS
    c_veces CONSTANT PLS_INTEGER := 100;
    v_t0    NUMBER;
    v_filas NUMBER;

    PROCEDURE sp_linea (p_consulta VARCHAR2, p_filas NUMBER, p_t0 NUMBER) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(p_etapa, 8) || RPAD(p_consulta, 46) ||
                             LPAD(p_filas, 8) || ' filas' ||
                             LPAD(DBMS_UTILITY.GET_TIME - p_t0, 8) || ' cs (' || c_veces || ' ejecuciones)');
    END sp_linea;
BEGIN
    -- C1: disponibilidad de la habitación 100 entre el 10 y el 15 de junio de 2025
    v_t0 := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. c_veces LOOP
        v_filas := 0;
        FOR r IN (SELECT id_reserva_habitacion, id_reserva, fecha_checkin, fecha_checkout, num_huespedes
                    FROM reserva_habitacion
                   WHERE id_habitacion = 100
                     AND fecha_checkin  < DATE '2025-06-15'
                     AND fecha_checkout > DATE '2025-06-10') LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    sp_linea('C1 disponibilidad de la habitación 100', v_filas, v_t0);

    -- C2: pagos recibidos el 15 de junio de 2025
    v_t0 := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. c_veces LOOP
        v_filas := 0;
        FOR r IN (SELECT id_pago, id_reserva, monto, metodo, estado
                    FROM pago
                   WHERE TRUNC(fecha) = DATE '2025-06-15') LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    sp_linea('C2 pagos del día 2025-06-15', v_filas, v_t0);

    -- C3: reservas del cliente 1500
    v_t0 := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. c_veces LOOP
        v_filas := 0;
        FOR r IN (SELECT id_reserva, fecha_checkin, fecha_checkout, estado
                    FROM reserva
                   WHERE id_cliente = 1500) LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    sp_linea('C3 reservas del cliente 1500', v_filas, v_t0);

    -- C4 (caso donde el índice no ayuda): reservas COMPLETADA
    v_t0 := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. 20 LOOP
        v_filas := 0;
        FOR r IN (SELECT id_reserva, fecha_checkin, fecha_checkout, id_cliente
                    FROM reserva
                   WHERE estado = 'COMPLETADA') LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_etapa, 8) || RPAD('C4 reservas COMPLETADA', 46) ||
                         LPAD(v_filas, 8) || ' filas' ||
                         LPAD(DBMS_UTILITY.GET_TIME - v_t0, 8) || ' cs (20 ejecuciones)');
END sp_medir_consultas;
/
SHOW ERRORS

--------------------------------------------------------------------------------
-- 1. ANTES: plan de ejecución y tiempo de las 3 consultas (sin índices propios)
--------------------------------------------------------------------------------

-- C1 · Disponibilidad de una habitación en un rango de fechas
EXPLAIN PLAN FOR
SELECT id_reserva_habitacion, id_reserva, fecha_checkin, fecha_checkout, num_huespedes
  FROM reserva_habitacion
 WHERE id_habitacion = 100
   AND fecha_checkin  < DATE '2025-06-15'
   AND fecha_checkout > DATE '2025-06-10';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- C2 · Pagos recibidos en un día. TRUNC(fecha) es una función sobre la columna
EXPLAIN PLAN FOR
SELECT id_pago, id_reserva, monto, metodo, estado
  FROM pago
 WHERE TRUNC(fecha) = DATE '2025-06-15';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- C3 · Reservas de un cliente. La llave foránea id_cliente no tiene índice
EXPLAIN PLAN FOR
SELECT id_reserva, fecha_checkin, fecha_checkout, estado
  FROM reserva
 WHERE id_cliente = 1500;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Tiempo ANTES
BEGIN
    sp_medir_consultas('ANTES');
END;
/

--------------------------------------------------------------------------------
-- 2. CREACIÓN DE LOS ÍNDICES
--------------------------------------------------------------------------------

-- Índice COMPUESTO para C1. La columna líder es id_habitacion (igualdad); le siguen
-- las fechas, que se usan en rangos. Con el orden inverso (fechas primero) no
-- serviría para ubicar una habitación concreta.
CREATE INDEX idx_reshab_hab_fechas
    ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout);

-- Índice BASADO EN FUNCIÓN para C2. El filtro aplica TRUNC a la columna, y un índice
-- normal sobre fecha no se podría usar: se indexa la propia expresión.
CREATE INDEX fx_pago_dia
    ON pago (TRUNC(fecha));

-- Índice simple (B-tree) para C3, sobre una llave foránea (Oracle no la indexa solo).
CREATE INDEX idx_reserva_cliente
    ON reserva (id_cliente);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
END;
/

-- Índices creados y sus columnas (la posición 1 es la columna líder)
SELECT i.index_name, i.table_name, c.column_position, c.column_name
  FROM user_indexes i
  LEFT JOIN user_ind_columns c ON c.index_name = i.index_name
 WHERE i.index_name IN ('IDX_RESHAB_HAB_FECHAS', 'FX_PAGO_DIA', 'IDX_RESERVA_CLIENTE')
 ORDER BY i.index_name, c.column_position;

--------------------------------------------------------------------------------
-- 3. DESPUÉS: las mismas 3 consultas, ahora con índices
--------------------------------------------------------------------------------

-- C1
EXPLAIN PLAN FOR
SELECT id_reserva_habitacion, id_reserva, fecha_checkin, fecha_checkout, num_huespedes
  FROM reserva_habitacion
 WHERE id_habitacion = 100
   AND fecha_checkin  < DATE '2025-06-15'
   AND fecha_checkout > DATE '2025-06-10';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- C2
EXPLAIN PLAN FOR
SELECT id_pago, id_reserva, monto, metodo, estado
  FROM pago
 WHERE TRUNC(fecha) = DATE '2025-06-15';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- C3
EXPLAIN PLAN FOR
SELECT id_reserva, fecha_checkin, fecha_checkout, estado
  FROM reserva
 WHERE id_cliente = 1500;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Tiempo DESPUÉS
BEGIN
    sp_medir_consultas('DESPUES');
END;
/

--------------------------------------------------------------------------------
-- 4. CASO DONDE EL ÍNDICE NO AYUDA
--    Reservas en estado COMPLETADA. Se crea un índice sobre estado y la consulta
--    sigue leyendo toda la tabla.
--------------------------------------------------------------------------------

-- 4.1 Por qué: la columna casi no separa las filas (baja selectividad)
SELECT estado,
       COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
  FROM reserva
 GROUP BY estado
 ORDER BY reservas DESC;

-- 4.2 Plan SIN índice sobre estado
EXPLAIN PLAN FOR
SELECT id_reserva, fecha_checkin, fecha_checkout, id_cliente
  FROM reserva
 WHERE estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 4.3 Se crea el índice sobre estado
CREATE INDEX idx_reserva_estado
    ON reserva (estado);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
END;
/

-- 4.4 Plan CON el índice: el optimizador lo ignora y sigue en TABLE ACCESS FULL
EXPLAIN PLAN FOR
SELECT id_reserva, fecha_checkin, fecha_checkout, id_cliente
  FROM reserva
 WHERE estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 4.5 Si se le OBLIGA a usar el índice (hint), el costo SUBE: confirma que el
--     optimizador hizo bien en ignorarlo
EXPLAIN PLAN FOR
SELECT /*+ INDEX(r idx_reserva_estado) */ id_reserva, fecha_checkin, fecha_checkout, id_cliente
  FROM reserva r
 WHERE estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 4.6 Tiempo de la consulta con el índice creado (comparar con la fila C4 de ANTES)
BEGIN
    sp_medir_consultas('CASO4');
END;
/

-- 4.7 El índice no se usa y solo cuesta (espacio y escrituras más lentas): se elimina
DROP INDEX idx_reserva_estado;

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
END;
/

-- Limpieza del procedimiento auxiliar de medición
DROP PROCEDURE sp_medir_consultas;


-- =============================================================================
-- EXPLICACIÓN DEL CASO DONDE EL ÍNDICE NO AYUDA (para el informe)
--   Aproximadamente tres de cada cuatro reservas están COMPLETADA y la columna
--   estado solo tiene 4 valores distintos: su selectividad es muy baja. Para
--   devolver esa gran parte de la tabla con el índice, Oracle tendría que leer
--   el índice y, por cada ROWID, saltar a su bloque de la tabla, una vez por fila.
--   Con tantas filas eso cuesta más que recorrer la tabla de corrido en lectura
--   multibloque, y por eso el optimizador mantiene TABLE ACCESS FULL (4.4) y,
--   al forzar el índice con un hint, el Cost sube (4.5). Regla de clase: pocas
--   filas -> índice; muchas filas -> lectura completa. Un índice así no acelera
--   nada y sí encarece cada INSERT y UPDATE de la columna, por lo que se elimina.
--   (Cuadro de la guía: un bitmap o ningún índice para columnas con pocos valores.)
-- =============================================================================
