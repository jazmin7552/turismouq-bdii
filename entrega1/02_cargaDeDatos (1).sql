--------------------------------------------------------------------------------
-- TurismoUQ - Entrega 1 - Script de carga de datos
-- Bases de Datos II - Universidad del Quindío
-- Motor: Oracle XE 21c  |  Cliente: Oracle SQL Developer (ejecutar con F5,
-- "Run Script"; también corre en SQL*Plus).
--
-- Orden de ejecución: 01 DDL, 02 este script, 03 consultas.
--
-- El script está dividido en 7 bloques PL/SQL. CADA bloque termina con una
-- línea que solo contiene "/". Sin esa barra, SQL Developer y SQL*Plus no
-- ejecutan el bloque y las tablas quedan vacías.
--
-- Bloques:
--   1. Catálogos, usuarios, alojamientos y habitaciones
--   2. Tarifas (cruce habitación x temporada), servicios y clientes
--   3. Reservas y reserva_habitacion (con estacionalidad y sin solapes)
--   4. Servicios contratados (reserva_servicio)
--   5. Pagos (calculados desde TARIFA y SERVICIO) y reembolsos del 80 %
--   6. Reseñas (del alojamiento realmente reservado)
--   7. Reinicio de las secuencias IDENTITY y resumen
--
-- Semilla fija en DBMS_RANDOM: los datos son reproducibles.
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK OFF

--------------------------------------------------------------------------------
-- BLOQUE 1. Limpieza, MUNICIPIO, TIPO_ALOJAMIENTO, TEMPORADA, USUARIO_SISTEMA,
--           ALOJAMIENTO y HABITACION
--------------------------------------------------------------------------------
DECLARE
    v_muni    NUMBER;
    v_tipo    NUMBER;
    v_n       NUMBER;
    v_id_hab  NUMBER := 0;
    v_id_tmp  NUMBER := 0;
    v_ss_ini  DATE;
    v_ss_fin  DATE;
    v_tipo_h  VARCHAR2(10);
    v_cap     NUMBER;

    -- Inserta una temporada con id consecutivo.
    PROCEDURE add_temporada(p_nombre VARCHAR2, p_nivel VARCHAR2,
                            p_ini DATE, p_fin DATE, p_anio NUMBER) IS
    BEGIN
        v_id_tmp := v_id_tmp + 1;
        INSERT INTO temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio)
        VALUES (v_id_tmp, p_nombre, p_nivel, p_ini, p_fin, p_anio);
    END;

    -- Tipo de habitación según el tipo de alojamiento (hotel: sencilla/doble/suite,
    -- hostal: sencilla/doble, finca: doble/suite/cabaña, glamping: doble/cabaña).
    FUNCTION f_tipo_hab(p_tipo NUMBER) RETURN VARCHAR2 IS
        u NUMBER := DBMS_RANDOM.VALUE;
    BEGIN
        IF p_tipo = 2 THEN
            RETURN CASE WHEN u < 0.40 THEN 'SENCILLA' WHEN u < 0.80 THEN 'DOBLE' ELSE 'SUITE' END;
        ELSIF p_tipo = 4 THEN
            RETURN CASE WHEN u < 0.50 THEN 'SENCILLA' ELSE 'DOBLE' END;
        ELSIF p_tipo = 1 THEN
            RETURN CASE WHEN u < 0.40 THEN 'DOBLE' WHEN u < 0.65 THEN 'SUITE' ELSE 'CABANA' END;
        ELSE
            RETURN CASE WHEN u < 0.50 THEN 'DOBLE' ELSE 'CABANA' END;
        END IF;
    END;
