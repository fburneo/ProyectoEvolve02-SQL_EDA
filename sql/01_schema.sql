/*
Proyecto SQL: Moto Rental (España)

Objetivo:
  - Crear el modelo relacional (modelo en estrella) desde cero en PostgreSQL.
  - Incluir PK/FK, constraints, índices, 1 VIEW y 1 FUNCIÓN.

Notas de diseño:
  - He mantenido un enfoque de almacén de datos ligero: una tabla de reservas
    y varias dimensiones (cliente, moto, sucursal, fechas, etc.).
  - Los date_key vienen en formato YYYYMMDD (entero). Es práctico para uniones y ordenación.
  - Los estados se controlan con CHECK para evitar valores fuera de catálogo.
*/

-- 0) Limpieza

DROP VIEW IF EXISTS vw_rental_summary;
DROP VIEW IF EXISTS vw_rental_enriched;
DROP FUNCTION IF EXISTS fn_rental_net_revenue(INT);

DROP TABLE IF EXISTS fact_rental CASCADE;
DROP TABLE IF EXISTS dim_customer CASCADE;
DROP TABLE IF EXISTS dim_motorcycle CASCADE;
DROP TABLE IF EXISTS dim_branch CASCADE;
DROP TABLE IF EXISTS dim_promo CASCADE;
DROP TABLE IF EXISTS dim_payment_method CASCADE;
DROP TABLE IF EXISTS dim_channel CASCADE;
DROP TABLE IF EXISTS dim_calendar CASCADE;
DROP TABLE IF EXISTS dim_province CASCADE;

-- 1) Dimensiones

CREATE TABLE IF NOT EXISTS dim_province (
    province_id            INT PRIMARY KEY,
    province_name          TEXT NOT NULL,
    autonomous_community   TEXT NOT NULL,
    CONSTRAINT uq_dim_province_name UNIQUE (province_name)
);

COMMENT ON TABLE dim_province IS 'Dimensión geográfica: provincias de España (con comunidad autónoma).';
COMMENT ON COLUMN dim_province.province_id IS 'PK natural del conjunto de datos (provincia).';


CREATE TABLE IF NOT EXISTS dim_calendar (
    date_key      INT PRIMARY KEY,
    date_value    DATE NOT NULL,
    day_of_month  SMALLINT NOT NULL,
    month         SMALLINT NOT NULL,
    year          SMALLINT NOT NULL,
    day_name      TEXT NOT NULL,
    month_name    TEXT NOT NULL,
    is_weekend    BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_dim_calendar_date_value UNIQUE (date_value),
    CONSTRAINT ck_dim_calendar_day CHECK (day_of_month BETWEEN 1 AND 31),
    CONSTRAINT ck_dim_calendar_month CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT ck_dim_calendar_year CHECK (year BETWEEN 1900 AND 2100),
    CONSTRAINT ck_dim_calendar_date_key CHECK (date_key BETWEEN 19000101 AND 29991231)
);

COMMENT ON TABLE dim_calendar IS 'Dimensión de fechas. Granularidad: 1 fila = 1 día.';
COMMENT ON COLUMN dim_calendar.date_key IS 'PK sustituta del conjunto de datos (YYYYMMDD como entero).';


CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id     INT PRIMARY KEY,
    channel_name   TEXT NOT NULL,
    CONSTRAINT uq_dim_channel_name UNIQUE (channel_name)
);

COMMENT ON TABLE dim_channel IS 'Dimensión del canal de reserva (web, walk-in, WhatsApp, etc.).';


CREATE TABLE IF NOT EXISTS dim_payment_method (
    payment_method_id   INT PRIMARY KEY,
    method_name         TEXT NOT NULL,
    CONSTRAINT uq_dim_payment_method_name UNIQUE (method_name)
);

COMMENT ON TABLE dim_payment_method IS 'Dimensión del método de pago.';


CREATE TABLE IF NOT EXISTS dim_promo (
    promo_id        INT PRIMARY KEY,
    code            TEXT NOT NULL,
    discount_type   TEXT NOT NULL,
    discount_value  NUMERIC(10,2) NOT NULL,
    description     TEXT,
    CONSTRAINT uq_dim_promo_code UNIQUE (code),
    CONSTRAINT ck_dim_promo_discount_type CHECK (discount_type IN ('percent', 'fixed')),
    CONSTRAINT ck_dim_promo_discount_value CHECK (discount_value > 0)
);

