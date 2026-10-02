-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Bases de Datos II (Universidad del Quindío)
-- SCRIPT DE CARGA MASIVA POBLACIONAL DE DATOS
-- =============================================================================

DECLARE
    TYPE t_array_str IS TABLE OF VARCHAR2(500);
    
    -- Array de Nombres
    v_nombres t_array_str := t_array_str(
        'Carlos', 'María', 'Juan', 'Laura', 'Andrés', 'Sofía', 'Diego', 'Camila', 'Alejandro', 'Valentina',
        'Mateo', 'Isabella', 'Daniel', 'Mariana', 'Gabriel', 'Lucía', 'Santiago', 'Daniela', 'Felipe', 'Paula',
        'Nicolás', 'Manuela', 'Samuel', 'Salomé', 'Lucas', 'Antonia', 'Joaquín', 'Valeria', 'Sebastián', 'Gabriela',
        'Emanuel', 'Victoria', 'Tomás', 'Martina', 'Jerónimo', 'Elena', 'Matías', 'Sara', 'Agustín', 'Alicia',
        'Esteban', 'Clara', 'Julián', 'Renata', 'David', 'Irene', 'Adrián', 'Catalina', 'Leonardo', 'Emilia'
    );
    
    -- Array de Apellidos
    v_apellidos t_array_str := t_array_str(
        'Pérez', 'Gómez', 'Rodríguez', 'López', 'Martínez', 'García', 'González', 'Hernández', 'Torres', 'Vargas',
        'Rojas', 'Ramírez', 'Castro', 'Morales', 'Ortiz', 'Gutiérrez', 'Chávez', 'Ríos', 'Navarro', 'Mendoza',
        'Silva', 'Suárez', 'Cárdenas', 'Moreno', 'Muñoz', 'Blanco', 'Jiménez', 'Díaz', 'Álvarez', 'Romero',
        'Acosta', 'Medina', 'Herrera', 'Aguilar', 'Paredes', 'Espinosa', 'Soto', 'Campos', 'Delgado', 'Vega',
        'Guerrero', 'Arias', 'Cortés', 'Pacheco', 'Ceballos', 'Ochoa', 'Bermúdez', 'Jaramillo', 'Londoño', 'Restrepo'
    );
    
    -- Array de Ciudades
    v_ciudades t_array_str := t_array_str(
        'Bogotá', 'Medellín', 'Cali', 'Barranquilla', 'Bucaramanga', 'Pereira', 'Manizales', 'Cartagena',
        'Ibagué', 'Cúcuta', 'Santa Marta', 'Popayán', 'Pasto', 'Neiva', 'Villavicencio', 'Montería',
        'Valledupar', 'Tunja', 'Florencia', 'Riohacha', 'Armenia', 'Palmira', 'Buenaventura', 'Tuluá',
        'Girardot', 'Zipaquirá', 'Sogamoso', 'Duitama', 'Buga', 'Rionegro', 'Yopal', 'Chía'
    );
    
    -- Reseñas
    v_comentarios_5 t_array_str := t_array_str(
        '¡Sencillamente espectacular! El aroma a café por las mañanas y la vista a las montañas del Quindío son inigualables.',
        'La atención del personal fue maravillosa. Nos hicieron sentir como en casa desde el primer minuto. ¡Volveremos!',
        'Las instalaciones son de primer nivel. El jacuzzi con vista al atardecer y la tranquilidad del lugar valen cada peso.',
        'Súper recomendado para desconectarse. El tour cafetero incluido estuvo fenomenal y el desayuno típico delicioso.',
        'Alojamiento impecable, camas muy cómodas y un paisaje soñado. La mejor experiencia que he tenido en el Eje Cafetero.',
        'Excelente relación calidad-precio. La amabilidad de los anfitriones y la limpieza de la habitación fueron de 10/10.',
        'Un oasis de paz en medio de la naturaleza. Hermosos jardines, avistamiento de aves y una comida exquisita.',
        'Nos encantó todo. La ubicación es perfecta para recorrer Salento y Filandia sin estar metido en el bullicio.',
        'Instalaciones súper acogedoras, impecables y con un toque campestre hermoso. El café de bienvenida estaba delicioso.',
        'Ideal para viajar en familia o en pareja. El personal siempre estuvo atento a cada una de nuestras necesidades.'
    );

    v_comentarios_4 t_array_str := t_array_str(
        'Muy buena estadía. El lugar es hermoso y la atención excelente, solo sugeriría mejorar un poco la señal de WiFi.',
        'La habitación muy cómoda y limpia. El desayuno estuvo muy rico, aunque faltó un poco más de variedad en la fruta.',
        'Excelente ubicación para explorar el Quindío. El ambiente es muy tranquilo, aunque la carretera de acceso tiene algunos baches.',
        'Nos gustó mucho el alojamiento y la calidez del servicio. La piscina estaba genial, aunque el agua algo fría en la tarde.',
        'Una gran experiencia en general. Camas muy confortables y paisajes bellísimos, solo la presión de la ducha bajaba a veces.',
        'Muy buen lugar para descansar. Las zonas comunes son muy agradables, aunque el restaurante tarda un poco en servir.',
        'El lugar supera las fotos, muy limpio y bien mantenido. Solo recomendaría ampliar el horario de atención en la recepción.',
        'Bonita finca con un ambiente campestre auténtico. Nos atendieron muy bien, seguro regresamos el próximo año.'
    );

    v_comentarios_3 t_array_str := t_array_str(
        'El sitio es bonito y el paisaje increíble, pero el servicio en el restaurante fue bastante lento durante nuestra estancia.',
        'Cumple para pasar la noche. La habitación es limpia, aunque se escuchaba bastante el ruido de los pasillos.',
        'Relación calidad-precio aceptable. La ubicación es buena, pero la conexión a internet falló casi todo el fin de semana.',
        'Instalaciones agradables pero con detalles por mejorar en la atención del personal durante las horas pico de check-in.',
        'Buena vista y lugar tranquilo, aunque el desayuno fue algo sencillo para el costo de la noche. Aceptable en general.'
    );

    v_tipos_hab t_array_str := t_array_str('SENCILLA', 'DOBLE', 'SUITE', 'CABANA');
    v_metodos_pago t_array_str := t_array_str('TARJETA_CREDITO', 'TARJETA_DEBITO', 'PSE', 'TRANSFERENCIA', 'EFECTIVO');
    
    -- Variables escalares
    v_id_alojamiento NUMBER;
    v_id_habitacion NUMBER := 0;
    v_id_tarifa NUMBER := 0;
    v_id_servicio NUMBER := 0;
    v_id_reserva NUMBER := 0;
    v_id_res_hab NUMBER := 0;
    v_id_pago NUMBER := 0;
    v_id_res_serv NUMBER := 0;
    v_id_resena NUMBER := 0;
    
    v_muni_id NUMBER;
    v_tipo_aloj_id NUMBER;
    v_habs_para_aloj NUMBER;
    
    v_f_in DATE;
    v_f_out DATE;
    v_dias NUMBER;
    v_estado_res VARCHAR2(20);
    v_cliente_id NUMBER;
    v_monto_pago NUMBER;
    v_serv_id NUMBER;
    v_precio_serv NUMBER;
    v_nom VARCHAR2(100);
    v_ape1 VARCHAR2(100);
    v_ape2 VARCHAR2(100);
    v_calif NUMBER;
    v_comentario_txt VARCHAR2(500);
    
    v_tipo_hab_str VARCHAR2(100);
    v_ciudad_str VARCHAR2(100);
    v_metodo_pago_str VARCHAR2(100);
    v_precio_calculado NUMBER;
    
    TYPE t_hab_rec IS RECORD (
        id_habitacion NUMBER,
        id_alojamiento NUMBER,
        precio_base NUMBER
    );
    TYPE t_hab_list IS TABLE OF t_hab_rec INDEX BY BINARY_INTEGER;
    v_hab_list t_hab_list;
    
    TYPE t_serv_rec IS RECORD (
        id_servicio NUMBER,
        precio NUMBER
    );
    TYPE t_serv_list IS TABLE OF t_serv_rec INDEX BY BINARY_INTEGER;
    v_serv_list t_serv_list;
    
    TYPE t_reserva_rec IS RECORD (
        id_reserva NUMBER,
        id_cliente NUMBER,
        id_alojamiento NUMBER,
        fecha_in DATE,
        fecha_out DATE,
        estado VARCHAR2(20)
    );
    TYPE t_reserva_list IS TABLE OF t_reserva_rec INDEX BY BINARY_INTEGER;
    v_reserva_list t_reserva_list;

