# Сутності

Модель містить **21 таблицю: 20 предметних сутностей і 1 технічну (`audit_log`)** у схемі `postal`. Один рейс містить багато відправлень; відправлення можна призначити лише одному рейсу (`UNIQUE (shipment_id)` у `run_shipments`).

| № | Таблиця | Призначення |
|---|---|---|
| 1 | `app_users` | Працівники й службові користувачі; автори змін даних. |
| 2 | `countries` | Країни поштових адрес. |
| 3 | `cities` | Населені пункти з прив’язкою до країни. |
| 4 | `addresses` | Адреси відділень. |
| 5 | `branches` | Поштові відділення приймання та видачі. |
| 6 | `customers` | Відправники та одержувачі поштових відправлень. |
| 7 | `service_types` | Види послуг доставки. |
| 8 | `shipment_statuses` | Довідник станів відправлення. |
| 9 | `tariffs` | Чинний тариф кожного виду послуг. |
| 10 | `shipments` | Відправлення з учасниками, відділеннями, послугою та станом. |
| 11 | `parcels` | Окремі пакунки в межах одного відправлення. |
| 12 | `shipment_events` | Історія станів і місця обробки відправлення. |
| 13 | `delivery_attempts` | Спроби вручення та їх результати. |
| 14 | `payment_methods` | Способи оплати поштових послуг. |
| 15 | `payments` | Оплати за відправленнями. |
| 16 | `vehicles` | Транспорт для перевезення відправлень. |
| 17 | `transport_routes` | Маршрути між відділеннями. |
| 18 | `route_stops` | Впорядковані зупинки маршруту. |
| 19 | `transport_runs` | Рейси за маршрутом із призначеним транспортом. |
| 20 | `run_shipments` | Зв’язок рейсів і відправлень, завантажених на рейс. |
| 21 | `audit_log` | Технічний журнал змін із попереднім і новим вмістом запису. |

## Поля та ключі

`NULL` — поле необов’язкове. Для інших полів діє `NOT NULL`. Складені ключі наведено під таблицею. Значення за замовчуванням та перевірки значень — у [`001_schema.sql`](../db/001_schema.sql).

### `app_users`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `username` | `text` | UQ | ні |
| `full_name` | `text` | — | ні |
| `is_active` | `boolean` | — | ні |

### `countries`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `code` | `char(2)` | UQ | ні |
| `name` | `text` | UQ | ні |

### `cities`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `country_id` | `integer` | FK → `countries.id` | ні |
| `name` | `text` | — | ні |

Унікальна комбінація: `country_id, name`.

### `addresses`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `city_id` | `integer` | FK → `cities.id` | ні |
| `street` | `text` | — | ні |
| `building` | `text` | — | ні |
| `postal_code` | `text` | — | ні |
| `created_at` | `timestamptz` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |
| `updated_at` | `timestamptz` | — | ні |
| `updated_by` | `uuid` | FK → `app_users.id` | ні |
| `deleted_at` | `timestamptz` | — | так |
| `deleted_by` | `uuid` | FK → `app_users.id` | так |

### `branches`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `code` | `text` | UQ | ні |
| `name` | `text` | — | ні |
| `address_id` | `integer` | FK → `addresses.id` | ні |
| `is_operational` | `boolean` | — | ні |
| `created_at` | `timestamptz` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |
| `updated_at` | `timestamptz` | — | ні |
| `updated_by` | `uuid` | FK → `app_users.id` | ні |
| `deleted_at` | `timestamptz` | — | так |
| `deleted_by` | `uuid` | FK → `app_users.id` | так |

### `customers`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `full_name` | `text` | — | ні |
| `email` | `text` | — | ні |
| `phone` | `text` | — | ні |
| `created_at` | `timestamptz` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |
| `updated_at` | `timestamptz` | — | ні |
| `updated_by` | `uuid` | FK → `app_users.id` | ні |
| `deleted_at` | `timestamptz` | — | так |
| `deleted_by` | `uuid` | FK → `app_users.id` | так |

### `service_types`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `code` | `text` | UQ | ні |
| `name` | `text` | — | ні |
| `is_active` | `boolean` | — | ні |

### `shipment_statuses`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `code` | `text` | UQ | ні |
| `name` | `text` | — | ні |
| `is_terminal` | `boolean` | — | ні |

### `tariffs`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `service_type_id` | `integer` | UQ; FK → `service_types.id` | ні |
| `base_price` | `numeric(12,2)` | — | ні |
| `price_per_kg` | `numeric(12,2)` | — | ні |
| `insurance_rate` | `numeric(6,4)` | — | ні |
| `max_weight_kg` | `numeric(10,3)` | — | ні |

