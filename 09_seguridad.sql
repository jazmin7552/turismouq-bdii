-- =============================================================================
-- Universidad del Quindío - Bases de Datos II
-- Proyecto Final: TurismoUQ
-- Entrega 3: Seguridad (4 roles, usuarios, GRANT, vistas y perfil de sesión)
-- Archivo: 04_roles_usuarios_vistas.sql
-- Motor: Oracle Database Free | Cliente: Oracle SQL Developer
--
-- CÓMO EJECUTARLO (dos conexiones distintas, en este orden):
--   PARTE A -> conexión SYSTEM. Crea el perfil, los roles y los usuarios.
--              (Crear usuarios, roles y perfiles exige privilegios de administrador.)
--   PARTE B -> conexión Proyecto (TURISMOUQ). Crea las vistas y entrega los
--              privilegios sobre los objetos al rol correspondiente.
--   PARTE C -> consultas de verificación. Cada línea indica con qué usuario se ejecuta.
--
-- Requisito: Entrega 1 y Entrega 2 ejecutadas (tablas, auditoria_tarifa,
-- mv_ocupacion_mensual y pkg_turismouq) y 01_transacciones_savepoint.sql
-- (sp_reservar_y_pagar).
--
-- Roles (privilegios diferenciados):
--   rol_recepcion           Solo VISTAS: ve las reservas por atender y las
--                           habitaciones, y registra reservas con sp_reservar_y_pagar.
--                           Ningún privilegio sobre tablas.
--   rol_admin_alojamiento   Gestiona SU alojamiento: habitaciones y tarifas (vistas
--                           filtradas por su usuario) y consulta sus reservas.
--   rol_gerente             Solo lectura de las tablas del negocio y de la vista
--                           materializada de ocupación. No modifica nada.
--   rol_auditor             Solo lectura de lo que se audita: cambios de tarifa,
--                           pagos, reservas y usuarios. No modifica nada.
-- =============================================================================