BEGIN
    DBMS_RANDOM.SEED(2026);

    ----------------------------------------------------------------------------
    -- 0. Limpieza previa en orden de FK (permite volver a correr el script)
    ----------------------------------------------------------------------------
    DELETE FROM resena;
    DELETE FROM pago;
    DELETE FROM reserva_servicio;
    DELETE FROM reserva_habitacion;
    DELETE FROM reserva;
    DELETE FROM servicio;
    DELETE FROM tarifa;
    DELETE FROM habitacion;
    DELETE FROM usuario_sistema;
    DELETE FROM alojamiento;
    DELETE FROM cliente;
    DELETE FROM temporada;
    DELETE FROM tipo_alojamiento;
    DELETE FROM municipio;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 1. MUNICIPIO: los 12 municipios del Quindío
    ----------------------------------------------------------------------------
    INSERT INTO municipio (id_municipio, nombre) VALUES (1, 'Armenia');
    INSERT INTO municipio (id_municipio, nombre) VALUES (2, 'Salento');
    INSERT INTO municipio (id_municipio, nombre) VALUES (3, 'Filandia');
    INSERT INTO municipio (id_municipio, nombre) VALUES (4, 'Quimbaya');
    INSERT INTO municipio (id_municipio, nombre) VALUES (5, 'Montenegro');
    INSERT INTO municipio (id_municipio, nombre) VALUES (6, 'Calarcá');
    INSERT INTO municipio (id_municipio, nombre) VALUES (7, 'Circasia');
    INSERT INTO municipio (id_municipio, nombre) VALUES (8, 'La Tebaida');
    INSERT INTO municipio (id_municipio, nombre) VALUES (9, 'Génova');
    INSERT INTO municipio (id_municipio, nombre) VALUES (10, 'Pijao');
    INSERT INTO municipio (id_municipio, nombre) VALUES (11, 'Córdoba');
    INSERT INTO municipio (id_municipio, nombre) VALUES (12, 'Buenavista');

    ----------------------------------------------------------------------------
    -- 2. TIPO_ALOJAMIENTO
    ----------------------------------------------------------------------------
    INSERT INTO tipo_alojamiento (id_tipo_alojamiento, nombre) VALUES (1, 'Finca cafetera');
    INSERT INTO tipo_alojamiento (id_tipo_alojamiento, nombre) VALUES (2, 'Hotel');
    INSERT INTO tipo_alojamiento (id_tipo_alojamiento, nombre) VALUES (3, 'Glamping');
    INSERT INTO tipo_alojamiento (id_tipo_alojamiento, nombre) VALUES (4, 'Hostal');

    ----------------------------------------------------------------------------
    -- 3. TEMPORADA
    -- Cubren sin huecos ni solapes desde 2024-01-01 hasta 2027-01-15, porque las
    -- reservas están repartidas en 2024-2026 y todas necesitan tarifa vigente.
    -- Alta: Semana Santa, mitad de año, puentes festivos y diciembre-enero.
    -- Baja: inicio de año y noviembre. Media: el resto.
    ----------------------------------------------------------------------------
    add_temporada('Alta diciembre-enero 2023-2024', 'ALTA',
                  DATE '2024-01-01', DATE '2024-01-15', 2023);

    FOR y IN 2024..2026 LOOP
        v_ss_ini := CASE y WHEN 2024 THEN DATE '2024-03-24'
                           WHEN 2025 THEN DATE '2025-04-13'
                           ELSE DATE '2026-03-29' END;
        v_ss_fin := CASE y WHEN 2024 THEN DATE '2024-03-31'
                           WHEN 2025 THEN DATE '2025-04-20'
                           ELSE DATE '2026-04-05' END;

        add_temporada('Baja inicio de año ' || y, 'BAJA',
                      TO_DATE(y || '-01-16', 'YYYY-MM-DD'), v_ss_ini - 1, y);
        add_temporada('Alta Semana Santa ' || y, 'ALTA', v_ss_ini, v_ss_fin, y);
        add_temporada('Media abril-junio ' || y, 'MEDIA',
                      v_ss_fin + 1, TO_DATE(y || '-06-14', 'YYYY-MM-DD'), y);
        add_temporada('Alta mitad de año ' || y, 'ALTA',
                      TO_DATE(y || '-06-15', 'YYYY-MM-DD'), TO_DATE(y || '-07-15', 'YYYY-MM-DD'), y);
        add_temporada('Media julio-octubre ' || y, 'MEDIA',
                      TO_DATE(y || '-07-16', 'YYYY-MM-DD'), TO_DATE(y || '-10-09', 'YYYY-MM-DD'), y);
        add_temporada('Alta puente festivo octubre ' || y, 'ALTA',
                      TO_DATE(y || '-10-10', 'YYYY-MM-DD'), TO_DATE(y || '-10-14', 'YYYY-MM-DD'), y);
        add_temporada('Media octubre ' || y, 'MEDIA',
                      TO_DATE(y || '-10-15', 'YYYY-MM-DD'), TO_DATE(y || '-10-30', 'YYYY-MM-DD'), y);
        add_temporada('Alta puentes noviembre ' || y, 'ALTA',
                      TO_DATE(y || '-10-31', 'YYYY-MM-DD'), TO_DATE(y || '-11-04', 'YYYY-MM-DD'), y);
        add_temporada('Baja noviembre ' || y, 'BAJA',
                      TO_DATE(y || '-11-05', 'YYYY-MM-DD'), TO_DATE(y || '-11-30', 'YYYY-MM-DD'), y);
        add_temporada('Alta diciembre-enero ' || y || '-' || (y + 1), 'ALTA',
                      TO_DATE(y || '-12-01', 'YYYY-MM-DD'), TO_DATE((y + 1) || '-01-15', 'YYYY-MM-DD'), y);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 4. USUARIO_SISTEMA: administradores
    ----------------------------------------------------------------------------
    INSERT INTO usuario_sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento)
    VALUES (1, 'ADMINISTRADOR', 'admin_gen', 'Carlos Plataforma', 'admin@turismouq.com', NULL);
    INSERT INTO usuario_sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento)
    VALUES (2, 'ADMINISTRADOR', 'admin_oper', 'Sonia Operaciones', 'soporte@turismouq.com', NULL);

    ----------------------------------------------------------------------------
    -- 5. ALOJAMIENTO (60), sus encargados y sus HABITACIONES
    -- Municipio: reparto desigual (Armenia 18, Salento 10, ... Génova 1).
    -- Tipo: según MOD(i,10): finca 30 %, hotel 30 %, glamping 20 %, hostal 20 %.
    -- Habitaciones (asimetría pedida en el enunciado):
    --   finca cafetera 3-5 | hotel en Armenia 30-40 | otros hoteles 8-20
    --   glamping 4-8 | hostal 6-12
    -- Encargados: uno por cada alojamiento 1..10, que cubren los 4 tipos.
    ----------------------------------------------------------------------------
    FOR i IN 1..60 LOOP
        IF i <= 18 THEN v_muni := 1;
        ELSIF i <= 28 THEN v_muni := 2;
        ELSIF i <= 36 THEN v_muni := 3;
        ELSIF i <= 42 THEN v_muni := 4;
        ELSIF i <= 48 THEN v_muni := 5;
        ELSIF i <= 54 THEN v_muni := 6;
        ELSE v_muni := MOD(i, 6) + 7;
        END IF;

        v_tipo := CASE MOD(i, 10) WHEN 1 THEN 1 WHEN 2 THEN 1 WHEN 3 THEN 1
                                  WHEN 4 THEN 2 WHEN 5 THEN 2 WHEN 6 THEN 2
                                  WHEN 7 THEN 3 WHEN 8 THEN 3
                                  ELSE 4 END;

        INSERT INTO alojamiento (id_alojamiento, nombre_comercial, direccion, calificacion,
                                 telefono, correo, id_municipio, id_tipo_alojamiento)
        VALUES (i,
                'Alojamiento ' || i || ' ' || CASE v_tipo WHEN 1 THEN 'Finca' WHEN 2 THEN 'Hotel'
                                                          WHEN 3 THEN 'Glamping' ELSE 'Hostal' END,
                'Calle ' || TRUNC(DBMS_RANDOM.VALUE(1, 50)) || ' # ' ||
                    TRUNC(DBMS_RANDOM.VALUE(1, 30)) || '-' || TRUNC(DBMS_RANDOM.VALUE(1, 99)),
                ROUND(DBMS_RANDOM.VALUE(3.5, 5.0), 1),
                '3' || TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)),
                'info@alojamiento' || i || '.com',
                v_muni, v_tipo);

        IF i <= 10 THEN
            INSERT INTO usuario_sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento)
            VALUES (i + 2, 'ENCARGADO', 'encargado_' || i, 'Encargado ' || i,
                    'encargado' || i || '@turismouq.com', i);
        END IF;

        v_n := CASE v_tipo
                   WHEN 1 THEN TRUNC(DBMS_RANDOM.VALUE(3, 6))
                   WHEN 2 THEN CASE WHEN v_muni = 1 THEN TRUNC(DBMS_RANDOM.VALUE(30, 41))
                                    ELSE TRUNC(DBMS_RANDOM.VALUE(8, 21)) END
                   WHEN 3 THEN TRUNC(DBMS_RANDOM.VALUE(4, 9))
                   ELSE TRUNC(DBMS_RANDOM.VALUE(6, 13))
               END;

        FOR h IN 1..v_n LOOP
            v_id_hab := v_id_hab + 1;
            v_tipo_h := f_tipo_hab(v_tipo);
            v_cap := CASE v_tipo_h WHEN 'SENCILLA' THEN TRUNC(DBMS_RANDOM.VALUE(1, 3))
                                   WHEN 'DOBLE'    THEN TRUNC(DBMS_RANDOM.VALUE(2, 4))
                                   WHEN 'SUITE'    THEN TRUNC(DBMS_RANDOM.VALUE(3, 6))
                                   ELSE TRUNC(DBMS_RANDOM.VALUE(4, 7)) END;
            INSERT INTO habitacion (id_habitacion, numero, capacidad_maxima, descripcion, tipo, id_alojamiento)
            VALUES (v_id_hab, TO_CHAR(h, 'FM000'), v_cap,
                    'Habitación tipo ' || LOWER(v_tipo_h) || ' con capacidad para ' || v_cap || ' personas',
                    v_tipo_h, i);
        END LOOP;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 1 OK. Habitaciones creadas: ' || v_id_hab ||
                         ' | Temporadas: ' || v_id_tmp);
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 2. TARIFA, SERVICIO y CLIENTE
--------------------------------------------------------------------------------
DECLARE
    TYPE t_str IS TABLE OF VARCHAR2(500);

    -- Servicios: 3 por alojamiento (180 en total), así todos los alojamientos
    -- tienen servicios y las reservas siempre contratan servicios de SU alojamiento.
    v_serv_nom  t_str := t_str('Desayuno típico', 'Tour cafetero guiado', 'Transporte al aeropuerto',
                               'Alquiler de bicicletas', 'Pasadía spa');
    v_serv_desc t_str := t_str('Desayuno campesino con arepa, huevo, chocolate y café',
                               'Recorrido guiado por el cultivo y beneficio del café',
                               'Traslado desde y hacia el aeropuerto El Edén',
                               'Bicicleta de montaña por día con casco',
                               'Circuito de relajación con masajes y aguas termales');
    v_serv_base t_str := t_str('25000', '60000', '70000', '30000', '90000');

    v_nombres t_str := t_str(
        'Carlos', 'María', 'Juan', 'Laura', 'Andrés', 'Sofía', 'Diego', 'Camila', 'Alejandro', 'Valentina',
        'Mateo', 'Isabella', 'Daniel', 'Mariana', 'Gabriel', 'Lucía', 'Santiago', 'Daniela', 'Felipe', 'Paula',
        'Nicolás', 'Manuela', 'Samuel', 'Salomé', 'Lucas', 'Antonia', 'Joaquín', 'Valeria', 'Sebastián', 'Gabriela',
        'Emanuel', 'Victoria', 'Tomás', 'Martina', 'Jerónimo', 'Elena', 'Matías', 'Sara', 'Agustín', 'Alicia',
        'Esteban', 'Clara', 'Julián', 'Renata', 'David', 'Irene', 'Adrián', 'Catalina', 'Leonardo', 'Emilia');
    v_apellidos t_str := t_str(
        'Pérez', 'Gómez', 'Rodríguez', 'López', 'Martínez', 'García', 'González', 'Hernández', 'Torres', 'Vargas',
        'Rojas', 'Ramírez', 'Castro', 'Morales', 'Ortiz', 'Gutiérrez', 'Chávez', 'Ríos', 'Navarro', 'Mendoza',
        'Silva', 'Suárez', 'Cárdenas', 'Moreno', 'Muñoz', 'Blanco', 'Jiménez', 'Díaz', 'Álvarez', 'Romero',
        'Acosta', 'Medina', 'Herrera', 'Aguilar', 'Paredes', 'Espinosa', 'Soto', 'Campos', 'Delgado', 'Vega',
        'Guerrero', 'Arias', 'Cortés', 'Pacheco', 'Ceballos', 'Ochoa', 'Bermúdez', 'Jaramillo', 'Londoño', 'Restrepo');
    -- Ciudades ordenadas de más a menos frecuentes (se muestrean con sesgo).
    v_ciudades t_str := t_str(
        'Bogotá', 'Medellín', 'Cali', 'Armenia', 'Pereira', 'Manizales', 'Barranquilla', 'Bucaramanga',
        'Cartagena', 'Ibagué', 'Cúcuta', 'Santa Marta', 'Popayán', 'Pasto', 'Neiva', 'Villavicencio',
        'Montería', 'Valledupar', 'Tunja', 'Florencia', 'Riohacha', 'Palmira', 'Buenaventura', 'Tuluá',
        'Girardot', 'Zipaquirá', 'Sogamoso', 'Duitama', 'Buga', 'Rionegro', 'Yopal', 'Chía');

    v_tipo_s  NUMBER;
    v_id_s    NUMBER := 0;
    v_nom     VARCHAR2(100);
    v_ape1    VARCHAR2(100);
    v_ape2    VARCHAR2(100);
