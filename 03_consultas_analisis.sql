--------------------------------------------------------------------------------
-- TurismoUQ - Entrega 1 - Consultas de análisis
-- Bases de Datos II - Universidad del Quindío
-- Motor: Oracle XE 21c  |  Cliente: Oracle SQL Developer
--
-- Orden de ejecución: 01 DDL, 02 carga de datos, 03 este script.
-- En SQL Developer: abrir el archivo y ejecutar con F5 (Run Script); cada
-- resultado sale en la pestaña "Script Output"/"Resultados de la consulta".
-- Para ejecutar UNA consulta, seleccionarla y presionar Ctrl+Enter.
--
-- Cómo calculamos el ingreso:
-- La tabla RESERVA no guarda el valor. Para cada línea de RESERVA_HABITACION el
-- valor se calcula noche por noche con la tarifa de la temporada que cubre cada
-- noche (la misma idea de fn_valor_estadia, Entrega 2). Para una línea y una
-- temporada que se cruzan:
--     noches en esa temporada = LEAST(checkout, fecha_fin + 1)
--                               - GREATEST(checkin, fecha_inicio)
--     ingreso = noches en esa temporada x precio_noche (TARIFA de la habitación)
-- Así una estadía que atraviesa dos temporadas se parte en dos filas y cada
-- noche se cobra a su tarifa. Solo se cuentan reservas CONFIRMADA y COMPLETADA.
-- "Ingreso" aquí es el de las habitaciones (no incluye servicios) y se asigna al
-- mes en que empieza la línea (check-in).
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- CONSULTA 1. Ocupación por municipio y mes (PIVOT)
-- Noches ocupadas en 2025 por municipio, con los meses como columnas.
-- Cada noche se asigna al mes en que realmente ocurre (una estadía del 30 de
-- junio al 2 de julio cuenta 1 noche en junio y 1 en julio). Para eso se
-- "expande" cada línea en una fila por noche con un generador de números.
--------------------------------------------------------------------------------
SELECT *
FROM (
    SELECT m.nombre AS municipio,
           TO_CHAR(rh.fecha_checkin + n.dia, 'MM') AS mes,
           1 AS noches
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    JOIN municipio m ON m.id_municipio = a.id_municipio
    JOIN (SELECT LEVEL - 1 AS dia FROM dual CONNECT BY LEVEL <= 31) n
         ON n.dia < rh.fecha_checkout - rh.fecha_checkin
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
      AND rh.fecha_checkin + n.dia >= DATE '2025-01-01'
      AND rh.fecha_checkin + n.dia <  DATE '2026-01-01'
)
PIVOT (
    SUM(noches)
    FOR mes IN ('01' AS ene, '02' AS feb, '03' AS mar, '04' AS abr,
                '05' AS may, '06' AS jun, '07' AS jul, '08' AS ago,
                '09' AS sep, '10' AS oct, '11' AS nov, '12' AS dic)
)
ORDER BY municipio;


--------------------------------------------------------------------------------
-- CONSULTA 2. Ingresos por municipio, tipo de alojamiento y temporada
--             (CUBE con GROUPING)
-- CUBE saca el detalle y los subtotales de todas las combinaciones. Con ROLLUP
-- solo saldrían los subtotales en orden jerárquico (municipio > tipo > temporada).
-- GROUPING devuelve 1 cuando la fila es un subtotal de esa columna, y así
-- ponemos 'TOTAL' en vez de dejar el NULL. El ORDER BY usa GROUPING para dejar
-- los subtotales al final de cada grupo y el total general en la última fila.
--------------------------------------------------------------------------------
SELECT DECODE(GROUPING(m.nombre), 1, 'TOTAL', m.nombre) AS municipio,
       DECODE(GROUPING(ta.nombre), 1, 'TOTAL', ta.nombre) AS tipo_alojamiento,
       DECODE(GROUPING(t.nivel), 1, 'TOTAL', t.nivel) AS temporada,
       SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1) - GREATEST(rh.fecha_checkin, t.fecha_inicio))
           * tf.precio_noche) AS ingresos
FROM reserva_habitacion rh
JOIN reserva r ON r.id_reserva = rh.id_reserva
JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                AND t.fecha_fin >= rh.fecha_checkin
JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
              AND tf.id_temporada = t.id_temporada
WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
GROUP BY CUBE (m.nombre, ta.nombre, t.nivel)
ORDER BY GROUPING(m.nombre), m.nombre,
         GROUPING(ta.nombre), ta.nombre,
         GROUPING(t.nivel), t.nivel;


--------------------------------------------------------------------------------
-- CONSULTA 3. Los 3 alojamientos con más ingresos dentro de cada municipio
--             (RANK con PARTITION BY)
-- PARTITION BY municipio hace que el ranking empiece de nuevo en cada municipio.
-- Se calcula en una subconsulta porque no se puede filtrar el RANK en el
-- mismo SELECT donde se calcula.
-- Los municipios que tienen pocos alojamientos salen con menos de 3 filas.
--------------------------------------------------------------------------------
SELECT municipio, alojamiento, ingresos, posicion
FROM (
    SELECT m.nombre AS municipio,
           a.nombre_comercial AS alojamiento,
           SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1) - GREATEST(rh.fecha_checkin, t.fecha_inicio))
               * tf.precio_noche) AS ingresos,
           RANK() OVER (PARTITION BY m.nombre
                        ORDER BY SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1)
                                      - GREATEST(rh.fecha_checkin, t.fecha_inicio))
                                     * tf.precio_noche) DESC) AS posicion
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    JOIN municipio m ON m.id_municipio = a.id_municipio
    JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                    AND t.fecha_fin >= rh.fecha_checkin
    JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
                  AND tf.id_temporada = t.id_temporada
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
    GROUP BY m.nombre, a.id_alojamiento, a.nombre_comercial
)
WHERE posicion <= 3
ORDER BY municipio, posicion;


