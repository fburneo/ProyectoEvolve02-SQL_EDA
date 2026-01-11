Moto Rental (España)

Archivos CSV incluidos
- dim_calendar.csv
- dim_province.csv
- dim_branch.csv
- dim_customer.csv
- dim_motorcycle.csv
- dim_channel.csv
- dim_payment_method.csv
- dim_promo.csv
- fact_rental.csv

Granularidad
- fact_rental: 1 fila = 1 reserva/alquiler (una moto por reserva).

Relaciones (FK lógicas)
- dim_branch.province_id -> dim_province.province_id
- dim_customer.created_date_key -> dim_calendar.date_key
- fact_rental.customer_id -> dim_customer.customer_id
- fact_rental.motorcycle_id -> dim_motorcycle.motorcycle_id
- fact_rental.branch_pickup_id -> dim_branch.branch_id
- fact_rental.branch_return_id -> dim_branch.branch_id
- fact_rental.channel_id -> dim_channel.channel_id
- fact_rental.payment_method_id -> dim_payment_method.payment_method_id
- fact_rental.promo_id -> dim_promo.promo_id (nullable)
- fact_rental.booking_date_key/pickup_date_key/return_date_key -> dim_calendar.date_key

Notas
- IVA asumido: 21% calculado sobre (subtotal - discount_amount).
- total_amount NO incluye daños/multas; esos campos van aparte (damage_fee, traffic_fines) para análisis.
- Datos 100% ficticios (nombres/emails de ejemplo).