BEGIN
    ----------------------------------------------------------------------------
    -- 7. TARIFA: una por cada combinación habitación x temporada (se deriva del
    -- cruce, no se digita). El precio NO es un porcentaje fijo sobre un precio
    -- base: cada alojamiento decide cuánto sube en temporada alta (entre +15 % y
    -- +85 % sobre su base), y además hay ruido por habitación y temporada.
    --   base = tipo de habitación x factor del tipo de alojamiento x factor propio
    ----------------------------------------------------------------------------
    INSERT INTO tarifa (precio_noche, id_habitacion, id_temporada)
    SELECT ROUND(
               CASE h.tipo WHEN 'SENCILLA' THEN 70000 WHEN 'DOBLE' THEN 100000
                           WHEN 'SUITE' THEN 170000 ELSE 140000 END
             * CASE a.id_tipo_alojamiento WHEN 1 THEN 1.1 WHEN 2 THEN 1.0 WHEN 3 THEN 1.5 ELSE 0.7 END
             * (0.90 + MOD(ORA_HASH(h.id_habitacion), 31) / 100)
             * CASE t.nivel
                   WHEN 'ALTA'  THEN 1.15 + MOD(ORA_HASH(a.id_alojamiento), 70) / 100
                                     + DBMS_RANDOM.VALUE(-0.05, 0.05)
                   WHEN 'MEDIA' THEN DBMS_RANDOM.VALUE(0.95, 1.15)
                   ELSE              DBMS_RANDOM.VALUE(0.75, 0.95)
               END, -3),
           h.id_habitacion, t.id_temporada
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    CROSS JOIN temporada t;

    ----------------------------------------------------------------------------
    -- 8. SERVICIO: 3 servicios distintos por alojamiento
    -- id_servicio = (alojamiento - 1) * 3 + j  (lo usa el bloque 4)
    ----------------------------------------------------------------------------
    FOR a IN 1..60 LOOP
        FOR j IN 1..3 LOOP
            v_id_s   := (a - 1) * 3 + j;
            v_tipo_s := MOD(a + 2 * (j - 1), 5) + 1;
            INSERT INTO servicio (id_servicio, nombre, descripcion, precio, id_alojamiento)
            VALUES (v_id_s, v_serv_nom(v_tipo_s), v_serv_desc(v_tipo_s),
                    ROUND(TO_NUMBER(v_serv_base(v_tipo_s)) * DBMS_RANDOM.VALUE(0.8, 1.3), -3),
                    a);
        END LOOP;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 9. CLIENTE: 3.000, con ciudades de origen variadas (sesgo hacia las
    -- ciudades grandes). El documento se construye único (no aleatorio) para
    -- no chocar con UQ_CLIENTE_DOCUMENTO.
    ----------------------------------------------------------------------------
    FOR c IN 1..3000 LOOP
        v_nom  := v_nombres(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        v_ape1 := v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        v_ape2 := v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        INSERT INTO cliente (id_cliente, nombre, documento_identidad, correo, telefono, ciudad_origen)
        VALUES (c,
                v_nom || ' ' || v_ape1 || ' ' || v_ape2,
                TO_CHAR(1000000000 + c * 9973 + MOD(c, 7)),
                LOWER(v_nom) || '.' || LOWER(v_ape1) || c || '@gmail.com',
                '3' || TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)),
                v_ciudades(TRUNC(32 * POWER(DBMS_RANDOM.VALUE, 1.7)) + 1));
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 2 OK. Tarifas, servicios y clientes cargados.');
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 3. RESERVA y RESERVA_HABITACION (25.000 reservas, 2024-2026)
--
-- Estacionalidad: la fecha de check-in se sortea con "rechazo" según el nivel
--   de la temporada de ese día: ALTA se acepta siempre, MEDIA el 40 %, BAJA el
--   18 %. Así diciembre-enero, Semana Santa y mitad de año concentran reservas.
-- Habitaciones: se sortea una habitación (los alojamientos con más habitaciones
--   reciben más reservas) y las demás habitaciones de la reserva son del MISMO
--   alojamiento (80 % una habitación, 14 % dos, 6 % tres). Algunas líneas llegan
--   un día después o salen un día antes dentro del rango general.
-- Sin solapes: una habitación no puede estar en dos reservas activas
--   (PENDIENTE, CONFIRMADA, COMPLETADA) en la misma noche. Las CANCELADAS no
--   ocupan la habitación. Si no se halla hueco tras 80 intentos, la reserva se
--   registra como CANCELADA (no pasa con estos parámetros).
--------------------------------------------------------------------------------
DECLARE
    TYPE t_num  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_date IS TABLE OF DATE INDEX BY PLS_INTEGER;
    TYPE t_str  IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER;
    TYPE t_bool IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;

    c_base  CONSTANT DATE := DATE '2024-01-01';
    c_corte CONSTANT DATE := DATE '2026-09-01';   -- fecha de corte: antes = ya ocurrió

    v_nivel      t_str;    -- nivel de temporada por día (offset desde c_base)
    v_hab_aloj   t_num;    -- habitación -> alojamiento
    v_hab_cap    t_num;    -- habitación -> capacidad máxima
    v_aloj_first t_num;    -- alojamiento -> primera habitación
    v_aloj_cnt   t_num;    -- alojamiento -> número de habitaciones
    v_occ        t_bool;   -- (habitación*2000 + día) ocupado

    v_l_hab t_num;         -- líneas de la reserva en construcción
    v_l_in  t_date;
    v_l_out t_date;

    v_nhab    PLS_INTEGER;
    v_d       PLS_INTEGER;
    v_try     PLS_INTEGER;
    v_k       PLS_INTEGER;
    v_off     PLS_INTEGER;
    v_a       PLS_INTEGER;
    v_h1      PLS_INTEGER;
    v_dias    PLS_INTEGER;
    v_f_in    DATE;
    v_f_out   DATE;
    v_estado  VARCHAR2(15);
    v_u1      NUMBER;
    v_u       NUMBER;
    v_ok      BOOLEAN;
    v_cli     NUMBER;
    v_id_rh   NUMBER := 0;
    v_fallos  NUMBER := 0;

    FUNCTION libre(p_hab NUMBER, p_in DATE, p_out DATE) RETURN BOOLEAN IS
    BEGIN
        FOR d IN TRUNC(p_in - c_base) .. TRUNC(p_out - c_base) - 1 LOOP
            IF v_occ.EXISTS(p_hab * 2000 + d) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
        RETURN TRUE;
    END;

    PROCEDURE ocupar(p_hab NUMBER, p_in DATE, p_out DATE) IS
    BEGIN
        FOR d IN TRUNC(p_in - c_base) .. TRUNC(p_out - c_base) - 1 LOOP
            v_occ(p_hab * 2000 + d) := TRUE;
        END LOOP;
    END;