--------------------------------------------------------------------------------
-- CONSULTA 4. Variación de ingresos mes contra mes (LAG)
-- Primero se suman los ingresos por mes y luego LAG trae el valor del mes
-- anterior para poder restarlos. En el primer mes no hay anterior y sale NULL.
-- Las reservas empiezan en enero de 2024, y los datos de 2026 llegan hasta las
-- reservas futuras ya registradas (CONFIRMADA), por eso los últimos meses bajan.
--------------------------------------------------------------------------------
SELECT mes,
       ingresos,
       LAG(ingresos) OVER (ORDER BY mes) AS ingresos_mes_anterior,
       ingresos - LAG(ingresos) OVER (ORDER BY mes) AS variacion,
       ROUND((ingresos - LAG(ingresos) OVER (ORDER BY mes))
             / LAG(ingresos) OVER (ORDER BY mes) * 100, 2) AS variacion_porcentual
FROM (
    SELECT TO_CHAR(rh.fecha_checkin, 'YYYY-MM') AS mes,
           SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1) - GREATEST(rh.fecha_checkin, t.fecha_inicio))
               * tf.precio_noche) AS ingresos
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                    AND t.fecha_fin >= rh.fecha_checkin
    JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
                  AND tf.id_temporada = t.id_temporada
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
    GROUP BY TO_CHAR(rh.fecha_checkin, 'YYYY-MM')
)
ORDER BY mes;


--------------------------------------------------------------------------------
-- CONSULTA 5. Ingresos por alojamiento en un rango de fechas
--             (consulta parametrizada con variables de enlace)
-- Las variables de enlace se DECLARAN con VARIABLE y se ASIGNAN con EXEC antes de
-- la consulta; así SQL Developer no abre ventanas pidiendo valores. Las fechas
-- se guardan como texto 'AAAA-MM-DD' y la consulta las convierte con TO_DATE.
-- Se filtran las líneas de reserva cuyo check-in cae en el rango. Para probar
-- otro rango basta con cambiar las dos líneas EXEC y volver a ejecutar.
--------------------------------------------------------------------------------
VARIABLE fecha_inicio VARCHAR2(10)
VARIABLE fecha_fin    VARCHAR2(10)
EXEC :fecha_inicio := '2025-06-01'
EXEC :fecha_fin    := '2025-06-30'

SELECT m.nombre AS municipio,
       a.nombre_comercial AS alojamiento,
       COUNT(DISTINCT r.id_reserva) AS reservas,
       SUM(LEAST(rh.fecha_checkout, t.fecha_fin + 1) - GREATEST(rh.fecha_checkin, t.fecha_inicio)) AS noches,
       SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1) - GREATEST(rh.fecha_checkin, t.fecha_inicio))
           * tf.precio_noche) AS ingresos
FROM reserva_habitacion rh
JOIN reserva r ON r.id_reserva = rh.id_reserva
JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                AND t.fecha_fin >= rh.fecha_checkin
JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
              AND tf.id_temporada = t.id_temporada
WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
  AND rh.fecha_checkin BETWEEN TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
                           AND TO_DATE(:fecha_fin, 'YYYY-MM-DD')
GROUP BY m.nombre, a.id_alojamiento, a.nombre_comercial
ORDER BY ingresos DESC;


--------------------------------------------------------------------------------
-- CONSULTA 6. Check-ins y check-outs por mes (UNPIVOT)
-- RESERVA tiene dos columnas de fecha (fecha_checkin y fecha_checkout).
-- UNPIVOT las convierte en filas: cada reserva queda dos veces, una como
-- 'CHECK-IN' y otra como 'CHECK-OUT', y así se pueden contar por mes.
--------------------------------------------------------------------------------
SELECT TO_CHAR(fecha, 'YYYY-MM') AS mes,
       movimiento,
       COUNT(*) AS cantidad
FROM (
    SELECT id_reserva, fecha_checkin, fecha_checkout
    FROM reserva
    WHERE estado IN ('CONFIRMADA', 'COMPLETADA')
)
UNPIVOT (
    fecha FOR movimiento IN (fecha_checkin AS 'CHECK-IN',
                             fecha_checkout AS 'CHECK-OUT')
)
GROUP BY TO_CHAR(fecha, 'YYYY-MM'), movimiento
ORDER BY mes, movimiento;


--------------------------------------------------------------------------------
-- CONSULTA 7 (libre). ¿La calificación que se pone cada alojamiento coincide
--                     con el promedio de sus reseñas?
-- La calificación de ALOJAMIENTO la asigna el mismo alojamiento. Aquí se
-- compara con el promedio real de las reseñas de sus clientes. Una diferencia
-- positiva significa que se da más estrellas de las que recibe.
-- Cada reseña está ligada al alojamiento de la habitación reservada. Solo se
-- toman alojamientos con 20 reseñas o más para que el promedio valga.
--------------------------------------------------------------------------------
SELECT a.nombre_comercial AS alojamiento,
       m.nombre AS municipio,
       a.calificacion AS calificacion_propia,
       ROUND(AVG(rs.calificacion), 2) AS promedio_resenas,
       ROUND(a.calificacion - AVG(rs.calificacion), 2) AS diferencia,
       COUNT(*) AS num_resenas
FROM resena rs
JOIN alojamiento a ON a.id_alojamiento = rs.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
GROUP BY a.id_alojamiento, a.nombre_comercial, m.nombre, a.calificacion
HAVING COUNT(*) >= 20
ORDER BY promedio_resenas DESC;