COMMENT ON TABLE dim_promo IS 'Dimensión de promociones/cupones. Puede ser NULL en fact_rental si no aplica.';


CREATE TABLE IF NOT EXISTS dim_branch (
    branch_id     INT PRIMARY KEY,
    branch_name   TEXT NOT NULL,
    city          TEXT NOT NULL,
    province_id   INT NOT NULL REFERENCES dim_province(province_id),
    address       TEXT NOT NULL,
    timezone      TEXT NOT NULL DEFAULT 'Europe/Madrid',
    CONSTRAINT uq_dim_branch_name UNIQUE (branch_name)
);

COMMENT ON TABLE dim_branch IS 'Dimensión de sucursales (puntos de recogida/devolución).';
COMMENT ON COLUMN dim_branch.province_id IS 'FK a dim_province: provincia donde está la sucursal.';


CREATE TABLE IF NOT EXISTS dim_motorcycle (
    motorcycle_id  INT PRIMARY KEY,
    plate          TEXT NOT NULL,
    brand          TEXT NOT NULL,
    model          TEXT NOT NULL,
    category       TEXT NOT NULL,
    engine_cc      INT NOT NULL,
    model_year     SMALLINT NOT NULL,
    color          TEXT NOT NULL,
    has_gps        BOOLEAN NOT NULL DEFAULT FALSE,
    status         TEXT NOT NULL DEFAULT 'available',
    CONSTRAINT uq_dim_motorcycle_plate UNIQUE (plate),
    CONSTRAINT ck_dim_motorcycle_category CHECK (category IN ('scooter', 'manual')),
    CONSTRAINT ck_dim_motorcycle_engine_cc CHECK (engine_cc > 0),
    CONSTRAINT ck_dim_motorcycle_model_year CHECK (model_year BETWEEN 1990 AND 2100),
    CONSTRAINT ck_dim_motorcycle_status CHECK (status IN ('available', 'maintenance', 'unavailable'))
);

COMMENT ON TABLE dim_motorcycle IS 'Dimensión de motos. Incluye atributos técnicos y estado operativo.';


CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id        INT PRIMARY KEY,
    first_name         TEXT NOT NULL,
    last_name          TEXT NOT NULL,
    email              TEXT NOT NULL,
    phone              TEXT,
    nationality        CHAR(2) NOT NULL,
    is_tourist         BOOLEAN NOT NULL DEFAULT FALSE,
    created_date_key   INT NOT NULL REFERENCES dim_calendar(date_key),
    CONSTRAINT uq_dim_customer_email UNIQUE (email),
    CONSTRAINT ck_dim_customer_nationality CHECK (char_length(nationality) = 2)
);

COMMENT ON TABLE dim_customer IS 'Dimensión de clientes (datos ficticios por privacidad).';
COMMENT ON COLUMN dim_customer.created_date_key IS 'FK a dim_calendar: fecha de alta/creación del cliente.';

-- 2) Tabla de Reservas

