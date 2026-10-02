--------------------------------------------------------------------------------
-- TurismoUQ - Entrega 1 - Consultas de análisis
-- Bases de Datos II - Universidad del Quindío
--
-- Orden de ejecución: 01 DDL, 02 carga de datos, 03 este script.
--
-- Cómo calculamos el ingreso:
-- La tabla RESERVA no guarda el valor, así que para cada línea de
-- RESERVA_HABITACION lo calculamos como:
--     noches (checkout - checkin) x precio_noche de la temporada del check-in
-- Solo se cuentan reservas CONFIRMADA y COMPLETADA.
-- Es una aproximación: si una estadía cruza dos temporadas, aquí se toma la
-- tarifa de la temporada donde empieza. El cálculo exacto noche por noche se
-- hace en fn_valor_estadia (Entrega 2).
--
-- Ojo: las temporadas cargadas empiezan el 16/01/2025, así que las reservas
-- con check-in antes de esa fecha no tienen tarifa y no salen en las consultas
-- de ingresos (2, 3, 4 y 5).
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- CONSULTA 1. Ocupación por municipio y mes (PIVOT)
-- Noches ocupadas en 2025 por municipio, con los meses como columnas.
-- El mes se toma de la fecha de check-in de cada línea de reserva.
--------------------------------------------------------------------------------
SELECT *
FROM (
    SELECT m.nombre AS municipio,
           TO_CHAR(rh.fecha_checkin, 'MM') AS mes,
           rh.fecha_checkout - rh.fecha_checkin AS noches
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    JOIN municipio m ON m.id_municipio = a.id_municipio
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
      AND TO_CHAR(rh.fecha_checkin, 'YYYY') = '2025'
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
-- ponemos 'TOTAL' en vez de dejar el NULL.
--------------------------------------------------------------------------------
SELECT DECODE(GROUPING(m.nombre), 1, 'TOTAL', m.nombre) AS municipio,
       DECODE(GROUPING(ta.nombre), 1, 'TOTAL', ta.nombre) AS tipo_alojamiento,
       DECODE(GROUPING(t.nivel), 1, 'TOTAL', t.nivel) AS temporada,
       SUM((rh.fecha_checkout - rh.fecha_checkin) * tf.precio_noche) AS ingresos
FROM reserva_habitacion rh
JOIN reserva r ON r.id_reserva = rh.id_reserva
JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
JOIN temporada t ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
              AND tf.id_temporada = t.id_temporada
WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
GROUP BY CUBE (m.nombre, ta.nombre, t.nivel)
ORDER BY m.nombre, ta.nombre, t.nivel;


--------------------------------------------------------------------------------
-- CONSULTA 3. Los 3 alojamientos con más ingresos dentro de cada municipio
--             (RANK con PARTITION BY)
-- PARTITION BY municipio hace que el ranking empiece de nuevo en cada municipio.
-- Se calcula en una subconsulta porque no se puede filtrar el RANK en el
-- mismo SELECT donde se calcula.
-- Los municipios que tienen un solo alojamiento salen con una sola fila.
--------------------------------------------------------------------------------
SELECT municipio, alojamiento, ingresos, posicion
FROM (
    SELECT m.nombre AS municipio,
           a.nombre_comercial AS alojamiento,
           SUM((rh.fecha_checkout - rh.fecha_checkin) * tf.precio_noche) AS ingresos,
           RANK() OVER (PARTITION BY m.nombre
                        ORDER BY SUM((rh.fecha_checkout - rh.fecha_checkin) * tf.precio_noche) DESC) AS posicion
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    JOIN municipio m ON m.id_municipio = a.id_municipio
    JOIN temporada t ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
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
-- El primer mes (2025-01) está incompleto porque las tarifas empiezan el 16.
--------------------------------------------------------------------------------
SELECT mes,
       ingresos,
       LAG(ingresos) OVER (ORDER BY mes) AS ingresos_mes_anterior,
       ingresos - LAG(ingresos) OVER (ORDER BY mes) AS variacion,
       ROUND((ingresos - LAG(ingresos) OVER (ORDER BY mes))
             / LAG(ingresos) OVER (ORDER BY mes) * 100, 2) AS variacion_porcentual
FROM (
    SELECT TO_CHAR(rh.fecha_checkin, 'YYYY-MM') AS mes,
           SUM((rh.fecha_checkout - rh.fecha_checkin) * tf.precio_noche) AS ingresos
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN temporada t ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
    JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
                  AND tf.id_temporada = t.id_temporada
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
    GROUP BY TO_CHAR(rh.fecha_checkin, 'YYYY-MM')
)
ORDER BY mes;


--------------------------------------------------------------------------------
-- CONSULTA 5. Ingresos por alojamiento en un rango de fechas
--             (consulta parametrizada con variables de enlace)
-- Se usan las variables :fecha_inicio y :fecha_fin, y se filtran las líneas de
-- reserva cuyo check-in cae en ese rango. Las fechas se escriben como texto
-- 'AAAA-MM-DD' y se convierten con TO_DATE.
-- Al ejecutarla, DBeaver abre una ventana pidiendo los valores de las dos
-- variables. Se escriben entre comillas simples, por ejemplo:
--     :fecha_inicio = '2025-06-01'
--     :fecha_fin    = '2025-06-30'
--------------------------------------------------------------------------------
SELECT m.nombre AS municipio,
       a.nombre_comercial AS alojamiento,
       COUNT(DISTINCT r.id_reserva) AS reservas,
       SUM(rh.fecha_checkout - rh.fecha_checkin) AS noches,
       SUM((rh.fecha_checkout - rh.fecha_checkin) * tf.precio_noche) AS ingresos
FROM reserva_habitacion rh
JOIN reserva r ON r.id_reserva = rh.id_reserva
JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN temporada t ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
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
-- Solo se toman alojamientos con 20 reseñas o más para que el promedio valga.
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