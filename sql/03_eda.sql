/*
CORE DEL ENTREGABLE:
  - Consultas EDA consecutivas, con comentarios y conclusiones de negocio.
  - Incluye: uniones (INNER/LEFT), CASE, agregaciones, subqueries, CTEs, ventanas,
    uso de VIEWs y FUNCIÓN, y una tabla/vista resumen para decisiones.

Requisito práctico:
  - Ejecuta primero sql/01_schema.sql, luego sql/02_data.sql ante sde ejecutar este archivo..
*/

-- 0) Chequeo rápido: ¿hay datos?

SELECT 'dim_customer' AS table_name, COUNT(*) AS rows FROM dim_customer
UNION ALL SELECT 'dim_motorcycle', COUNT(*) FROM dim_motorcycle
UNION ALL SELECT 'dim_branch', COUNT(*) FROM dim_branch
UNION ALL SELECT 'dim_calendar', COUNT(*) FROM dim_calendar
UNION ALL SELECT 'fact_rental', COUNT(*) FROM fact_rental
ORDER BY table_name;

-- 1) Vista enriquecida: vistazo rápido (uniones ya integradas)

-- Insight: esta vista es la "BASE" para el análisis: ya trae cliente, moto, provincia, canal, fechas y campos derivados.
SELECT *
FROM vw_rental_enriched
ORDER BY rental_id
LIMIT 10;

-- 2) Distribución de estados de reservas (agregación)

-- Insight: entender el estado del funnel: active vs completed vs cancelled/no_show.
SELECT
  rental_status,
  COUNT(*) AS bookings,
  ROUND(COUNT(*)::NUMERIC * 100 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM vw_rental_enriched
GROUP BY rental_status
ORDER BY bookings DESC;

-- 3) JOIN INNER: Revenue por canal

-- Insight: qué canal trae más volumen y qué canal trae más ingreso (no siempre coincide).
SELECT
  channel_name,
  COUNT(*) AS bookings,
  SUM(total_amount) AS revenue_gross_eur,
  AVG(total_amount)::NUMERIC(12,2) AS avg_ticket_eur
FROM vw_rental_enriched
GROUP BY channel_name
ORDER BY revenue_gross_eur DESC;

-- 4) JOIN INNER: Revenue por provincia (recogida)

-- Insight: mapa geográfico de ingresos. Útil para asignación de flota y staffing.
SELECT
  pickup_autonomous_community,
  pickup_province,
  COUNT(*) AS bookings,
  SUM(total_amount) AS revenue_gross_eur,
  AVG(rental_days)::NUMERIC(10,2) AS avg_days
FROM vw_rental_enriched
GROUP BY pickup_autonomous_community, pickup_province
ORDER BY revenue_gross_eur DESC;

-- 5) LEFT JOIN (caso típico): ¿promos usadas o no?

-- Insight: adopción real de cupones. Si “NO_PROMO” domina, quizá la estrategia de promos tiene el impacto esperado.
SELECT
  promo_code,
  COUNT(*) AS bookings,
  SUM(discount_amount) AS total_discount_given_eur,
  SUM(total_amount) AS revenue_gross_eur
FROM vw_rental_enriched
GROUP BY promo_code
ORDER BY bookings DESC;

-- 6) CASE: segmentación por duración (corta/media/larga)

-- Insight: segmentar demanda para diseñar packs y políticas de precios.
SELECT
  CASE
    WHEN rental_days <= 2 THEN 'Corta (1-2 dias)'
    WHEN rental_days <= 7 THEN 'Media (3-7 dias)'
    ELSE 'Larga (+7 dias)'
  END AS duration_segment,
  COUNT(*) AS bookings,
  AVG(total_amount)::NUMERIC(12,2) AS avg_ticket_eur,
  AVG(rental_days)::NUMERIC(10,2) AS avg_days
FROM vw_rental_enriched
GROUP BY duration_segment
ORDER BY bookings DESC;

-- 7) Ventana: Top clientes por gasto (ranking)

-- Insight: identificar clientes valiosos (para fidelización y upsell).
SELECT
  customer_id,
  first_name,
  last_name,
  nationality,
  is_tourist,
  SUM(total_amount) AS total_spent_eur,
  COUNT(*) AS bookings,
  ROW_NUMBER() OVER (ORDER BY SUM(total_amount) DESC) AS rn_spend
FROM vw_rental_enriched
WHERE rental_status = 'completed'
GROUP BY customer_id, first_name, last_name, nationality, is_tourist
ORDER BY total_spent_eur DESC
LIMIT 10;

-- 8) Subquery: clientes por encima de la media de gasto

