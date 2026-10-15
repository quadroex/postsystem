# Схема бази даних

Діаграма містить 20 предметних сутностей і технічну таблицю `audit_log`.

У [postsystem.drawio](postsystem.drawio) є повна модель та сторінки відправлень, довідників, перевезень і аудиту. Файл відкривається через **File → Open from → Device** у diagrams.net. [schema.dbml](schema.dbml) можна імпортувати в dbdiagram.io.

`PK` — первинний ключ, `FK` — зовнішній, `UK` — унікальний. `o{` означає 0..N, `||` — 1, `o|` — 0..1. Усі `*_by` посилаються на `app_users.id`; ці зв’язки окремо показано на сторінці «Аудит» у drawio.

```mermaid
erDiagram
    app_users {
        uuid id PK "NOT NULL"
        text username UK "NOT NULL"
        text full_name "NOT NULL"
        boolean is_active "NOT NULL"
    }
    countries {
        integer id PK "NOT NULL"
        char_2 code UK "NOT NULL"
        text name UK "NOT NULL"
    }
    cities {
        integer id PK "NOT NULL"
        integer country_id FK "NOT NULL"
        text name "NOT NULL"
    }
    addresses {
        integer id PK "NOT NULL"
        integer city_id FK "NOT NULL"
        text street "NOT NULL"
        text building "NOT NULL"
        text postal_code "NOT NULL"
        timestamptz created_at "NOT NULL"
        uuid created_by FK "NOT NULL"
        timestamptz updated_at "NOT NULL"
        uuid updated_by FK "NOT NULL"
        timestamptz deleted_at "NULL"
        uuid deleted_by FK "NULL"
    }
    branches {
        integer id PK "NOT NULL"
        text code UK "NOT NULL"
        text name "NOT NULL"
        integer address_id FK "NOT NULL"
        boolean is_operational "NOT NULL"
        timestamptz created_at "NOT NULL"
        uuid created_by FK "NOT NULL"
        timestamptz updated_at "NOT NULL"
        uuid updated_by FK "NOT NULL"
        timestamptz deleted_at "NULL"
        uuid deleted_by FK "NULL"
    }
    customers {
        uuid id PK "NOT NULL"
        text full_name "NOT NULL"
        text email "NOT NULL"
        text phone "NOT NULL"
        timestamptz created_at "NOT NULL"
        uuid created_by FK "NOT NULL"
        timestamptz updated_at "NOT NULL"
        uuid updated_by FK "NOT NULL"
        timestamptz deleted_at "NULL"
        uuid deleted_by FK "NULL"
    }
    service_types {
        integer id PK "NOT NULL"
        text code UK "NOT NULL"
        text name "NOT NULL"
        boolean is_active "NOT NULL"
    }
    shipment_statuses {
        integer id PK "NOT NULL"
        text code UK "NOT NULL"
        text name "NOT NULL"
        boolean is_terminal "NOT NULL"
    }
    tariffs {
        integer id PK "NOT NULL"
        integer service_type_id FK,UK "NOT NULL"
        numeric_12_2 base_price "NOT NULL"
        numeric_12_2 price_per_kg "NOT NULL"
        numeric_6_4 insurance_rate "NOT NULL"
        numeric_10_3 max_weight_kg "NOT NULL"
    }
    shipments {
        uuid id PK "NOT NULL"
        text tracking_number UK "NOT NULL"
        uuid sender_id FK "NOT NULL"
        uuid recipient_id FK "NOT NULL"
        integer origin_branch_id FK "NOT NULL"
        integer destination_branch_id FK "NOT NULL"
        integer service_type_id FK "NOT NULL"
        integer status_id FK "NOT NULL"
        numeric_12_2 declared_value "NOT NULL"
        numeric_12_2 price "NOT NULL"
        timestamptz created_at "NOT NULL"
        uuid created_by FK "NOT NULL"
        timestamptz updated_at "NOT NULL"
        uuid updated_by FK "NOT NULL"
        timestamptz deleted_at "NULL"
        uuid deleted_by FK "NULL"
    }
    parcels {
        uuid id PK "NOT NULL"
        uuid shipment_id FK "NOT NULL"
        text description "NOT NULL"
        numeric_10_3 weight_kg "NOT NULL"
        numeric_8_2 length_cm "NOT NULL"
        numeric_8_2 width_cm "NOT NULL"
        numeric_8_2 height_cm "NOT NULL"
        timestamptz created_at "NOT NULL"
        uuid created_by FK "NOT NULL"
    }
    shipment_events {
        uuid id PK "NOT NULL"
        uuid shipment_id FK "NOT NULL"
        integer status_id FK "NOT NULL"
        integer branch_id FK "NOT NULL"
        text note "NOT NULL"
        timestamptz occurred_at "NOT NULL"
        uuid recorded_by FK "NOT NULL"
    }
    delivery_attempts {
        uuid id PK "NOT NULL"
        uuid shipment_id FK "NOT NULL"
        integer branch_id FK "NOT NULL"
        integer attempt_no "NOT NULL"
        text outcome "NOT NULL"
        text note "NOT NULL"
        timestamptz attempted_at "NOT NULL"
        uuid recorded_by FK "NOT NULL"
    }
    payment_methods {
        integer id PK "NOT NULL"
        text code UK "NOT NULL"
        text name "NOT NULL"
        boolean requires_reference "NOT NULL"
        boolean is_active "NOT NULL"
    }
    payments {
        uuid id PK "NOT NULL"
        uuid shipment_id FK "NOT NULL"
        numeric_12_2 amount "NOT NULL"
        integer payment_method_id FK "NOT NULL"
        text reference UK "NULL"
        timestamptz paid_at "NOT NULL"
        uuid recorded_by FK "NOT NULL"
    }
    vehicles {
        integer id PK "NOT NULL"
        text registration_number UK "NOT NULL"
        numeric_10_3 max_load_kg "NOT NULL"
        boolean is_active "NOT NULL"
    }
    transport_routes {
        integer id PK "NOT NULL"
        text name UK "NOT NULL"
        integer origin_branch_id FK "NOT NULL"
        integer destination_branch_id FK "NOT NULL"
    }
    route_stops {
        integer id PK "NOT NULL"
        integer route_id FK "NOT NULL"
        integer branch_id FK "NOT NULL"
        integer stop_order "NOT NULL"
    }
    transport_runs {
        uuid id PK "NOT NULL"
        integer route_id FK "NOT NULL"
        integer vehicle_id FK "NOT NULL"
        timestamptz departure_at "NOT NULL"
        timestamptz arrival_at "NULL"
        text status "NOT NULL"
        uuid created_by FK "NOT NULL"
    }
    run_shipments {
        uuid run_id PK,FK "NOT NULL"
        uuid shipment_id PK,FK,UK "NOT NULL"
        timestamptz loaded_at "NOT NULL"
        uuid loaded_by FK "NOT NULL"
    }
    audit_log {
        bigint id PK "NOT NULL"
        text entity_name "NOT NULL"
        text entity_id "NOT NULL"
        text operation "NOT NULL"
        timestamptz changed_at "NOT NULL"
        uuid changed_by FK "NOT NULL"
        jsonb old_data "NULL"
        jsonb new_data "NOT NULL"
    }
    countries ||--o{ cities : "country_id"
    cities ||--o{ addresses : "city_id"
    addresses ||--o{ branches : "address_id"
    service_types ||--o| tariffs : "service_type_id"
    customers ||--o{ shipments : "sender_id"
    customers ||--o{ shipments : "recipient_id"
    branches ||--o{ shipments : "origin_branch_id"
    branches ||--o{ shipments : "destination_branch_id"
    service_types ||--o{ shipments : "service_type_id"
    shipment_statuses ||--o{ shipments : "status_id"
    shipments ||--o{ parcels : "shipment_id"
    shipments ||--o{ shipment_events : "shipment_id"
    shipment_statuses ||--o{ shipment_events : "status_id"
    branches ||--o{ shipment_events : "branch_id"
    shipments ||--o{ delivery_attempts : "shipment_id"
    branches ||--o{ delivery_attempts : "branch_id"
    shipments ||--o{ payments : "shipment_id"
    payment_methods ||--o{ payments : "payment_method_id"
    branches ||--o{ transport_routes : "origin_branch_id"
    branches ||--o{ transport_routes : "destination_branch_id"
    transport_routes ||--o{ route_stops : "route_id"
    branches ||--o{ route_stops : "branch_id"
    transport_routes ||--o{ transport_runs : "route_id"
    vehicles ||--o{ transport_runs : "vehicle_id"
    transport_runs ||--o{ run_shipments : "run_id"
    shipments ||--o| run_shipments : "shipment_id"
```

Точні типи PostgreSQL, обмеження `CHECK`, значення за замовчуванням і дії зовнішніх ключів задано в [`db/001_schema.sql`](../../db/001_schema.sql).