-- #############################################################################
-- PARTE A · EJECUTAR COMO SYSTEM
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- A1. Limpieza para poder repetir el script
DECLARE
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM dba_users WHERE username = 'TURISMOUQ';
    IF v_n = 0 THEN
        RAISE_APPLICATION_ERROR(-20011,
            'No existe TURISMOUQ en esta base de datos. Conéctate como SYSTEM a la misma base donde está el proyecto.');
    END IF;

    FOR u IN (SELECT username FROM dba_users
               WHERE username IN ('RECEPCION_1', 'ENCARGADO_1', 'GERENTE_1', 'AUDITOR_1')) LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    END LOOP;
    FOR r IN (SELECT role FROM dba_roles
               WHERE role IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')) LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
    END LOOP;
    SELECT COUNT(*) INTO v_n FROM dba_profiles WHERE profile = 'PERFIL_TURISMOUQ';
    IF v_n > 0 THEN
        EXECUTE IMMEDIATE 'DROP PROFILE perfil_turismouq CASCADE';
    END IF;
END;
/

-- A2. Perfil con límites de sesión
CREATE PROFILE perfil_turismouq LIMIT
    SESSIONS_PER_USER        2        -- máximo 2 sesiones simultáneas por usuario
    CONNECT_TIME             480      -- una sesión dura como máximo 8 horas (minutos)
    IDLE_TIME                15       -- se cierra tras 15 minutos sin actividad
    FAILED_LOGIN_ATTEMPTS    3        -- se bloquea la cuenta al tercer intento fallido
    PASSWORD_LOCK_TIME       1        -- la cuenta bloqueada se libera tras 1 día
    PASSWORD_LIFE_TIME       90       -- la contraseña vence a los 90 días
    PASSWORD_GRACE_TIME      7;       -- 7 días de gracia para cambiarla

-- A3. Los cuatro roles (CREATE SESSION permite conectarse)
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_alojamiento;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- A4. Un usuario por rol, todos con el perfil. encargado_1 coincide con el
--     nombre_usuario del encargado del alojamiento 1 en USUARIO_SISTEMA: las vistas
--     del administrador de alojamiento lo usan para mostrarle solo lo suyo.
CREATE USER recepcion_1 IDENTIFIED BY Recepcion2026 PROFILE perfil_turismouq;
CREATE USER encargado_1 IDENTIFIED BY Encargado2026 PROFILE perfil_turismouq;
CREATE USER gerente_1   IDENTIFIED BY Gerente2026   PROFILE perfil_turismouq;
CREATE USER auditor_1   IDENTIFIED BY Auditor2026   PROFILE perfil_turismouq;

GRANT rol_recepcion         TO recepcion_1;
GRANT rol_admin_alojamiento TO encargado_1;
GRANT rol_gerente           TO gerente_1;
GRANT rol_auditor           TO auditor_1;


-- #############################################################################
-- PARTE B · EJECUTAR COMO TURISMOUQ (conexión Proyecto)
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

--------------------------------------------------------------------------------
-- B1. VISTAS PARA RECEPCIÓN (recepción nunca toca las tablas)
--------------------------------------------------------------------------------

-- Reservas por atender: vigentes (pendientes o confirmadas) que aún no han salido.
-- Muestra lo necesario para atender al huésped; no incluye correo, ciudad ni pagos.
CREATE OR REPLACE VIEW v_recepcion_reservas AS
SELECT r.id_reserva,
       r.estado,
       rh.fecha_checkin,
       rh.fecha_checkout,
       rh.num_huespedes,
       c.nombre               AS cliente,
       c.documento_identidad  AS documento,
       c.telefono             AS telefono,
       a.nombre_comercial     AS alojamiento,
       h.numero               AS habitacion,
       h.tipo                 AS tipo_habitacion
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  JOIN habitacion h          ON h.id_habitacion = rh.id_habitacion
  JOIN alojamiento a         ON a.id_alojamiento = h.id_alojamiento
  JOIN cliente c             ON c.id_cliente = r.id_cliente
 WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
   AND rh.fecha_checkout >= TRUNC(SYSDATE);

-- Habitaciones y su capacidad, para saber dónde ubicar a cada grupo
CREATE OR REPLACE VIEW v_recepcion_habitaciones AS
SELECT h.id_habitacion,
       a.nombre_comercial AS alojamiento,
       h.numero,
       h.tipo,
       h.capacidad_maxima
  FROM habitacion h
  JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento;

--------------------------------------------------------------------------------
-- B2. VISTAS PARA EL ADMINISTRADOR DE ALOJAMIENTO
--     Cada una filtra por el alojamiento del usuario conectado (se busca su
--     nombre de usuario en USUARIO_SISTEMA). WITH CHECK OPTION impide insertar o
--     modificar filas que queden fuera de su alojamiento.
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_admin_habitaciones AS
SELECT h.id_habitacion, h.numero, h.capacidad_maxima, h.descripcion, h.tipo, h.id_alojamiento
  FROM habitacion h
 WHERE h.id_alojamiento = (SELECT u.id_alojamiento
                             FROM usuario_sistema u
                            WHERE UPPER(u.nombre_usuario) = SYS_CONTEXT('USERENV', 'SESSION_USER'))
WITH CHECK OPTION;

CREATE OR REPLACE VIEW v_admin_tarifas AS
SELECT t.id_tarifa, t.id_habitacion, t.id_temporada, t.precio_noche
  FROM tarifa t
 WHERE t.id_habitacion IN (SELECT h.id_habitacion
                             FROM habitacion h
                            WHERE h.id_alojamiento = (SELECT u.id_alojamiento
                                                        FROM usuario_sistema u
                                                       WHERE UPPER(u.nombre_usuario) = SYS_CONTEXT('USERENV', 'SESSION_USER')))
WITH CHECK OPTION;

-- Solo lectura: las reservas de las habitaciones de su alojamiento
CREATE OR REPLACE VIEW v_admin_reservas AS
SELECT r.id_reserva,
       r.estado,
       rh.id_habitacion,
       h.numero AS habitacion,
       rh.fecha_checkin,
       rh.fecha_checkout,
       rh.num_huespedes,
       c.nombre AS cliente
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  JOIN habitacion h          ON h.id_habitacion = rh.id_habitacion
  JOIN cliente c             ON c.id_cliente = r.id_cliente
 WHERE h.id_alojamiento = (SELECT u.id_alojamiento
                             FROM usuario_sistema u
                            WHERE UPPER(u.nombre_usuario) = SYS_CONTEXT('USERENV', 'SESSION_USER'))
WITH READ ONLY;

--------------------------------------------------------------------------------
-- B3. PRIVILEGIOS SOBRE LOS OBJETOS, UN ROL A LA VEZ
--------------------------------------------------------------------------------

-- Recepción: solo las dos vistas y el procedimiento que registra la reserva con su pago
GRANT SELECT ON v_recepcion_reservas     TO rol_recepcion;
GRANT SELECT ON v_recepcion_habitaciones TO rol_recepcion;

DECLARE
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM user_objects
     WHERE object_name = 'SP_RESERVAR_Y_PAGAR' AND object_type = 'PROCEDURE';
    IF v_n > 0 THEN
        EXECUTE IMMEDIATE 'GRANT EXECUTE ON sp_reservar_y_pagar TO rol_recepcion';
    ELSE
        DBMS_OUTPUT.PUT_LINE('Aviso: falta sp_reservar_y_pagar (01_transacciones_savepoint.sql). ' ||
                             'Ejecútelo y repita este GRANT.');
    END IF;
END;
/

-- Administrador de alojamiento: gestiona habitaciones y tarifas de lo suyo (sin DELETE),
-- lee sus reservas y consulta las temporadas
GRANT SELECT, INSERT, UPDATE ON v_admin_habitaciones TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON v_admin_tarifas      TO rol_admin_alojamiento;
GRANT SELECT                 ON v_admin_reservas     TO rol_admin_alojamiento;
GRANT SELECT                 ON temporada            TO rol_admin_alojamiento;

-- Gerente: solo lectura del negocio y de la ocupación; sin clientes ni auditoría
GRANT SELECT ON municipio            TO rol_gerente;
GRANT SELECT ON tipo_alojamiento     TO rol_gerente;
GRANT SELECT ON alojamiento          TO rol_gerente;
GRANT SELECT ON habitacion           TO rol_gerente;
GRANT SELECT ON temporada            TO rol_gerente;
GRANT SELECT ON tarifa               TO rol_gerente;
GRANT SELECT ON reserva              TO rol_gerente;
GRANT SELECT ON reserva_habitacion   TO rol_gerente;
GRANT SELECT ON servicio             TO rol_gerente;
GRANT SELECT ON reserva_servicio     TO rol_gerente;
GRANT SELECT ON pago                 TO rol_gerente;
GRANT SELECT ON resena               TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;

-- Auditor: solo lectura de lo que se audita
GRANT SELECT ON auditoria_tarifa   TO rol_auditor;
GRANT SELECT ON tarifa             TO rol_auditor;
GRANT SELECT ON pago               TO rol_auditor;
GRANT SELECT ON reserva            TO rol_auditor;
GRANT SELECT ON reserva_habitacion TO rol_auditor;
GRANT SELECT ON usuario_sistema    TO rol_auditor;


-- #############################################################################
-- PARTE C · VERIFICACIÓN (evidencia)
-- #############################################################################

-- C1. Como SYSTEM: privilegios sobre objetos de cada rol (captura)
SELECT grantee, table_name, privilege
  FROM dba_tab_privs
 WHERE grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
 ORDER BY grantee, table_name, privilege;

-- C2. Como SYSTEM: roles de cada usuario y su perfil (captura)
SELECT u.username, u.profile, r.granted_role
  FROM dba_users u
  JOIN dba_role_privs r ON r.grantee = u.username
 WHERE u.username IN ('RECEPCION_1', 'ENCARGADO_1', 'GERENTE_1', 'AUDITOR_1')
 ORDER BY u.username;

-- C3. Como SYSTEM: límites del perfil (captura)
SELECT resource_name, limit
  FROM dba_profiles
 WHERE profile = 'PERFIL_TURISMOUQ'
   AND resource_name IN ('SESSIONS_PER_USER', 'CONNECT_TIME', 'IDLE_TIME',
                         'FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME',
                         'PASSWORD_LIFE_TIME', 'PASSWORD_GRACE_TIME')
 ORDER BY resource_name;

-- C4. Pruebas con cada usuario (crear una conexión por usuario en SQL Developer:
--     mismo host, puerto y servicio que Proyecto; usuario y contraseña de la PARTE A).
--
--   Con recepcion_1:
--     SELECT COUNT(*) FROM turismouq.v_recepcion_reservas;   -- funciona
--     SELECT COUNT(*) FROM turismouq.reserva;                -- ORA-00942: no ve la tabla
--     SELECT COUNT(*) FROM turismouq.cliente;                -- ORA-00942
--
--   Con encargado_1 (alojamiento 1):
--     SELECT COUNT(*) FROM turismouq.v_admin_habitaciones;   -- solo las del alojamiento 1
--     UPDATE turismouq.v_admin_tarifas SET precio_noche = precio_noche + 1000
--      WHERE id_habitacion = (SELECT MIN(id_habitacion) FROM turismouq.v_admin_habitaciones);
--                                                            -- funciona (y queda en auditoria_tarifa)
--     INSERT INTO turismouq.v_admin_habitaciones (numero, capacidad_maxima, tipo, id_alojamiento)
--     VALUES ('999', 2, 'DOBLE', 2);                         -- ORA-01402: otro alojamiento
--     SELECT COUNT(*) FROM turismouq.pago;                   -- ORA-00942
--     ROLLBACK;
--
--   Con gerente_1:
--     SELECT COUNT(*) FROM turismouq.reserva;                -- funciona
--     DELETE FROM turismouq.reserva;                         -- ORA-01031: privilegios insuficientes
--     SELECT COUNT(*) FROM turismouq.auditoria_tarifa;       -- ORA-00942
--
--   Con auditor_1:
--     SELECT COUNT(*) FROM turismouq.auditoria_tarifa;       -- funciona
--     UPDATE turismouq.tarifa SET precio_noche = 1;          -- ORA-01031
--     SELECT COUNT(*) FROM turismouq.resena;                 -- ORA-00942


SELECT banner_full FROM v$version;