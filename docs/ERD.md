# Modelo de Datos (ERD)

## Qué modela este ERD?

- **Hechos**: `fact_rental` (1 fila = 1 reserva de 1 moto).
- **Dimensiones**: `dim_*` (cliente, moto, sucursal, provincia, calendario, canal, pago, promo).

En la práctica, el análisis se centra en métricas de `fact_rental` y se cruza con dimensiones para responder “quién / qué / dónde / cuándo / cómo”.

## ERD (Mermaid)

```mermaid
erDiagram

    DIM_PROVINCE {
        int province_id PK
        string province_name UK
        string autonomous_community
    }

    DIM_CALENDAR {
        int date_key PK
        date date_value UK
        int day_of_month
        int month
        int year
        string day_name
        string month_name
        boolean is_weekend
    }

    DIM_BRANCH {
        int branch_id PK
        string branch_name UK
        string city
        int province_id FK
        string address
        string timezone
    }

    DIM_CUSTOMER {
        int customer_id PK
        string first_name
        string last_name
        string email UK
        string phone
        string nationality
        boolean is_tourist
        int created_date_key FK
    }

    DIM_MOTORCYCLE {
        int motorcycle_id PK
        string plate UK
        string brand
        string model
        string category
        int engine_cc
        int model_year
        string color
        boolean has_gps
        string status
    }

    DIM_CHANNEL {
        int channel_id PK
        string channel_name UK
    }

    DIM_PAYMENT_METHOD {
        int payment_method_id PK
        string method_name UK
    }

    DIM_PROMO {
        int promo_id PK
        string code UK
        string discount_type
        float discount_value
        string description
    }

    FACT_RENTAL {
        int rental_id PK
        string booking_reference UK
        int customer_id FK
        int motorcycle_id FK
        int branch_pickup_id FK
        int branch_return_id FK
        int channel_id FK
        int payment_method_id FK
        int promo_id FK
        int booking_date_key FK
        int pickup_date_key FK
        int return_date_key FK
        int rental_days
        float daily_rate
        float subtotal
        float discount_amount
        float tax_amount
        float total_amount
        float deposit_amount
        string deposit_status
        float damage_fee
        float traffic_fines
        string status
        datetime created_at
    }

    DIM_PROVINCE ||--o{ DIM_BRANCH : "tiene"
    DIM_CALENDAR ||--o{ DIM_CUSTOMER : "alta"

    DIM_CUSTOMER ||--o{ FACT_RENTAL : "reserva"
    DIM_MOTORCYCLE ||--o{ FACT_RENTAL : "moto"
    DIM_BRANCH ||--o{ FACT_RENTAL : "recogida"
    DIM_BRANCH ||--o{ FACT_RENTAL : "devolucion"
    DIM_CHANNEL ||--o{ FACT_RENTAL : "canal"
    DIM_PAYMENT_METHOD ||--o{ FACT_RENTAL : "pago"
    DIM_PROMO ||--o{ FACT_RENTAL : "promo"
    DIM_CALENDAR ||--o{ FACT_RENTAL : "fechas"
```

## Decisiones de diseño

- **`date_key` (YYYYMMDD)**: simplifica uniones/ordenación temporal. Cuando necesito fecha uso `TO_DATE(date_key::text, 'YYYYMMDD')`.
- **Promo opcional**: `promo_id` puede ser `NULL` (no todas las reservas usan código).
- **Integridad**: `CHECK` para catálogos (estados), `UNIQUE` para claves naturales (email, matrícula, etc.).
- **Vistas** (en `sql/01_schema.sql`):
  - `vw_rental_enriched`: fact + dimensiones + campos derivados para análisis.
  - `vw_rental_summary`: resumen provincia × mes para decisiones.