### `shipments`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `tracking_number` | `text` | UQ | ні |
| `sender_id` | `uuid` | FK → `customers.id` | ні |
| `recipient_id` | `uuid` | FK → `customers.id` | ні |
| `origin_branch_id` | `integer` | FK → `branches.id` | ні |
| `destination_branch_id` | `integer` | FK → `branches.id` | ні |
| `service_type_id` | `integer` | FK → `service_types.id` | ні |
| `status_id` | `integer` | FK → `shipment_statuses.id` | ні |
| `declared_value` | `numeric(12,2)` | — | ні |
| `price` | `numeric(12,2)` | — | ні |
| `created_at` | `timestamptz` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |
| `updated_at` | `timestamptz` | — | ні |
| `updated_by` | `uuid` | FK → `app_users.id` | ні |
| `deleted_at` | `timestamptz` | — | так |
| `deleted_by` | `uuid` | FK → `app_users.id` | так |

### `parcels`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `shipment_id` | `uuid` | FK → `shipments.id` | ні |
| `description` | `text` | — | ні |
| `weight_kg` | `numeric(10,3)` | — | ні |
| `length_cm` | `numeric(8,2)` | — | ні |
| `width_cm` | `numeric(8,2)` | — | ні |
| `height_cm` | `numeric(8,2)` | — | ні |
| `created_at` | `timestamptz` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |

### `shipment_events`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `shipment_id` | `uuid` | FK → `shipments.id` | ні |
| `status_id` | `integer` | FK → `shipment_statuses.id` | ні |
| `branch_id` | `integer` | FK → `branches.id` | ні |
| `note` | `text` | — | ні |
| `occurred_at` | `timestamptz` | — | ні |
| `recorded_by` | `uuid` | FK → `app_users.id` | ні |

### `delivery_attempts`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `shipment_id` | `uuid` | FK → `shipments.id` | ні |
| `branch_id` | `integer` | FK → `branches.id` | ні |
| `attempt_no` | `integer` | — | ні |
| `outcome` | `text` | — | ні |
| `note` | `text` | — | ні |
| `attempted_at` | `timestamptz` | — | ні |
| `recorded_by` | `uuid` | FK → `app_users.id` | ні |

Унікальна комбінація: `shipment_id, attempt_no`.

### `payment_methods`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `code` | `text` | UQ | ні |
| `name` | `text` | — | ні |
| `requires_reference` | `boolean` | — | ні |
| `is_active` | `boolean` | — | ні |

### `payments`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `shipment_id` | `uuid` | FK → `shipments.id` | ні |
| `amount` | `numeric(12,2)` | — | ні |
| `payment_method_id` | `integer` | FK → `payment_methods.id` | ні |
| `reference` | `text` | UQ | так |
| `paid_at` | `timestamptz` | — | ні |
| `recorded_by` | `uuid` | FK → `app_users.id` | ні |

### `vehicles`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `registration_number` | `text` | UQ | ні |
| `max_load_kg` | `numeric(10,3)` | — | ні |
| `is_active` | `boolean` | — | ні |

### `transport_routes`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `name` | `text` | UQ | ні |
| `origin_branch_id` | `integer` | FK → `branches.id` | ні |
| `destination_branch_id` | `integer` | FK → `branches.id` | ні |

### `route_stops`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `integer` | PK | ні |
| `route_id` | `integer` | FK → `transport_routes.id` | ні |
| `branch_id` | `integer` | FK → `branches.id` | ні |
| `stop_order` | `integer` | — | ні |

Унікальна комбінація: `route_id, stop_order`.

Унікальна комбінація: `route_id, branch_id`.

### `transport_runs`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `uuid` | PK | ні |
| `route_id` | `integer` | FK → `transport_routes.id` | ні |
| `vehicle_id` | `integer` | FK → `vehicles.id` | ні |
| `departure_at` | `timestamptz` | — | ні |
| `arrival_at` | `timestamptz` | — | так |
| `status` | `text` | — | ні |
| `created_by` | `uuid` | FK → `app_users.id` | ні |

### `run_shipments`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `run_id` | `uuid` | PK; FK → `transport_runs.id` | ні |
| `shipment_id` | `uuid` | PK; UQ; FK → `shipments.id` | ні |
| `loaded_at` | `timestamptz` | — | ні |
| `loaded_by` | `uuid` | FK → `app_users.id` | ні |

Складений PK: `run_id, shipment_id`.

Унікальна комбінація: `shipment_id`.

### `audit_log`

| Поле | Тип PostgreSQL | Ключ / зв’язок | NULL |
|---|---|---|---|
| `id` | `bigint` | PK | ні |
| `entity_name` | `text` | — | ні |
| `entity_id` | `text` | — | ні |
| `operation` | `text` | — | ні |
| `changed_at` | `timestamptz` | — | ні |
| `changed_by` | `uuid` | FK → `app_users.id` | ні |
| `old_data` | `jsonb` | — | так |
| `new_data` | `jsonb` | — | ні |
