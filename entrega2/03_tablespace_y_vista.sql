-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 2: Tablespace del histórico de reservas y vista materializada
-- Archivo: 03_tablespace_y_vista.sql
-- Motor: Oracle XE 21c | Cliente: Oracle SQL Developer
-- Maria Jazmin Valencia Muñoz y Jhony Alexander Villanueva Ortiz
--
-- CÓMO EJECUTARLO (son dos conexiones distintas):
--   PARTE A  -> conexión SYSTEM (el administrador), en la MISMA base de datos
--               donde vive TURISMOUQ.
--   PARTE B  -> conexión Proyecto (usuario TURISMOUQ). 
--   (Crear un tablespace exige privilegios de DBA; por eso va aparte.)
-- =============================================================================


-- #############################################################################
-- PARTE A · EJECUTAR COMO SYSTEM
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

/*
================================================================================
JUSTIFICACIÓN DEL TABLESPACE ts_historico_reservas
Un tablespace es el "edificio" lógico donde viven las tablas; su datafile es la
obra física en disco. Las reservas ya terminadas (COMPLETADA o CANCELADA de años
anteriores) casi no cambian, mientras que las reservas vigentes se insertan y
modifican todo el día. Mezclarlas en USERS es como arrendar el mismo edificio a
inquilinos con necesidades opuestas. Separarlas aporta:
 1. Respaldos distintos: el histórico no cambia, así que se respalda una vez y
    no en cada copia diaria; el respaldo de lo vigente queda pequeño y rápido.
 2. Administración: el histórico puede pasar a READ ONLY (se protege de cambios
    por error) o su datafile reubicarse en un disco más barato y lento, sin
    tocar el tablespace de lo operativo.
 3. Crecimiento controlado: su datafile tiene AUTOEXTEND con MAXSIZE; el
    histórico solo crece y no compite por el espacio con lo transaccional.
 4. Rendimiento: las lecturas pesadas de reportes históricos no comparten
    archivo con las escrituras de las reservas nuevas.
 Se crea SMALLFILE (como en clase) para poder agregar más datafiles después.
================================================================================
*/

DECLARE
    v_n NUMBER;