-- Insight: segmentación premium basada en datos, no intuición.
SELECT *
FROM (
  SELECT
    customer_id,
    first_name,
    last_name,
    SUM(total_amount) AS total_spent_eur
  FROM vw_rental_enriched
  WHERE rental_status = 'completed'
  GROUP BY customer_id, first_name, last_name
) t
WHERE t.total_spent_eur > (
  SELECT AVG(total_spent_eur)
  FROM (
    SELECT customer_id, SUM(total_amount) AS total_spent_eur
    FROM vw_rental_enriched
    WHERE rental_status = 'completed'
    GROUP BY customer_id
  ) x
)
ORDER BY total_spent_eur DESC;

-- 9) Ventana + CTE: revenue mensual y acumulado (serie temporal)

-- Insight: tendencia en el tiempo más detectar meses fuertes y débiles.
WITH monthly AS (
  SELECT
    DATE_TRUNC('month', booking_date)::DATE AS month,
    SUM(total_amount) AS revenue_gross_eur,
    COUNT(*) AS bookings
  FROM vw_rental_enriched
  WHERE rental_status = 'completed'
  GROUP BY DATE_TRUNC('month', booking_date)::DATE
),
monthly_with_running AS (
  SELECT
    month,
    bookings,
    revenue_gross_eur,
    SUM(revenue_gross_eur) OVER (ORDER BY month) AS revenue_running_eur
  FROM monthly
)
SELECT *
FROM monthly_with_running
ORDER BY month;

-- 10) CTE encadenadas: ranking de meses por revenue

WITH monthly AS (
  SELECT
    DATE_TRUNC('month', booking_date)::DATE AS month,
    SUM(total_amount) AS revenue_gross_eur
  FROM vw_rental_enriched
  WHERE rental_status = 'completed'
  GROUP BY DATE_TRUNC('month', booking_date)::DATE
),
ranked AS (
  SELECT
    month,
    revenue_gross_eur,
    DENSE_RANK() OVER (ORDER BY revenue_gross_eur DESC) AS revenue_rank
  FROM monthly
)
SELECT *
FROM ranked
ORDER BY revenue_rank, month;

-- 11) ¿Fines de semana vs laborables? (funciones fecha + agregación)

-- Insight: demanda de turismo suele concentrarse en fines de semana.
SELECT
  CASE WHEN EXTRACT(ISODOW FROM booking_date) IN (6, 7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
  COUNT(*) AS bookings,
  AVG(total_amount)::NUMERIC(12,2) AS avg_ticket_eur
FROM vw_rental_enriched
GROUP BY day_type
ORDER BY bookings DESC;

-- 12) Incidencias (daños/multas) por canal y provincia

-- Insight: riesgos operativos; si un canal o unaprovincia tiene más incidencias, revisar políticas (depósitos, verificación, briefing).
SELECT
  pickup_province,
  channel_name,
  COUNT(*) FILTER (WHERE has_incident) AS incident_bookings,
  COUNT(*) AS bookings,
  ROUND((COUNT(*) FILTER (WHERE has_incident))::NUMERIC * 100 / NULLIF(COUNT(*)::NUMERIC, 0), 2) AS incident_rate_pct
FROM vw_rental_enriched
GROUP BY pickup_province, channel_name
ORDER BY incident_rate_pct DESC, bookings DESC;

-- 13) Uso de la FUNCIÓN: revenue neto antes de IVA

-- Insight: el revenue neto (antes de IVA) es una métrica más comparable entre periodos si el IVA cambia.
SELECT
  rental_id,
  rental_status,
  total_amount AS revenue_gross_eur,
  fn_rental_net_revenue(rental_id) AS revenue_net_before_tax_eur
FROM vw_rental_enriched
ORDER BY rental_id
LIMIT 15;

-- 14) CROSS-check de IVA (aprox): tax_amount ≈ 21% de (subtotal - discount)

-- Insight: validación de consistencia contable.
SELECT
  rental_id,
  subtotal,
  discount_amount,
  tax_amount,
  ROUND(((subtotal - discount_amount) * 0.21)::NUMERIC, 2) AS expected_tax,
  ROUND((tax_amount - ((subtotal - discount_amount) * 0.21))::NUMERIC, 2) AS tax_diff
FROM fact_rental
ORDER BY ABS(tax_amount - ((subtotal - discount_amount) * 0.21)) DESC
LIMIT 10;

-- 15) LEFT JOIN real: motos sin reservas (infrautilización)

-- Insight: detectar activos infrautilizados para rotación entre sucursales o cambios de pricing.
SELECT
  m.motorcycle_id,
  m.brand,
  m.model,
  m.category,
  m.status AS motorcycle_status,
  COUNT(fr.rental_id) AS bookings
FROM dim_motorcycle m
LEFT JOIN fact_rental fr
  ON fr.motorcycle_id = m.motorcycle_id
