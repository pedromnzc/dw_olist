-- ---------- CREATE TABLES (tudo TEXT) ----------
CREATE TABLE repositorio.customers (
    customer_id              text,
    customer_unique_id       text,
    customer_zip_code_prefix text,
    customer_city            text,
    customer_state           text
);

CREATE TABLE repositorio.geolocation (
    geolocation_zip_code_prefix text,
    geolocation_lat             text,
    geolocation_lng             text,
    geolocation_city            text,
    geolocation_state           text
);

CREATE TABLE repositorio.order_items (
    order_id            text,
    order_item_id       text,
    product_id          text,
    seller_id           text,
    shipping_limit_date text,
    price               text,
    freight_value       text
);

CREATE TABLE repositorio.order_payments (
    order_id             text,
    payment_sequential   text,
    payment_type         text,
    payment_installments text,
    payment_value        text
);

CREATE TABLE repositorio.order_reviews (
    review_id               text,
    order_id                text,
    review_score            text,
    review_comment_title    text,
    review_comment_message  text,
    review_creation_date    text,
    review_answer_timestamp text
);

CREATE TABLE repositorio.orders (
    order_id                      text,
    customer_id                   text,
    order_status                  text,
    order_purchase_timestamp      text,
    order_approved_at             text,
    order_delivered_carrier_date  text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text
);

CREATE TABLE repositorio.products (
    product_id                 text,
    product_category_name      text,
    product_name_length        text,
    product_description_length text,
    product_photos_qty         text,
    product_weight_g           text,
    product_length_cm          text,
    product_height_cm          text,
    product_width_cm           text
);

CREATE TABLE repositorio.sellers (
    seller_id              text,
    seller_zip_code_prefix text,
    seller_city            text,
    seller_state           text
);

CREATE TABLE repositorio.category_translation (
    product_category_name         text,
    product_category_name_english text
);

SELECT 'customers'    AS tabela, count(*) FROM repositorio.customers
UNION ALL SELECT 'geolocation',        count(*) FROM repositorio.geolocation
UNION ALL SELECT 'order_items',        count(*) FROM repositorio.order_items
UNION ALL SELECT 'order_payments',     count(*) FROM repositorio.order_payments
UNION ALL SELECT 'order_reviews',      count(*) FROM repositorio.order_reviews
UNION ALL SELECT 'orders',             count(*) FROM repositorio.orders
UNION ALL SELECT 'products',           count(*) FROM repositorio.products
UNION ALL SELECT 'sellers',            count(*) FROM repositorio.sellers
UNION ALL SELECT 'category_translation', count(*) FROM repositorio.category_translation;