# Proyecto Módulo SQL: Diseño de Base de Datos Relacional y Análisis Exploratorio en SQL de una empresa Moto Rental en España. 

Este es un proyecto con finalidad netamente educativa. Los datos utilizados fueron extraídos manualmente de la empresa y modificado manualmente para proteger la privacidad de los datos obtenidos.

## Objetivo

Diseñé e implementé una base de datos relacional en PostgreSQL para analizar reservas de alquiler de motos con un **modelo en estrella**:
- **Hechos**: `fact_rental` (1 fila = 1 reserva)
- **Dimensiones**: calendario, provincia, sucursal, cliente, moto, canal, método de pago y promo

El entregable principal es el **EDA en SQL**: consultas ejecutables y comentadas para extraer conclusiones de negocio.

## Datos

Los CSV están en [`data/`](data/). He respetado la granularidad del conjunto de datos:
- `fact_rental`: **1 reserva = 1 moto**
- `promo_id` puede venir vacío (promo opcional)
- `total_amount` no incluye daños/multas (van aparte: `damage_fee`, `traffic_fines`)

## Archivos del proyecto

```
.
├── data/                  # CSVs de entrada
├── docs/
│   ├── ERD.png            # Diagrama ERD del modelo
│   ├── ERD.md             # Explicación corta del modelo y decisiones
│   └── EDA_Report.md      # Resumen ejecutivo (KPIs + conclusiones)
└── sql/
    ├── 01_schema.sql      # Tablas, constraints, índices, vistas y función
    ├── 02_data.sql        # Carga re-ejecutable + ejemplos DML/Transacciones
    └── 03_eda.sql         # EDA completo (CORE)
```

## Requisitos técnicos

- PostgreSQL 18.1 (estable, recomendado)
- Compatible con PostgreSQL 13+
- `psql` para ejecutar scripts

## Ejecución

```bash
psql -d tu_base_de_datos -f sql/01_schema.sql
psql -d tu_base_de_datos -f sql/02_data.sql
psql -d tu_base_de_datos -f sql/03_eda.sql
```

## Resumen de resultados

- **Reservas**: 160 (138 completadas, 10 activas, 8 canceladas, 4 no_show)
- **Rango booking_date_key**: 20250604 → 20250915
- **Revenue total (`total_amount`)**: €113.941,94
- **Revenue completado**: €99.956,76
- **Promos usadas**: 13,75%
- **Reservas perdidas (cancelled + no_show)**: 7,50%
- **Incidencias (daños o multas)**: 8,75%

Top revenue (solo reservas completadas):
- **Canal**: Phone (€24.195,52), Partner OTA (€23.103,98), WhatsApp (€20.014,61)
- **Provincia**: Girona (€32.642,65), Málaga (€24.195,52), Valencia (€23.103,98), Barcelona (€20.014,61)
- **Mejor mes**: 2025-07 (€40.344,30)

## Decisiones de diseño

Modelo en estrella para análisis; `date_key` (YYYYMMDD) como entero para uniones rápidas; constraints para integridad; promo opcional.
