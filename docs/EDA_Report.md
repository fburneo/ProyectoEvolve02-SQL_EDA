## Resumen de EDA en SQL

## Contexto: Qué estoy analizando?

- **Unidad de análisis**: 1 fila en `fact_rental` = 1 reserva (1 moto).
- **Periodo**: `booking_date_key` 20250604 → 20250915.
- **Objetivo**: entender volumen, ingresos, uso de promos, incidencias y patrones operativos (canal/sucursal/provincia/tiempo).

## KPIs

- **Reservas**: 160  
  - completed: 138 | active: 10 | cancelled: 8 | no_show: 4
- **Revenue total (`total_amount`)**: €113.941,94
- **Revenue completado**: €99.956,76
- **Promos usadas**: 13,75%
- **Reservas perdidas (cancelled + no_show)**: 7,50%
- **Incidencias (daños o multas)**: 8,75%

## Hallazgos accionables

### 1) Canales: De dónde entra el flujo de dinero?

Top revenue (sólo para reservas completadas):
- Phone: €24.195,52
- Partner OTA: €23.103,98
- WhatsApp: €20.014,61
- Walk-in: €18.197,19
- Wix Website: €14.445,46

Lectura práctica:
- Si tengo que priorizar, empiezo por **Phone** y **Partner OTA** (son los que más facturan).

### 2) Geografía: En dónde se genera el revenue?

Revenue por provincia (sólo para reservas completadas):
- Girona: €32.642,65
- Málaga: €24.195,52
- Valencia: €23.103,98
- Barcelona: €20.014,61

Lectura práctica:
- Girona tira del negocio. Si falta disponibilidad, es el primer sitio donde reviso flota/precios.

### 3) Temporada: Cuándo se concentra?

- **Mejor mes**: 2025-07 con €40.344,30 (reservas completadas)

Lectura práctica:
- Julio es el pico. Planificación: staff, stock de motos “best sellers” y política de depósitos.

### 4) Clientes y flota: Qué se tiene mayor movimiento?

- **Cliente top (gasto completado)**: Name4 Surname4 con €4.022,04
- **Modelo más reservado**: Yamaha NMAX (38 reservas completadas)

Lectura práctica:
- Yamaha NMAX es el “caballo de batalla”. Si pienso en compras o rotación de flota, parto de ahí.

## Cómo lo reproduzco en PostgreSQL

- **Esquema**: `sql/01_schema.sql` (tablas, constraints, índices, vistas, función).
- **Carga**: `sql/02_data.sql` (re-ejecutable).
- **EDA**: `sql/03_eda.sql` (consultas comentadas: uniones, CTEs, ventanas, subqueries, y demás).

Si necesito un “output” de resumen rápido para negocio:
- `SELECT * FROM vw_rental_summary;`


