## Orden de ejecución (Oracle Database Free 26ai, SQL Developer)

| Orden | Archivo | Contenido | Usuario que lo ejecuta |
| :--- | :--- | :--- | :--- |
| 0 | `00_usuario_y_tablespaces.sql` | Creación del usuario del esquema y del tablespace del histórico | SYSTEM |
| 1 | `01_DDL.sql` | Tablas, llaves y restricciones | TURISMOUQ |
| 2 | `02_carga.sql` | Datos con el volumen mínimo | TURISMOUQ |
| 3 | `03_consultas_analisis.sql` | Las 7 consultas de la Entrega 1 | TURISMOUQ |
| 4 | `04_paquete.sql` | Función, procedimiento, cursor y paquete | TURISMOUQ |
| 5 | `05_disparadores.sql` | Auditoría de TARIFA y solape de reservas | TURISMOUQ |
| 6 | `06_vista_materializada.sql` | Vista materializada de ocupación | SYSTEM (Parte A) y TURISMOUQ (Parte B) |
| 7 | `07_transacciones.sql` | Reserva y pago con SAVEPOINT | TURISMOUQ |
| 8 | `08_indices.sql` | Índices y planes de ejecución | TURISMOUQ (2 sesiones) |
| 9 | `09_seguridad.sql` | Roles, usuarios, perfil, GRANT y vistas | TURISMOUQ |
| 10 | `10_pruebas.sql` | Pruebas de las Entregas 2 y 3 | SYSTEM (Parte A y C1-C3) y TURISMOUQ (Parte B) |