CREATE TABLE IF NOT EXISTS fact_rental (
    rental_id            INT PRIMARY KEY,
    booking_reference    TEXT NOT NULL,
    customer_id          INT NOT NULL REFERENCES dim_customer(customer_id),
    motorcycle_id        INT NOT NULL REFERENCES dim_motorcycle(motorcycle_id),
    branch_pickup_id     INT NOT NULL REFERENCES dim_branch(branch_id),
    branch_return_id     INT NOT NULL REFERENCES dim_branch(branch_id),
    channel_id           INT NOT NULL REFERENCES dim_channel(channel_id),
    payment_method_id    INT NOT NULL REFERENCES dim_payment_method(payment_method_id),
    promo_id             INT REFERENCES dim_promo(promo_id),
    booking_date_key     INT NOT NULL REFERENCES dim_calendar(date_key),
    pickup_date_key      INT NOT NULL REFERENCES dim_calendar(date_key),
    return_date_key      INT NOT NULL REFERENCES dim_calendar(date_key),
    rental_days          INT NOT NULL,
    daily_rate           NUMERIC(12,2) NOT NULL,
    subtotal             NUMERIC(12,2) NOT NULL,
    discount_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount           NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_amount         NUMERIC(12,2) NOT NULL,
    deposit_amount       NUMERIC(12,2) NOT NULL DEFAULT 0,
    deposit_status       TEXT NOT NULL DEFAULT 'held',
    damage_fee           NUMERIC(12,2) NOT NULL DEFAULT 0,
    traffic_fines        NUMERIC(12,2) NOT NULL DEFAULT 0,
    status               TEXT NOT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_fact_rental_booking_reference UNIQUE (booking_reference),

    -- Integridad numérica básica
    CONSTRAINT ck_fact_rental_rental_days CHECK (rental_days > 0),
    CONSTRAINT ck_fact_rental_daily_rate CHECK (daily_rate >= 0),
    CONSTRAINT ck_fact_rental_subtotal CHECK (subtotal >= 0),
    CONSTRAINT ck_fact_rental_discount_amount CHECK (discount_amount >= 0),
    CONSTRAINT ck_fact_rental_tax_amount CHECK (tax_amount >= 0),
    CONSTRAINT ck_fact_rental_total_amount CHECK (total_amount >= 0),
    CONSTRAINT ck_fact_rental_deposit_amount CHECK (deposit_amount >= 0),
    CONSTRAINT ck_fact_rental_damage_fee CHECK (damage_fee >= 0),
    CONSTRAINT ck_fact_rental_traffic_fines CHECK (traffic_fines >= 0),

    -- Catálogos de estados (evita valores inconsistentes)
    CONSTRAINT ck_fact_rental_deposit_status CHECK (deposit_status IN ('held', 'released', 'partially_used')),
    CONSTRAINT ck_fact_rental_status CHECK (status IN ('active', 'completed', 'cancelled', 'no_show')),

    -- Coherencia temporal (date_key YYYYMMDD: comparar enteros para ver si funciona bien)
    CONSTRAINT ck_fact_rental_date_order_1 CHECK (booking_date_key <= pickup_date_key),
    CONSTRAINT ck_fact_rental_date_order_2 CHECK (pickup_date_key <= return_date_key)
);

COMMENT ON TABLE fact_rental IS 'Tabla de hechos: 1 fila = 1 reserva (1 moto por reserva).';
COMMENT ON COLUMN fact_rental.promo_id IS 'FK opcional a dim_promo (NULL si no aplica cupón).';
COMMENT ON COLUMN fact_rental.total_amount IS 'Total con IVA (21%) aplicado a (subtotal - discount_amount). No incluye daños/multas.';
COMMENT ON COLUMN fact_rental.damage_fee IS 'Importe por daños. Se analiza aparte (no incluido en total_amount).';
COMMENT ON COLUMN fact_rental.traffic_fines IS 'Importe por multas. Se analiza aparte (no incluido en total_amount).';

-- 3) Índices (rendimiento para EDA / reporting)

-- Búsquedas y agregaciones por fecha de reserva
CREATE INDEX IF NOT EXISTS idx_fact_rental_booking_date_key
    ON fact_rental (booking_date_key);

-- Reportes por sucursal de recogida
CREATE INDEX IF NOT EXISTS idx_fact_rental_branch_pickup_id
    ON fact_rental (branch_pickup_id);

-- Cohorts por cliente
CREATE INDEX IF NOT EXISTS idx_fact_rental_customer_id
    ON fact_rental (customer_id);

-- 4) VIEW: datos enriquecidos (uniones + campos derivados)

CREATE OR REPLACE VIEW vw_rental_enriched AS
SELECT
    fr.rental_id,
    fr.booking_reference,

    fr.status AS rental_status,
    fr.deposit_status,
    fr.created_at,

    c.customer_id,
    c.first_name,
    c.last_name,
    c.nationality,
    c.is_tourist,

    m.motorcycle_id,
    m.brand,
    m.model AS motorcycle_model,
    m.category AS motorcycle_category,
    m.engine_cc,

    bp.branch_id AS pickup_branch_id,
    bp.branch_name AS pickup_branch_name,
    bp.city AS pickup_city,
    p.province_name AS pickup_province,
    p.autonomous_community AS pickup_autonomous_community,

    br.branch_id AS return_branch_id,
    br.branch_name AS return_branch_name,

    ch.channel_name,
    pm.method_name AS payment_method,
    COALESCE(pr.code, 'NO_PROMO') AS promo_code,

    bcal.date_value AS booking_date,
    pcal.date_value AS pickup_date,
    rcal.date_value AS return_date,

    fr.rental_days,
    fr.daily_rate,

    fr.subtotal,
    fr.discount_amount,
    (fr.subtotal - fr.discount_amount) AS net_before_tax,
    fr.tax_amount,
    fr.total_amount,

    fr.deposit_amount,
    fr.damage_fee,
    fr.traffic_fines,

    CASE
        WHEN fr.damage_fee > 0 OR fr.traffic_fines > 0 THEN TRUE
        ELSE FALSE
    END AS has_incident