BEGIN
    -- Seguridad: confirma que se está en la base de datos donde existe TURISMOUQ
    SELECT COUNT(*) INTO v_n FROM dba_users WHERE username = 'TURISMOUQ';
    IF v_n = 0 THEN
        RAISE_APPLICATION_ERROR(-20011,
            'No existe TURISMOUQ en esta base de datos. Conéctate como SYSTEM a la misma base donde está el proyecto.');
    END IF;

    SELECT COUNT(*) INTO v_n FROM dba_tablespaces WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';
    IF v_n = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE SMALLFILE TABLESPACE ts_historico_reservas ' ||
            'DATAFILE ''ts_historico_reservas01.dbf'' SIZE 50M ' ||
            'AUTOEXTEND ON NEXT 10M MAXSIZE 500M';
        DBMS_OUTPUT.PUT_LINE('Tablespace TS_HISTORICO_RESERVAS creado.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('El tablespace TS_HISTORICO_RESERVAS ya existía.');
    END IF;

    -- QUOTA: permiso para que TURISMOUQ ocupe espacio en ese tablespace
    EXECUTE IMMEDIATE 'ALTER USER turismouq QUOTA UNLIMITED ON ts_historico_reservas';
    -- Privilegios para crear y refrescar la vista materializada
    EXECUTE IMMEDIATE 'GRANT CREATE MATERIALIZED VIEW TO turismouq';
    EXECUTE IMMEDIATE 'GRANT CREATE JOB TO turismouq';
    DBMS_OUTPUT.PUT_LINE('Cuota y privilegios otorgados a TURISMOUQ.');
END;
/

-- Evidencia de que existe (captura esto)
SELECT t.tablespace_name, t.status, t.contents, t.bigfile,
       f.file_name, ROUND(f.bytes / 1024 / 1024) AS mb_iniciales, f.autoextensible,
       ROUND(f.maxbytes / 1024 / 1024) AS mb_maximo
  FROM dba_tablespaces t
  JOIN dba_data_files f ON f.tablespace_name = t.tablespace_name
 WHERE t.tablespace_name = 'TS_HISTORICO_RESERVAS';


-- #############################################################################
-- PARTE B · EJECUTAR COMO TURISMOUQ (conexión Proyecto)
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

--------------------------------------------------------------------------------
-- B1. HISTÓRICO DE RESERVAS EN SU PROPIO TABLESPACE
--     Se archiva una copia de las reservas ya terminadas (COMPLETADA o CANCELADA)
--     con salida anterior al 2026-01-01, junto con sus líneas de habitación.
--     Se copia (no se borra de las tablas operativas) para no romper las
--     llaves foráneas de PAGO, RESERVA_SERVICIO y RESENA; en producción, tras
--     validar la copia, el siguiente paso sería retirar esas filas de las tablas
--     operativas.
--------------------------------------------------------------------------------
DECLARE
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM user_tablespaces WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';
    IF v_n = 0 THEN
        RAISE_APPLICATION_ERROR(-20010,
            'Falta el tablespace: ejecuta primero la PARTE A con la conexión SYSTEM.');
    END IF;

    FOR t IN (SELECT table_name FROM user_tables
               WHERE table_name IN ('RESERVA_HABITACION_HISTORICO', 'RESERVA_HISTORICO')
               ORDER BY table_name DESC) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
    END LOOP;
END;
/

CREATE TABLE reserva_historico
    TABLESPACE ts_historico_reservas
AS
SELECT r.id_reserva, r.fecha_checkin, r.fecha_checkout, r.estado, r.id_cliente
  FROM reserva r
 WHERE r.estado IN ('COMPLETADA', 'CANCELADA')
   AND r.fecha_checkout < DATE '2026-01-01';

ALTER TABLE reserva_historico
    ADD CONSTRAINT pk_reserva_historico PRIMARY KEY (id_reserva)
    USING INDEX TABLESPACE ts_historico_reservas;

CREATE TABLE reserva_habitacion_historico
    TABLESPACE ts_historico_reservas
AS
SELECT rh.id_reserva_habitacion, rh.fecha_checkin, rh.fecha_checkout,
       rh.num_huespedes, rh.id_reserva, rh.id_habitacion
  FROM reserva_habitacion rh
 WHERE rh.id_reserva IN (SELECT id_reserva FROM reserva_historico);

ALTER TABLE reserva_habitacion_historico
    ADD CONSTRAINT pk_reshab_historico PRIMARY KEY (id_reserva_habitacion)
    USING INDEX TABLESPACE ts_historico_reservas;

COMMENT ON TABLE reserva_historico IS 'Histórico de reservas terminadas (COMPLETADA/CANCELADA) con salida anterior a 2026-01-01.';
COMMENT ON TABLE reserva_habitacion_historico IS 'Líneas de habitación de las reservas archivadas en RESERVA_HISTORICO.';

-- Evidencia B1: dónde vive cada tabla, qué ocupa y que no se perdió nada
SELECT table_name, tablespace_name
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HABITACION', 'RESERVA_HISTORICO', 'RESERVA_HABITACION_HISTORICO')
 ORDER BY tablespace_name, table_name;

SELECT segment_name, segment_type, tablespace_name, ROUND(bytes / 1024) AS kb
  FROM user_segments
 WHERE tablespace_name = 'TS_HISTORICO_RESERVAS'
 ORDER BY segment_type, segment_name;

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_origen   NUMBER;
    v_hist     NUMBER;
    v_faltan   NUMBER;
    v_sobran   NUMBER;
    v_lineas   NUMBER;
    v_lin_hist NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_origen FROM reserva
     WHERE estado IN ('COMPLETADA', 'CANCELADA') AND fecha_checkout < DATE '2026-01-01';
    SELECT COUNT(*) INTO v_hist FROM reserva_historico;
    SELECT COUNT(*) INTO v_faltan FROM (
        SELECT id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente FROM reserva
         WHERE estado IN ('COMPLETADA', 'CANCELADA') AND fecha_checkout < DATE '2026-01-01'
        MINUS
        SELECT id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente FROM reserva_historico);
    SELECT COUNT(*) INTO v_sobran FROM (
        SELECT id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente FROM reserva_historico
        MINUS
        SELECT id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente FROM reserva);
    SELECT COUNT(*) INTO v_lineas FROM reserva_habitacion
     WHERE id_reserva IN (SELECT id_reserva FROM reserva_historico);
    SELECT COUNT(*) INTO v_lin_hist FROM reserva_habitacion_historico;

    DBMS_OUTPUT.PUT_LINE('--- B1 Verificación del histórico ---');
    DBMS_OUTPUT.PUT_LINE('Reservas que cumplen el criterio : ' || v_origen);
    DBMS_OUTPUT.PUT_LINE('Reservas en RESERVA_HISTORICO    : ' || v_hist);
    DBMS_OUTPUT.PUT_LINE('Faltan (origen MINUS histórico)  : ' || v_faltan);
    DBMS_OUTPUT.PUT_LINE('Sobran (histórico MINUS origen)  : ' || v_sobran);
    DBMS_OUTPUT.PUT_LINE('Líneas de habitación origen/hist.: ' || v_lineas || ' / ' || v_lin_hist);
    DBMS_OUTPUT.PUT_LINE('Resultado: ' || CASE WHEN v_origen = v_hist AND v_faltan = 0 AND v_sobran = 0
                                                 AND v_lineas = v_lin_hist
                                               THEN 'OK, no se perdió ni se inventó ninguna fila'
                                               ELSE 'ERROR' END);
END;
/

--------------------------------------------------------------------------------
-- B2. VISTA MATERIALIZADA DE OCUPACIÓN MENSUAL
--     Una fila por alojamiento y por mes (también los meses sin reservas):
--       noches_ocupadas   noches de habitación vendidas en ese mes
--       noches_disponibles habitaciones x días del mes
--       pct_ocupacion     noches_ocupadas / noches_disponibles
--     Las noches de una estadía que cruza de un mes a otro se reparten en cada
--     mes según la fecha real de cada noche (no se cuentan todas en el mes del
--     check-in). Cuentan las reservas que bloquean habitación: PENDIENTE,
--     CONFIRMADA y COMPLETADA (CANCELADA libera la habitación).
--
--     POLÍTICA DE REFRESCO: REFRESH COMPLETE, programado todos los días a las
--     2:00 a.m. (START WITH / NEXT), y además refrescable a demanda con
--     DBMS_MVIEW.REFRESH.
--      * ¿Por qué no ON COMMIT? Cada reserva nueva haría recalcular el resumen
--        dentro de la misma transacción del cliente y la haría lenta; y el
--        resumen mensual no necesita el dato de este segundo (es para tableros
--        de gerencia, que toleran los datos completos de ayer).
--      * ¿Por qué no FAST? Esta consulta usa COUNT(DISTINCT), JOIN externo y un
--        generador de meses con CONNECT BY; Oracle no puede mantenerla solo con
--        los cambios (no es refrescable FAST). Además un LOG sobre
--        RESERVA_HABITACION penalizaría cada reserva nueva.
--      * ¿Por qué a las 2:00 a.m.? Es la hora de menor carga; el refresco
--        recalcula todo una sola vez y durante el día leer la vista
--        es instantáneo, sin los JOIN ni el CONNECT BY.
--      * Si se necesita un dato fresco (por ejemplo un cierre de mes), se
--        refresca a mano: EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL','C');
--     La desventaja se acepta a conciencia: durante el día la vista puede
--     estar desactualizada hasta el siguiente refresco.
--------------------------------------------------------------------------------
DECLARE
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM user_mviews WHERE mview_name = 'MV_OCUPACION_MENSUAL';
    IF v_n > 0 THEN
        EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
    END IF;
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH TRUNC(SYSDATE) + 1 + 2/24
NEXT TRUNC(SYSDATE) + 1 + 2/24
AS
SELECT b.id_alojamiento,
       b.alojamiento,
       b.municipio,
       b.periodo,
       b.mes_inicio,
       b.habitaciones,
       b.reservas,
       b.noches_ocupadas,
       b.noches_disponibles,
       ROUND(100 * b.noches_ocupadas / b.noches_disponibles, 2) AS pct_ocupacion
  FROM (
        SELECT a.id_alojamiento,
               a.nombre_comercial AS alojamiento,
               mu.nombre          AS municipio,
               TO_CHAR(mm.mes_ini, 'YYYY-MM') AS periodo,
               mm.mes_ini         AS mes_inicio,
               hc.habitaciones,
               COUNT(DISTINCT x.id_reserva) AS reservas,
               NVL(SUM(LEAST(x.fecha_checkout, ADD_MONTHS(mm.mes_ini, 1))
                       - GREATEST(x.fecha_checkin, mm.mes_ini)), 0) AS noches_ocupadas,
               hc.habitaciones * (ADD_MONTHS(mm.mes_ini, 1) - mm.mes_ini) AS noches_disponibles
          FROM (SELECT ADD_MONTHS(TRUNC(rg.f_ini, 'MM'), LEVEL - 1) AS mes_ini
                  FROM (SELECT MIN(fecha_checkin) AS f_ini, MAX(fecha_checkout) AS f_fin
                          FROM reserva_habitacion) rg
               CONNECT BY LEVEL <= MONTHS_BETWEEN(TRUNC(rg.f_fin, 'MM'), TRUNC(rg.f_ini, 'MM')) + 1) mm
         CROSS JOIN alojamiento a
          JOIN municipio mu ON mu.id_municipio = a.id_municipio
          JOIN (SELECT id_alojamiento, COUNT(*) AS habitaciones
                  FROM habitacion
                 GROUP BY id_alojamiento) hc ON hc.id_alojamiento = a.id_alojamiento
          LEFT JOIN (SELECT h.id_alojamiento, rh.id_reserva, rh.fecha_checkin, rh.fecha_checkout
                       FROM reserva_habitacion rh
                       JOIN reserva r    ON r.id_reserva = rh.id_reserva
                       JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
                      WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')) x
                 ON x.id_alojamiento = a.id_alojamiento
                AND x.fecha_checkin  < ADD_MONTHS(mm.mes_ini, 1)
                AND x.fecha_checkout > mm.mes_ini
         GROUP BY a.id_alojamiento, a.nombre_comercial, mu.nombre, mm.mes_ini, hc.habitaciones
       ) b;

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS 'Ocupación mensual por alojamiento. Refresco COMPLETE diario a las 2:00 a.m.';

--------------------------------------------------------------------------------
-- B3. PRUEBAS DE LA VISTA MATERIALIZADA (evidencia)
--------------------------------------------------------------------------------

-- B3.1 Configuración: modo y método de refresco, estado y última foto
SELECT mview_name, build_mode, refresh_mode, refresh_method, staleness,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

-- B3.2 Contenido: los 5 alojamientos más ocupados en diciembre de 2025
SELECT alojamiento, municipio, periodo, habitaciones, reservas,
       noches_ocupadas, noches_disponibles, pct_ocupacion
  FROM (SELECT * FROM mv_ocupacion_mensual WHERE periodo = '2025-12' ORDER BY pct_ocupacion DESC)
 WHERE ROWNUM <= 5;

-- B3.3 Correctitud, estacionalidad y política de refresco
DECLARE
    v_mv      NUMBER;
    v_ref     NUMBER;
    v_max     NUMBER;
    v_filas   NUMBER;
    v_alta    NUMBER;
    v_baja    NUMBER;
    v_hab     NUMBER := 1;
    v_aloj    NUMBER;
    v_ini     DATE;
    v_res     reserva.id_reserva%TYPE;
    v_periodo VARCHAR2(7);
    v_antes   NUMBER;
    v_stale   NUMBER;
    v_despues NUMBER;
    v_final   NUMBER;
    v_encontrada BOOLEAN := FALSE;

    FUNCTION fn_noches (p_aloj NUMBER, p_periodo VARCHAR2) RETURN NUMBER IS
        v_n NUMBER;
    BEGIN
        SELECT noches_ocupadas INTO v_n FROM mv_ocupacion_mensual
         WHERE id_alojamiento = p_aloj AND periodo = p_periodo;
        RETURN v_n;
    END fn_noches;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- B3.3a Correctitud: noches ocupadas en junio de 2025 ---');
    SELECT SUM(noches_ocupadas) INTO v_mv FROM mv_ocupacion_mensual WHERE periodo = '2025-06';
    SELECT SUM(LEAST(rh.fecha_checkout, DATE '2025-07-01') - GREATEST(rh.fecha_checkin, DATE '2025-06-01'))
      INTO v_ref
      FROM reserva_habitacion rh
      JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
       AND rh.fecha_checkin  < DATE '2025-07-01'
       AND rh.fecha_checkout > DATE '2025-06-01';
    DBMS_OUTPUT.PUT_LINE('   Según la vista materializada : ' || v_mv);
    DBMS_OUTPUT.PUT_LINE('   Según consulta directa (ref.): ' || v_ref);
    DBMS_OUTPUT.PUT_LINE('   Resultado: ' || CASE WHEN v_mv = v_ref THEN 'OK, coinciden' ELSE 'ERROR' END);

    SELECT COUNT(*), MAX(pct_ocupacion) INTO v_filas, v_max FROM mv_ocupacion_mensual;
    DBMS_OUTPUT.PUT_LINE('   Filas en la vista: ' || v_filas || ' | ocupación máxima: ' || v_max ||
                         '%  ' || CASE WHEN v_max <= 100 THEN '(OK, nunca supera 100%)' ELSE '(ERROR)' END);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- B3.3b Estacionalidad: ocupación promedio por mes de 2025 ---');
    SELECT ROUND(AVG(CASE WHEN periodo IN ('2025-06', '2025-07', '2025-12') THEN pct_ocupacion END), 1),
           ROUND(AVG(CASE WHEN periodo IN ('2025-02', '2025-11') THEN pct_ocupacion END), 1)
      INTO v_alta, v_baja
      FROM mv_ocupacion_mensual;
    DBMS_OUTPUT.PUT_LINE('   Meses de más demanda (jun, jul, dic): ' || v_alta || '% de ocupación promedio');
    DBMS_OUTPUT.PUT_LINE('   Meses de menos demanda (feb, nov)   : ' || v_baja || '% de ocupación promedio');

    -- Política de refresco: la vista es una "foto" y se pone vieja hasta refrescarla
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- B3.3c La foto se queda vieja hasta refrescar (habitación 1) ---');
    SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = v_hab;

    -- Busca 3 noches libres de la habitación 1 en 2026 usando sp_crear_reserva
    v_ini := DATE '2026-01-05';
    WHILE NOT v_encontrada AND v_ini < DATE '2026-12-01' LOOP
        IF TO_NUMBER(TO_CHAR(v_ini, 'DD')) <= 25 THEN
            BEGIN
                pkg_turismouq.sp_crear_reserva(1, v_hab, v_ini, v_ini + 3, 1, v_res);
                v_encontrada := TRUE;
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE <> -20004 THEN RAISE; END IF;
                    v_ini := v_ini + 1;
            END;
        ELSE
            v_ini := v_ini + 1;
        END IF;
    END LOOP;

    IF NOT v_encontrada THEN
        DBMS_OUTPUT.PUT_LINE('   No se encontró una ventana libre; prueba omitida.');
    ELSE
        v_periodo := TO_CHAR(v_ini, 'YYYY-MM');
        v_antes := fn_noches(v_aloj, v_periodo);
        DBMS_OUTPUT.PUT_LINE('   Alojamiento ' || v_aloj || ', ' || v_periodo ||
                             ': noches ocupadas en la vista = ' || v_antes);

        COMMIT;   -- reserva nueva de 3 noches confirmada
        v_stale := fn_noches(v_aloj, v_periodo);
        DBMS_OUTPUT.PUT_LINE('   Reserva nueva de 3 noches (' || TO_CHAR(v_ini, 'YYYY-MM-DD') ||
                             ') + COMMIT -> la vista sigue en ' || v_stale || '  (foto vieja, esperado)');

        DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
        v_despues := fn_noches(v_aloj, v_periodo);
        DBMS_OUTPUT.PUT_LINE('   Tras DBMS_MVIEW.REFRESH(..., ''C'')            -> la vista pasa a ' || v_despues);
        DBMS_OUTPUT.PUT_LINE('   Resultado: ' || CASE WHEN v_stale = v_antes AND v_despues = v_antes + 3
                                                     THEN 'OK, se actualiza solo al refrescar'
                                                     ELSE 'ERROR' END);

        -- Limpieza: se elimina la reserva de prueba y se vuelve a refrescar
        DELETE FROM reserva_habitacion WHERE id_reserva = v_res;
        DELETE FROM reserva WHERE id_reserva = v_res;
        COMMIT;
        DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
        v_final := fn_noches(v_aloj, v_periodo);
        DBMS_OUTPUT.PUT_LINE('   Reserva de prueba eliminada y vista refrescada -> vuelve a ' || v_final ||
                             CASE WHEN v_final = v_antes THEN '  (OK)' ELSE '  (ERROR)' END);
    END IF;
END;
/

-- B3.4 Estado final de la vista (debe quedar FRESH tras el último refresco)
SELECT mview_name, refresh_method, staleness,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';
 
 
 