GROUP BY m.motorcycle_id, m.brand, m.model, m.category, m.status
ORDER BY bookings ASC, m.motorcycle_id;

-- 16) Repetición de clientes: cohortes simples (turista vs local)

-- Insight: si turistas repiten poco, el foco es adquisición; si locales repiten, el foco es retención.
SELECT
  is_tourist,
  COUNT(DISTINCT customer_id) AS customers,
  AVG(bookings_per_customer)::NUMERIC(10,2) AS avg_bookings_per_customer
FROM (
  SELECT
    customer_id,
    is_tourist,
    COUNT(*) AS bookings_per_customer
  FROM vw_rental_enriched
  GROUP BY customer_id, is_tourist
) t
GROUP BY is_tourist
ORDER BY is_tourist DESC;

-- 17) Ventana: LAG para comparar la última reserva del mismo cliente

-- Insight: ver si el ticket del cliente crece o cae entre reservas.
SELECT
  customer_id,
  booking_date,
  total_amount,
  LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY booking_date) AS prev_total_amount,
  (total_amount - LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY booking_date))::NUMERIC(12,2) AS delta_vs_prev
FROM vw_rental_enriched
WHERE rental_status = 'completed'
ORDER BY customer_id, booking_date;

-- 18) Sucursales: pickup vs return (logística)

-- Insight: si muchas reservas devuelven en otra sucursal, necesitas logística de reposición.
SELECT
  pickup_branch_name,
  return_branch_name,
  COUNT(*) AS bookings
FROM vw_rental_enriched
GROUP BY pickup_branch_name, return_branch_name
ORDER BY bookings DESC, pickup_branch_name, return_branch_name;

-- 19) Pricing: relación daily_rate vs duración

-- Insight: ver si hay descuentos por duración (daily_rate promedio podría bajar en alquileres largos).
SELECT
  CASE
    WHEN rental_days <= 2 THEN 'Corta'
    WHEN rental_days <= 7 THEN 'Media'
    ELSE 'Larga'
  END AS duration_segment,
  AVG(daily_rate)::NUMERIC(12,2) AS avg_daily_rate,
  AVG(total_amount)::NUMERIC(12,2) AS avg_total
FROM vw_rental_enriched
WHERE rental_status = 'completed'
GROUP BY duration_segment
ORDER BY avg_daily_rate DESC;

-- 20) Motos: popularidad por marca/categoría

-- Insight: guía para compras y mix de flota.
SELECT
  brand,
  motorcycle_category,
  COUNT(*) AS bookings,
  SUM(total_amount) AS revenue_gross_eur
FROM vw_rental_enriched
WHERE rental_status = 'completed'
GROUP BY brand, motorcycle_category
ORDER BY revenue_gross_eur DESC;

-- 21) Subquery: motos por encima de la media de su categoría

-- Insight: “MEJORES PERFORMERS” dentro de scooter Y manual.
WITH per_moto AS (
  SELECT
    motorcycle_id,
    motorcycle_category,
    COUNT(*) AS bookings,
    SUM(total_amount) AS revenue
  FROM vw_rental_enriched
  WHERE rental_status = 'completed'
  GROUP BY motorcycle_id, motorcycle_category
),
avg_by_cat AS (
  SELECT motorcycle_category, AVG(bookings)::NUMERIC AS avg_bookings
  FROM per_moto
  GROUP BY motorcycle_category
)
SELECT
  pm.motorcycle_id,
  ve.brand,
  ve.motorcycle_model,
  pm.motorcycle_category,
  pm.bookings,
  abc.avg_bookings
FROM per_moto pm
JOIN avg_by_cat abc ON abc.motorcycle_category = pm.motorcycle_category
JOIN (
  SELECT DISTINCT motorcycle_id, brand, motorcycle_model
  FROM vw_rental_enriched
) ve ON ve.motorcycle_id = pm.motorcycle_id
WHERE pm.bookings::NUMERIC > abc.avg_bookings
ORDER BY pm.motorcycle_category, pm.bookings DESC;

-- 22) Deposits: estados y uso parcial

-- Insight: depósitos parcialmente usados suelen correlacionar con incidencias.
SELECT
  deposit_status,
  COUNT(*) AS bookings,
  SUM(damage_fee) AS damage_eur,
  SUM(traffic_fines) AS fines_eur
FROM vw_rental_enriched
GROUP BY deposit_status
ORDER BY bookings DESC;

-- 23) VIEW resumen final (resultado final del proyecto)

-- Insight: esta salida sirve como tabla resumen para tomar decisiones:
-- volumen, revenue, pérdidas por cancel/no_show e incidencias por provincia y mes.
SELECT *
FROM vw_rental_summary
ORDER BY booking_month, pickup_autonomous_community, pickup_province;