BEGIN
    ----------------------------------------------------------------------------
    -- 0. LIMPIEZA PREVIA EN ORDEN CORRECTO DE FK
    ----------------------------------------------------------------------------
    DELETE FROM RESENA;
    DELETE FROM PAGO;
    DELETE FROM RESERVA_SERVICIO;
    DELETE FROM RESERVA_HABITACION;
    DELETE FROM RESERVA;
    DELETE FROM SERVICIO;
    DELETE FROM TARIFA;
    DELETE FROM HABITACION;
    DELETE FROM USUARIO_SISTEMA;
    DELETE FROM ALOJAMIENTO;
    DELETE FROM CLIENTE;
    DELETE FROM TEMPORADA;
    DELETE FROM TIPO_ALOJAMIENTO;
    DELETE FROM MUNICIPIO;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 1. MUNICIPIO
    ----------------------------------------------------------------------------
    INSERT INTO Municipio (id_municipio, nombre) VALUES (1, 'Armenia');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (2, 'Salento');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (3, 'Filandia');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (4, 'Quimbaya');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (5, 'Montenegro');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (6, 'Calarcá');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (7, 'Circasia');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (8, 'La Tebaida');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (9, 'Génova');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (10, 'Pijao');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (11, 'Córdoba');
    INSERT INTO Municipio (id_municipio, nombre) VALUES (12, 'Buenavista');

    ----------------------------------------------------------------------------
    -- 2. TIPO_ALOJAMIENTO
    ----------------------------------------------------------------------------
    INSERT INTO Tipo_Alojamiento (id_tipo_alojamiento, nombre) VALUES (1, 'Finca cafetera');
    INSERT INTO Tipo_Alojamiento (id_tipo_alojamiento, nombre) VALUES (2, 'Hotel');
    INSERT INTO Tipo_Alojamiento (id_tipo_alojamiento, nombre) VALUES (3, 'Glamping');
    INSERT INTO Tipo_Alojamiento (id_tipo_alojamiento, nombre) VALUES (4, 'Hostal');

    ----------------------------------------------------------------------------
    -- 3. TEMPORADA
    ----------------------------------------------------------------------------
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (1, 'Baja 2025', 'BAJA', TO_DATE('2025-01-16', 'YYYY-MM-DD'), TO_DATE('2025-03-31', 'YYYY-MM-DD'), 2025);
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (2, 'Media 2025', 'MEDIA', TO_DATE('2025-04-01', 'YYYY-MM-DD'), TO_DATE('2025-11-30', 'YYYY-MM-DD'), 2025);
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (3, 'Alta 2025', 'ALTA', TO_DATE('2025-12-01', 'YYYY-MM-DD'), TO_DATE('2026-01-15', 'YYYY-MM-DD'), 2025);
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (4, 'Baja 2026', 'BAJA', TO_DATE('2026-01-16', 'YYYY-MM-DD'), TO_DATE('2026-03-31', 'YYYY-MM-DD'), 2026);
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (5, 'Media 2026', 'MEDIA', TO_DATE('2026-04-01', 'YYYY-MM-DD'), TO_DATE('2026-11-30', 'YYYY-MM-DD'), 2026);
    INSERT INTO Temporada (id_temporada, nombre, nivel, fecha_inicio, fecha_fin, anio) VALUES (6, 'Alta 2026', 'ALTA', TO_DATE('2026-12-01', 'YYYY-MM-DD'), TO_DATE('2027-01-15', 'YYYY-MM-DD'), 2026);

    ----------------------------------------------------------------------------
    -- 4. USUARIO_SISTEMA (ADMINISTRADORES)
    ----------------------------------------------------------------------------
    INSERT INTO Usuario_Sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento) VALUES (1, 'ADMINISTRADOR', 'admin_gen', 'Carlos Plataforma', 'admin@turismouq.com', NULL);
    INSERT INTO Usuario_Sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento) VALUES (2, 'ADMINISTRADOR', 'admin_oper', 'Sonia Operaciones', 'soporte@turismouq.com', NULL);

    ----------------------------------------------------------------------------
    -- 5. ALOJAMIENTO Y ENCARGADOS
    ----------------------------------------------------------------------------
    FOR i IN 1..60 LOOP
        IF i <= 18 THEN v_muni_id := 1;
        ELSIF i <= 28 THEN v_muni_id := 2;
        ELSIF i <= 36 THEN v_muni_id := 3;
        ELSIF i <= 42 THEN v_muni_id := 4;
        ELSIF i <= 48 THEN v_muni_id := 5;
        ELSIF i <= 54 THEN v_muni_id := 6;
        ELSE v_muni_id := MOD(i, 6) + 7;
        END IF;

        IF i <= 20 THEN v_tipo_aloj_id := 1;
        ELSIF i <= 40 THEN v_tipo_aloj_id := 2;
        ELSIF i <= 50 THEN v_tipo_aloj_id := 3;
        ELSE v_tipo_aloj_id := 4;
        END IF;

        INSERT INTO Alojamiento (id_alojamiento, nombre_comercial, direccion, calificacion, telefono, correo, id_municipio, id_tipo_alojamiento)
        VALUES (i, 'Alojamiento ' || i || ' ' || CASE v_tipo_aloj_id WHEN 1 THEN 'Finca' WHEN 2 THEN 'Hotel' WHEN 3 THEN 'Glamping' ELSE 'Hostal' END,
                'Calle ' || TRUNC(DBMS_RANDOM.VALUE(1, 50)) || ' # ' || TRUNC(DBMS_RANDOM.VALUE(1, 30)) || '-' || TRUNC(DBMS_RANDOM.VALUE(1, 99)),
                ROUND(DBMS_RANDOM.VALUE(3.5, 5.0), 1),
                '3' || TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)),
                'info@alojamiento' || i || '.com',
                v_muni_id, v_tipo_aloj_id);

        IF i <= 8 THEN
            INSERT INTO Usuario_Sistema (id_usuario, rol, nombre_usuario, nombre, correo, id_alojamiento)
            VALUES (i + 2, 'ENCARGADO', 'encargado_' || i, 'Encargado ' || i, 'encargado' || i || '@turismouq.com', i);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 6. HABITACION
    ----------------------------------------------------------------------------
    FOR a IN 1..60 LOOP
        IF a <= 5 THEN v_habs_para_aloj := 32;
        ELSIF a <= 20 THEN v_habs_para_aloj := 9;
        ELSE v_habs_para_aloj := 2 + MOD(a, 2);
        END IF;

        FOR h IN 1..v_habs_para_aloj LOOP
            v_id_habitacion := v_id_habitacion + 1;
            EXIT WHEN v_id_habitacion > 400;

            v_tipo_hab_str := v_tipos_hab(TRUNC(DBMS_RANDOM.VALUE(1, 5)));

            INSERT INTO Habitacion (id_habitacion, numero, capacidad_maxima, descripcion, tipo, id_alojamiento)
            VALUES (v_id_habitacion, TO_CHAR(h, 'FM000'), TRUNC(DBMS_RANDOM.VALUE(2, 6)),
                    'Habitación confortable tipo ' || v_tipo_hab_str,
                    v_tipo_hab_str, a);

            v_hab_list(v_id_habitacion).id_habitacion := v_id_habitacion;
            v_hab_list(v_id_habitacion).id_alojamiento := a;
            v_hab_list(v_id_habitacion).precio_base := 80000 + (TRUNC(DBMS_RANDOM.VALUE(0, 4)) * 30000);
        END LOOP;
    END LOOP;

    WHILE v_id_habitacion < 400 LOOP
        v_id_habitacion := v_id_habitacion + 1;
        v_id_alojamiento := MOD(v_id_habitacion, 60) + 1;
        INSERT INTO Habitacion (id_habitacion, numero, capacidad_maxima, descripcion, tipo, id_alojamiento)
        VALUES (v_id_habitacion, TO_CHAR(v_id_habitacion), 2, 'Habitación estándar', 'SENCILLA', v_id_alojamiento);
        v_hab_list(v_id_habitacion).id_habitacion := v_id_habitacion;
        v_hab_list(v_id_habitacion).id_alojamiento := v_id_alojamiento;
        v_hab_list(v_id_habitacion).precio_base := 90000;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 7. TARIFA
    ----------------------------------------------------------------------------
    FOR h IN 1..400 LOOP
        FOR t IN 1..6 LOOP
            v_id_tarifa := v_id_tarifa + 1;
            v_precio_calculado := v_hab_list(h).precio_base * CASE MOD(t, 3) WHEN 1 THEN 1.0 WHEN 2 THEN 1.3 ELSE 1.8 END;
            
            INSERT INTO Tarifa (id_tarifa, precio_noche, id_habitacion, id_temporada)
            VALUES (v_id_tarifa, v_precio_calculado, h, t);
        END LOOP;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 8. SERVICIO
    ----------------------------------------------------------------------------
    FOR s IN 1..30 LOOP
        v_id_alojamiento := MOD(s * 2, 60) + 1;
        v_precio_serv := ROUND(DBMS_RANDOM.VALUE(15000, 90000), -3);

        INSERT INTO Servicio (id_servicio, id_alojamiento, nombre, descripcion, precio)
        VALUES (s, v_id_alojamiento,
                'Servicio ' || s || ' - ' || CASE MOD(s, 5) WHEN 0 THEN 'Desayuno Especial' WHEN 1 THEN 'Tour Cafetero' WHEN 2 THEN 'Pasadía Spa' WHEN 3 THEN 'Alquiler Bici' ELSE 'Transporte Aeropuerto' END,
                'Servicio opcional para huéspedes', v_precio_serv);

        v_serv_list(s).id_servicio := s;
        v_serv_list(s).precio := v_precio_serv;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 9. CLIENTE
    ----------------------------------------------------------------------------
    FOR c IN 1..3000 LOOP
        v_nom := v_nombres(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        v_ape1 := v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        v_ape2 := v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1, 51)));
        v_ciudad_str := v_ciudades(TRUNC(DBMS_RANDOM.VALUE(1, 33)));

        INSERT INTO Cliente (id_cliente, nombre, documento_identidad, correo, telefono, ciudad_origen)
        VALUES (c,
                v_nom || ' ' || v_ape1 || ' ' || v_ape2,
                TO_CHAR(1000000000 + TRUNC(DBMS_RANDOM.VALUE(100000, 99999999))),
                LOWER(v_nom) || '.' || LOWER(v_ape1) || c || '@gmail.com',
                '3' || TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)),
                v_ciudad_str);
    END LOOP;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 10. RESERVA
    ----------------------------------------------------------------------------
    FOR r IN 1..25000 LOOP
        v_cliente_id := TRUNC(DBMS_RANDOM.VALUE(1, 3001));
        v_f_in := TO_DATE('2024-01-01', 'YYYY-MM-DD') + TRUNC(DBMS_RANDOM.VALUE(0, 1080));
        v_dias := TRUNC(DBMS_RANDOM.VALUE(1, 6));
        v_f_out := v_f_in + v_dias;

        IF v_f_out < TO_DATE('2026-09-01', 'YYYY-MM-DD') THEN
            IF DBMS_RANDOM.VALUE(0, 1) < 0.85 THEN v_estado_res := 'COMPLETADA';
            ELSE v_estado_res := 'CANCELADA';
            END IF;
        ELSE
            IF DBMS_RANDOM.VALUE(0, 1) < 0.70 THEN v_estado_res := 'CONFIRMADA';
            ELSE v_estado_res := 'PENDIENTE';
            END IF;
        END IF;

        v_id_alojamiento := TRUNC(DBMS_RANDOM.VALUE(1, 61));

        INSERT INTO Reserva (id_reserva, fecha_checkin, fecha_checkout, estado, id_cliente)
        VALUES (r, v_f_in, v_f_out, v_estado_res, v_cliente_id);

        v_reserva_list(r).id_reserva := r;
        v_reserva_list(r).id_cliente := v_cliente_id;
        v_reserva_list(r).id_alojamiento := v_id_alojamiento;
        v_reserva_list(r).fecha_in := v_f_in;
        v_reserva_list(r).fecha_out := v_f_out;
        v_reserva_list(r).estado := v_estado_res;

        IF MOD(r, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 11. RESERVA_HABITACION
    ----------------------------------------------------------------------------
    FOR r IN 1..25000 LOOP
        v_id_res_hab := v_id_res_hab + 1;
        v_id_habitacion := TRUNC(DBMS_RANDOM.VALUE(1, 401));
        v_f_in := v_reserva_list(r).fecha_in;
        v_f_out := v_reserva_list(r).fecha_out;

        INSERT INTO Reserva_Habitacion (id_reserva_habitacion, id_reserva, id_habitacion, fecha_checkin, fecha_checkout, num_huespedes)
        VALUES (v_id_res_hab, r, v_id_habitacion, v_f_in, v_f_out, TRUNC(DBMS_RANDOM.VALUE(1, 4)));

        IF DBMS_RANDOM.VALUE(0, 1) < 0.20 THEN
            v_id_res_hab := v_id_res_hab + 1;
            INSERT INTO Reserva_Habitacion (id_reserva_habitacion, id_reserva, id_habitacion, fecha_checkin, fecha_checkout, num_huespedes)
            VALUES (v_id_res_hab, r, MOD(v_id_habitacion + 1, 400) + 1, v_f_in, v_f_out, TRUNC(DBMS_RANDOM.VALUE(1, 4)));
        END IF;

        IF MOD(r, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 12. PAGO
    ----------------------------------------------------------------------------
    FOR r IN 1..25000 LOOP
        v_f_in := v_reserva_list(r).fecha_in;
        v_estado_res := v_reserva_list(r).estado;

        IF v_estado_res IN ('COMPLETADA', 'CONFIRMADA') THEN
            v_id_pago := v_id_pago + 1;
            v_monto_pago := ROUND(DBMS_RANDOM.VALUE(150000, 600000), -4);
            v_metodo_pago_str := v_metodos_pago(TRUNC(DBMS_RANDOM.VALUE(1, 6)));

            INSERT INTO Pago (id_pago, fecha, monto, estado, metodo, id_reserva)
            VALUES (v_id_pago, v_f_in - TRUNC(DBMS_RANDOM.VALUE(1, 15)), v_monto_pago, 'EXITOSO', v_metodo_pago_str, r);

            IF DBMS_RANDOM.VALUE(0, 1) < 0.30 THEN
                v_id_pago := v_id_pago + 1;
                v_metodo_pago_str := v_metodos_pago(TRUNC(DBMS_RANDOM.VALUE(1, 6)));
                INSERT INTO Pago (id_pago, fecha, monto, estado, metodo, id_reserva)
                VALUES (v_id_pago, v_f_in, v_monto_pago * 0.5, 'EXITOSO', v_metodo_pago_str, r);
            END IF;
        ELSIF v_estado_res = 'CANCELADA' THEN
            v_id_pago := v_id_pago + 1;
            INSERT INTO Pago (id_pago, fecha, monto, estado, metodo, id_reserva)
            VALUES (v_id_pago, v_f_in - 10, 100000, 'REEMBOLSADO', 'PSE', r);
        END IF;

        IF MOD(r, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 13. RESERVA_SERVICIO
    ----------------------------------------------------------------------------
    FOR rs IN 1..40000 LOOP
        v_id_reserva := TRUNC(DBMS_RANDOM.VALUE(1, 25001));
        v_serv_id := TRUNC(DBMS_RANDOM.VALUE(1, 31));
        v_precio_serv := v_serv_list(v_serv_id).precio;

        INSERT INTO Reserva_Servicio (id_reserva_servicio, id_reserva, id_servicio, cantidad, precio_unitario)
        VALUES (rs, v_id_reserva, v_serv_id, TRUNC(DBMS_RANDOM.VALUE(1, 4)), v_precio_serv);

        IF MOD(rs, 10000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    ----------------------------------------------------------------------------
    -- 14. RESENA
    ----------------------------------------------------------------------------
    FOR r IN 1..25000 LOOP
        IF v_reserva_list(r).estado = 'COMPLETADA' THEN
            IF DBMS_RANDOM.VALUE(0, 1) <= 0.48 THEN
                v_id_resena := v_id_resena + 1;
                v_calif := TRUNC(DBMS_RANDOM.VALUE(3, 6));
                
                IF v_calif = 5 THEN
                    v_comentario_txt := v_comentarios_5(TRUNC(DBMS_RANDOM.VALUE(1, 11)));
                ELSIF v_calif = 4 THEN
                    v_comentario_txt := v_comentarios_4(TRUNC(DBMS_RANDOM.VALUE(1, 9)));
                ELSE
                    v_comentario_txt := v_comentarios_3(TRUNC(DBMS_RANDOM.VALUE(1, 6)));
                END IF;

                v_f_out := v_reserva_list(r).fecha_out;
                v_id_alojamiento := v_reserva_list(r).id_alojamiento;
                v_cliente_id := v_reserva_list(r).id_cliente;

                INSERT INTO Resena (id_resena, calificacion, comentario, fecha, id_alojamiento, id_reserva, id_cliente)
                VALUES (v_id_resena, v_calif, v_comentario_txt, v_f_out + 1, v_id_alojamiento, r, v_cliente_id);
            END IF;
        END IF;

        IF MOD(r, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

END;