BEGIN
    DBMS_RANDOM.SEED(20262);

    -- Mapas en memoria construidos desde las tablas ya cargadas
    FOR t IN (SELECT fecha_inicio, fecha_fin, nivel FROM temporada) LOOP
        FOR d IN TRUNC(t.fecha_inicio - c_base) .. TRUNC(t.fecha_fin - c_base) LOOP
            v_nivel(d) := t.nivel;
        END LOOP;
    END LOOP;

    FOR h IN (SELECT id_habitacion, id_alojamiento, capacidad_maxima FROM habitacion) LOOP
        v_hab_aloj(h.id_habitacion) := h.id_alojamiento;
        v_hab_cap(h.id_habitacion)  := h.capacidad_maxima;
    END LOOP;

    FOR a IN (SELECT id_alojamiento, MIN(id_habitacion) AS primera, COUNT(*) AS n
              FROM habitacion GROUP BY id_alojamiento) LOOP
        v_aloj_first(a.id_alojamiento) := a.primera;
        v_aloj_cnt(a.id_alojamiento)   := a.n;
    END LOOP;

    SELECT COUNT(*) INTO v_nhab FROM habitacion;

    FOR r IN 1..25000 LOOP
        v_u1 := DBMS_RANDOM.VALUE;    -- decide una sola vez si se cancela / queda pendiente
        v_ok := FALSE;
        v_try := 0;

        WHILE NOT v_ok AND v_try < 80 LOOP
            v_try := v_try + 1;

            -- Fecha de check-in con estacionalidad (muestreo por rechazo)
            LOOP
                v_d := TRUNC(DBMS_RANDOM.VALUE(0, 1096));   -- 2024-01-01 .. 2026-12-31
                EXIT WHEN DBMS_RANDOM.VALUE <
                          CASE v_nivel(v_d) WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 0.40 ELSE 0.18 END;
            END LOOP;
            v_dias  := TRUNC(DBMS_RANDOM.VALUE(1, 6));       -- 1 a 5 noches
            v_f_in  := c_base + v_d;
            v_f_out := v_f_in + v_dias;

            -- Estado: lo ya ocurrido se completa o se cancela; lo futuro se
            -- confirma o queda pendiente.
            IF v_f_out < c_corte THEN
                v_estado := CASE WHEN v_u1 < 0.15 THEN 'CANCELADA' ELSE 'COMPLETADA' END;
            ELSE
                v_estado := CASE WHEN v_u1 < 0.70 THEN 'CONFIRMADA' ELSE 'PENDIENTE' END;
            END IF;

            -- Habitaciones: todas del mismo alojamiento, consecutivas (cíclico)
            v_h1  := TRUNC(DBMS_RANDOM.VALUE(1, v_nhab + 1));
            v_a   := v_hab_aloj(v_h1);
            v_u   := DBMS_RANDOM.VALUE;
            v_k   := LEAST(CASE WHEN v_u < 0.80 THEN 1 WHEN v_u < 0.94 THEN 2 ELSE 3 END,
                           v_aloj_cnt(v_a));
            v_off := v_h1 - v_aloj_first(v_a);

            FOR i IN 1..v_k LOOP
                v_l_hab(i) := v_aloj_first(v_a) + MOD(v_off + i - 1, v_aloj_cnt(v_a));
                v_l_in(i)  := v_f_in;
                v_l_out(i) := v_f_out;
                IF i > 1 AND v_dias >= 2 AND DBMS_RANDOM.VALUE < 0.25 THEN
                    v_l_in(i) := v_f_in + 1;       -- alguien llega un día después
                END IF;
                IF i > 1 AND v_dias >= 3 AND DBMS_RANDOM.VALUE < 0.15 THEN
                    v_l_out(i) := v_f_out - 1;     -- alguien sale un día antes
                END IF;
            END LOOP;

            -- Disponibilidad (las canceladas no ocupan la habitación)
            v_ok := TRUE;
            IF v_estado <> 'CANCELADA' THEN
                FOR i IN 1..v_k LOOP
                    IF NOT libre(v_l_hab(i), v_l_in(i), v_l_out(i)) THEN
                        v_ok := FALSE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;

        IF NOT v_ok THEN               -- no se halló hueco: queda cancelada
            v_estado := 'CANCELADA';
            v_fallos := v_fallos + 1;
        END IF;

        IF v_estado <> 'CANCELADA' THEN
            FOR i IN 1..v_k LOOP
                ocupar(v_l_hab(i), v_l_in(i), v_l_out(i));
            END LOOP;
        END IF;

        -- Clientes con sesgo: algunos reservan mucho más que otros
        v_cli := TRUNC(3000 * POWER(DBMS_RANDOM.VALUE, 1.3)) + 1;

        INSERT INTO reserva (id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente)
        VALUES (r, v_f_in, v_f_out, v_estado, v_cli);

        FOR i IN 1..v_k LOOP
            v_id_rh := v_id_rh + 1;
            INSERT INTO reserva_habitacion (id_reserva_habitacion, fecha_checkin, fecha_checkout,
                                            num_huespedes, id_reserva, id_habitacion)
            VALUES (v_id_rh, v_l_in(i), v_l_out(i),
                    TRUNC(DBMS_RANDOM.VALUE(1, v_hab_cap(v_l_hab(i)) + 1)),
                    r, v_l_hab(i));
        END LOOP;

        IF MOD(r, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 3 OK. Líneas de reserva_habitacion: ' || v_id_rh ||
                         ' | reservas sin hueco (pasadas a CANCELADA): ' || v_fallos);
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 4. RESERVA_SERVICIO
-- Cada reserva NO cancelada contrata entre 0 y 3 servicios, y siempre del
-- alojamiento de la habitación reservada (servicios id = (alojamiento-1)*3 + j).
-- Reparto: 5 % ninguno, 25 % uno, 35 % dos, 35 % tres (promedio ~2 por reserva,
-- sobre las ~21.600 reservas activas: ~43.000 líneas, mínimo exigido 40.000).
-- precio_unitario congela el precio que tenía el servicio al contratarlo.
--------------------------------------------------------------------------------
DECLARE
    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_precio t_num;
    v_k      PLS_INTEGER;
    v_s      PLS_INTEGER;
    v_u      NUMBER;
    v_total  NUMBER := 0;