FROM fact_rental fr
JOIN dim_customer c ON c.customer_id = fr.customer_id
JOIN dim_motorcycle m ON m.motorcycle_id = fr.motorcycle_id
JOIN dim_branch bp ON bp.branch_id = fr.branch_pickup_id
JOIN dim_province p ON p.province_id = bp.province_id
JOIN dim_branch br ON br.branch_id = fr.branch_return_id
JOIN dim_channel ch ON ch.channel_id = fr.channel_id
JOIN dim_payment_method pm ON pm.payment_method_id = fr.payment_method_id
LEFT JOIN dim_promo pr ON pr.promo_id = fr.promo_id
JOIN dim_calendar bcal ON bcal.date_key = fr.booking_date_key
JOIN dim_calendar pcal ON pcal.date_key = fr.pickup_date_key
JOIN dim_calendar rcal ON rcal.date_key = fr.return_date_key;

COMMENT ON VIEW vw_rental_enriched IS 'Vista para análisis: fact_rental + dimensiones + campos derivados (net_before_tax, has_incident, entre otros).';

-- 5) VIEW final (resumen del negocio): provincia x mes

CREATE OR REPLACE VIEW vw_rental_summary AS
SELECT
    ve.pickup_autonomous_community,
    ve.pickup_province,
    DATE_TRUNC('month', ve.booking_date)::DATE AS booking_month,

    COUNT(*) AS total_bookings,
    COUNT(*) FILTER (WHERE ve.rental_status = 'completed') AS completed_bookings,
    COUNT(*) FILTER (WHERE ve.rental_status IN ('cancelled', 'no_show')) AS lost_bookings,

    ROUND(
        (COUNT(*) FILTER (WHERE ve.rental_status IN ('cancelled', 'no_show'))::NUMERIC / NULLIF(COUNT(*)::NUMERIC, 0)) * 100,
        2
    ) AS lost_booking_rate_pct,

    SUM(ve.total_amount) AS revenue_gross_eur,
    SUM(ve.net_before_tax) AS revenue_net_before_tax_eur,
    AVG(ve.rental_days)::NUMERIC(10,2) AS avg_rental_days,
    SUM(CASE WHEN ve.has_incident THEN 1 ELSE 0 END) AS incident_count
FROM vw_rental_enriched ve
GROUP BY
    ve.pickup_autonomous_community,
    ve.pickup_province,
    DATE_TRUNC('month', ve.booking_date)::DATE
ORDER BY
    booking_month,
    pickup_autonomous_community,
    pickup_province;

COMMENT ON VIEW vw_rental_summary IS 'Vista resumen para decisiones de negocio: provincia x mes (volumen, revenue, cancel/no_show, incidencias).';

-- 6) FUNCIÓN: revenue neto (antes de IVA) por rental_id

CREATE OR REPLACE FUNCTION fn_rental_net_revenue(p_rental_id INT)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_net NUMERIC(12,2);
BEGIN
    /*
    Interpretación:
      - Revenue neto (antes de IVA) = subtotal - discount_amount
      - Si la reserva se canceló, devolvemos 0.
    */
    SELECT
        CASE
            WHEN fr.status IN ('cancelled', 'no_show') THEN 0
            ELSE (fr.subtotal - fr.discount_amount)
        END
    INTO v_net
    FROM fact_rental fr
    WHERE fr.rental_id = p_rental_id;

    RETURN COALESCE(v_net, 0);
END;
$$;

COMMENT ON FUNCTION fn_rental_net_revenue(INT) IS 'Devuelve el revenue neto (antes de IVA) de una reserva. Cancelled/no_show => 0.';