BEGIN
    DBMS_RANDOM.SEED(20264);

    FOR s IN (SELECT id_servicio, precio FROM servicio) LOOP
        v_precio(s.id_servicio) := s.precio;
    END LOOP;

    FOR r IN (SELECT rs.id_reserva, MIN(h.id_alojamiento) AS id_alojamiento
              FROM reserva rs
              JOIN reserva_habitacion rh ON rh.id_reserva = rs.id_reserva
              JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
              WHERE rs.estado <> 'CANCELADA'
              GROUP BY rs.id_reserva
              ORDER BY rs.id_reserva) LOOP
        v_u := DBMS_RANDOM.VALUE;
        v_k := CASE WHEN v_u < 0.05 THEN 0 WHEN v_u < 0.30 THEN 1 WHEN v_u < 0.65 THEN 2 ELSE 3 END;
        v_s := TRUNC(DBMS_RANDOM.VALUE(0, 3));            -- servicio por el que se empieza

        FOR i IN 0..v_k - 1 LOOP
            INSERT INTO reserva_servicio (cantidad, precio_unitario, id_reserva, id_servicio)
            VALUES (TRUNC(DBMS_RANDOM.VALUE(1, 4)),
                    v_precio((r.id_alojamiento - 1) * 3 + MOD(v_s + i, 3) + 1),
                    r.id_reserva,
                    (r.id_alojamiento - 1) * 3 + MOD(v_s + i, 3) + 1);
            v_total := v_total + 1;
        END LOOP;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 4 OK. Líneas de reserva_servicio: ' || v_total);
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 5. PAGO
-- Los montos salen de los datos, no son aleatorios:
--   valor de la estadía = suma, noche por noche, de la TARIFA vigente cada
--                         noche (la misma lógica de fn_valor_estadia, Entrega 2)
--   valor de servicios  = suma de cantidad x precio_unitario (RESERVA_SERVICIO)
--   total               = estadía + servicios
-- Reglas por estado de la reserva:
--   COMPLETADA : pagada por completo (70 % un pago, 30 % anticipo 50 % + saldo);
--                4 % tiene además un intento FALLIDO previo.
--   CONFIRMADA : 55 % pagada por completo; 45 % solo anticipo EXITOSO del 50 % y
--                saldo PENDIENTE.
--   PENDIENTE  : 50 % tiene un anticipo PENDIENTE del 30 %; el resto no tiene pagos.
--   CANCELADA  : 20 % se canceló sin pagar nada; el resto pagó un anticipo del 50 %.
--                Se sortea con cuántos días de anticipación canceló (0 a 30):
--                  más de 5 días -> se registra un pago REEMBOLSADO por el 80 %
--                                   del anticipo;
--                  5 días o menos -> sin reembolso.
--------------------------------------------------------------------------------
DECLARE
    TYPE t_str IS TABLE OF VARCHAR2(20);
    v_metodos t_str := t_str('TARJETA_CREDITO', 'TARJETA_DEBITO', 'PSE', 'TRANSFERENCIA', 'EFECTIVO');
    v_total    NUMBER;
    v_anticipo NUMBER;
    v_aviso    NUMBER;
    v_u        NUMBER;
    v_n_pagos  NUMBER := 0;

    -- Inserta un pago con método aleatorio (el método se saca a una variable
    -- porque una función local no puede llamarse dentro de un INSERT).
    PROCEDURE pago(p_fecha DATE, p_monto NUMBER, p_estado VARCHAR2, p_reserva NUMBER) IS
        v_metodo VARCHAR2(20) := v_metodos(TRUNC(DBMS_RANDOM.VALUE(1, 6)));
    BEGIN
        INSERT INTO pago (fecha, monto, metodo, estado, id_reserva)
        VALUES (p_fecha, p_monto, v_metodo, p_estado, p_reserva);
        v_n_pagos := v_n_pagos + 1;
    END;
BEGIN
    DBMS_RANDOM.SEED(20265);

    FOR r IN (SELECT rs.id_reserva, rs.estado, rs.fecha_checkin,
                     NVL(hab.valor, 0) + NVL(srv.valor, 0) AS total
              FROM reserva rs
              LEFT JOIN (SELECT rh.id_reserva,
                                SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1)
                                     - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.precio_noche) AS valor
                         FROM reserva_habitacion rh
                         JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                                         AND t.fecha_fin + 1 > rh.fecha_checkin
                         JOIN tarifa tf ON tf.id_habitacion = rh.id_habitacion
                                       AND tf.id_temporada = t.id_temporada
                         GROUP BY rh.id_reserva) hab ON hab.id_reserva = rs.id_reserva
              LEFT JOIN (SELECT id_reserva, SUM(cantidad * precio_unitario) AS valor
                         FROM reserva_servicio
                         GROUP BY id_reserva) srv ON srv.id_reserva = rs.id_reserva
              ORDER BY rs.id_reserva) LOOP

        v_total    := r.total;
        v_anticipo := ROUND(v_total * 0.5, 2);
        v_u        := DBMS_RANDOM.VALUE;

        IF r.estado = 'COMPLETADA' THEN
            IF DBMS_RANDOM.VALUE < 0.04 THEN               -- intento fallido previo
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(15, 25)), v_total, 'FALLIDO', r.id_reserva);
            END IF;
            IF v_u < 0.70 THEN
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(1, 15)), v_total, 'EXITOSO', r.id_reserva);
            ELSE
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(10, 31)), v_anticipo, 'EXITOSO', r.id_reserva);
                pago(r.fecha_checkin, v_total - v_anticipo, 'EXITOSO', r.id_reserva);
            END IF;

        ELSIF r.estado = 'CONFIRMADA' THEN
            IF v_u < 0.55 THEN
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(1, 15)), v_total, 'EXITOSO', r.id_reserva);
            ELSE
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(10, 31)), v_anticipo, 'EXITOSO', r.id_reserva);
                pago(r.fecha_checkin, v_total - v_anticipo, 'PENDIENTE', r.id_reserva);
            END IF;

        ELSIF r.estado = 'PENDIENTE' THEN
            IF v_u < 0.50 THEN
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(5, 20)), ROUND(v_total * 0.3, 2),
                     'PENDIENTE', r.id_reserva);
            END IF;

        ELSE  -- CANCELADA
            IF v_u >= 0.20 THEN
                v_aviso := TRUNC(DBMS_RANDOM.VALUE(0, 31));   -- días de anticipación al cancelar
                pago(r.fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(31, 46)), v_anticipo, 'EXITOSO', r.id_reserva);
                IF v_aviso > 5 THEN
                    pago(r.fecha_checkin - v_aviso, ROUND(v_anticipo * 0.8, 2), 'REEMBOLSADO', r.id_reserva);
                END IF;
            END IF;
        END IF;

        IF MOD(r.id_reserva, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 5 OK. Pagos insertados: ' || v_n_pagos);
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 6. RESENA
-- Solo reservas COMPLETADAS (~48 % deja reseña, mínimo exigido 40 %).
-- El alojamiento reseñado es el de la habitación realmente reservada, y el
-- cliente es el titular de la reserva.
-- La calificación varía entre 1 y 5 y depende de la calidad real del alojamiento:
-- la calificación que él mismo se asignó menos un descuento fijo de 0 a 1,0
-- estrellas, más ruido normal. Así la consulta 7 muestra diferencias reales entre
-- lo que el alojamiento dice y lo que opinan sus clientes.
--------------------------------------------------------------------------------
DECLARE
    TYPE t_str IS TABLE OF VARCHAR2(500);

    v_com_5 t_str := t_str(
        '¡Sencillamente espectacular! El aroma a café por las mañanas y la vista a las montañas del Quindío son inigualables.',
        'La atención del personal fue maravillosa. Nos hicieron sentir como en casa desde el primer minuto. ¡Volveremos!',
        'Las instalaciones son de primer nivel. El jacuzzi con vista al atardecer y la tranquilidad del lugar valen cada peso.',
        'Súper recomendado para desconectarse. El tour cafetero incluido estuvo fenomenal y el desayuno típico delicioso.',
        'Alojamiento impecable, camas muy cómodas y un paisaje soñado. La mejor experiencia que he tenido en el Eje Cafetero.',
        'Excelente relación calidad-precio. La amabilidad de los anfitriones y la limpieza de la habitación fueron de 10/10.',
        'Un oasis de paz en medio de la naturaleza. Hermosos jardines, avistamiento de aves y una comida exquisita.',
        'Nos encantó todo. La ubicación es perfecta para recorrer Salento y Filandia sin estar metido en el bullicio.',
        'Instalaciones súper acogedoras, impecables y con un toque campestre hermoso. El café de bienvenida estaba delicioso.',
        'Ideal para viajar en familia o en pareja. El personal siempre estuvo atento a cada una de nuestras necesidades.');
    v_com_4 t_str := t_str(
        'Muy buena estadía. El lugar es hermoso y la atención excelente, solo sugeriría mejorar un poco la señal de WiFi.',
        'La habitación muy cómoda y limpia. El desayuno estuvo muy rico, aunque faltó un poco más de variedad en la fruta.',
        'Excelente ubicación para explorar el Quindío. El ambiente es muy tranquilo, aunque la carretera de acceso tiene algunos baches.',
        'Nos gustó mucho el alojamiento y la calidez del servicio. La piscina estaba genial, aunque el agua algo fría en la tarde.',
        'Una gran experiencia en general. Camas muy confortables y paisajes bellísimos, solo la presión de la ducha bajaba a veces.',
        'Muy buen lugar para descansar. Las zonas comunes son muy agradables, aunque el restaurante tarda un poco en servir.',
        'El lugar supera las fotos, muy limpio y bien mantenido. Solo recomendaría ampliar el horario de atención en la recepción.',
        'Bonita finca con un ambiente campestre auténtico. Nos atendieron muy bien, seguro regresamos el próximo año.');
    v_com_3 t_str := t_str(
        'El sitio es bonito y el paisaje increíble, pero el servicio en el restaurante fue bastante lento durante nuestra estancia.',
        'Cumple para pasar la noche. La habitación es limpia, aunque se escuchaba bastante el ruido de los pasillos.',
        'Relación calidad-precio aceptable. La ubicación es buena, pero la conexión a internet falló casi todo el fin de semana.',
        'Instalaciones agradables pero con detalles por mejorar en la atención del personal durante las horas pico de check-in.',
        'Buena vista y lugar tranquilo, aunque el desayuno fue algo sencillo para el costo de la noche. Aceptable en general.');
    v_com_2 t_str := t_str(
        'La habitación no estaba como en las fotos y tardaron mucho en atendernos al llegar. Esperaba más por el precio.',
        'El lugar es bonito pero la limpieza dejó que desear y el agua caliente no funcionó durante la noche.',
        'Mucho ruido por la noche y poca respuesta del personal cuando reportamos el problema. No creo que regresemos.');
    v_com_1 t_str := t_str(
        'Mala experiencia: la reserva no fue respetada como la hicimos y la habitación estaba en mal estado. No lo recomiendo.',
        'Muy decepcionante. Servicios que no funcionaban, atención indiferente y nada de lo que prometía la publicación.',
        'Pésima atención y habitación sin mantenimiento. Tuvimos que pedir un cambio de cuarto y aun así no se resolvió.');

    v_calif NUMBER;
    v_com   VARCHAR2(500);
    v_total NUMBER := 0;
BEGIN
    DBMS_RANDOM.SEED(20266);

    FOR r IN (SELECT rs.id_reserva, rs.id_cliente, rs.fecha_checkout,
                     h.id_alojamiento,
                     a.calificacion - MOD(ORA_HASH(a.id_alojamiento), 11) / 10 AS calidad
              FROM reserva rs
              JOIN (SELECT id_reserva, MIN(id_habitacion) AS id_habitacion
                    FROM reserva_habitacion GROUP BY id_reserva) x ON x.id_reserva = rs.id_reserva
              JOIN habitacion h ON h.id_habitacion = x.id_habitacion
              JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
              WHERE rs.estado = 'COMPLETADA'
              ORDER BY rs.id_reserva) LOOP

        IF DBMS_RANDOM.VALUE <= 0.48 THEN
            v_calif := LEAST(5, GREATEST(1, ROUND(r.calidad + DBMS_RANDOM.NORMAL * 0.9)));
            v_com := CASE v_calif
                         WHEN 5 THEN v_com_5(TRUNC(DBMS_RANDOM.VALUE(1, 11)))
                         WHEN 4 THEN v_com_4(TRUNC(DBMS_RANDOM.VALUE(1, 9)))
                         WHEN 3 THEN v_com_3(TRUNC(DBMS_RANDOM.VALUE(1, 6)))
                         WHEN 2 THEN v_com_2(TRUNC(DBMS_RANDOM.VALUE(1, 4)))
                         ELSE        v_com_1(TRUNC(DBMS_RANDOM.VALUE(1, 4)))
                     END;
            INSERT INTO resena (calificacion, comentario, fecha, id_cliente, id_alojamiento, id_reserva)
            VALUES (v_calif, v_com, r.fecha_checkout + TRUNC(DBMS_RANDOM.VALUE(1, 8)),
                    r.id_cliente, r.id_alojamiento, r.id_reserva);
            v_total := v_total + 1;
        END IF;

        IF MOD(r.id_reserva, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Bloque 6 OK. Reseñas insertadas: ' || v_total);
END;
/

--------------------------------------------------------------------------------
-- BLOQUE 7. Reinicio de las columnas IDENTITY
-- Las tablas se cargaron con ids explícitos, y la secuencia interna de cada
-- IDENTITY no avanza con eso: el primer INSERT sin id de la Entrega 2 o 3
-- (sp_crear_reserva, triggers, pruebas) chocaría con la PK (ORA-00001).
-- Se reinicia cada una en el máximo actual + 1.
--------------------------------------------------------------------------------
DECLARE
    TYPE t_str IS TABLE OF VARCHAR2(60);
    v_tablas t_str := t_str('MUNICIPIO', 'TIPO_ALOJAMIENTO', 'ALOJAMIENTO', 'HABITACION', 'TEMPORADA',
                            'TARIFA', 'CLIENTE', 'RESERVA', 'RESERVA_HABITACION', 'SERVICIO',
                            'RESERVA_SERVICIO', 'PAGO', 'RESENA', 'USUARIO_SISTEMA');
    v_cols   t_str := t_str('ID_MUNICIPIO', 'ID_TIPO_ALOJAMIENTO', 'ID_ALOJAMIENTO', 'ID_HABITACION', 'ID_TEMPORADA',
                            'ID_TARIFA', 'ID_CLIENTE', 'ID_RESERVA', 'ID_RESERVA_HABITACION', 'ID_SERVICIO',
                            'ID_RESERVA_SERVICIO', 'ID_PAGO', 'ID_RESENA', 'ID_USUARIO');
    v_max NUMBER;
BEGIN
    FOR i IN 1..v_tablas.COUNT LOOP
        EXECUTE IMMEDIATE 'SELECT NVL(MAX(' || v_cols(i) || '), 0) + 1 FROM ' || v_tablas(i) INTO v_max;
        EXECUTE IMMEDIATE 'ALTER TABLE ' || v_tablas(i) || ' MODIFY (' || v_cols(i) ||
                          ' GENERATED BY DEFAULT AS IDENTITY (RESTART START WITH ' || v_max || '))';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Bloque 7 OK. Secuencias IDENTITY reiniciadas.');
END;
/

--------------------------------------------------------------------------------
-- Resumen de lo cargado (volumen mínimo del enunciado entre paréntesis)
--------------------------------------------------------------------------------
SELECT 'MUNICIPIO' AS tabla, COUNT(*) AS filas, '12' AS minimo FROM municipio UNION ALL
SELECT 'TIPO_ALOJAMIENTO', COUNT(*), '4' FROM tipo_alojamiento UNION ALL
SELECT 'ALOJAMIENTO', COUNT(*), '60' FROM alojamiento UNION ALL
SELECT 'HABITACION', COUNT(*), '400' FROM habitacion UNION ALL
SELECT 'TEMPORADA', COUNT(*), '6' FROM temporada UNION ALL
SELECT 'TARIFA', COUNT(*), 'habitaciones x temporadas' FROM tarifa UNION ALL
SELECT 'CLIENTE', COUNT(*), '3000' FROM cliente UNION ALL
SELECT 'RESERVA', COUNT(*), '25000' FROM reserva UNION ALL
SELECT 'RESERVA_HABITACION', COUNT(*), '25000' FROM reserva_habitacion UNION ALL
SELECT 'PAGO', COUNT(*), '25000' FROM pago UNION ALL
SELECT 'SERVICIO', COUNT(*), '30' FROM servicio UNION ALL
SELECT 'RESERVA_SERVICIO', COUNT(*), '40000' FROM reserva_servicio UNION ALL
SELECT 'RESENA', COUNT(*), '40 % de las completadas' FROM resena UNION ALL
SELECT 'USUARIO_SISTEMA', COUNT(*), '10' FROM usuario_sistema;