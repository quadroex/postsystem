# Об’єкти БД

Реалізація — `db/003_logic.sql`. Каталог об’єктів і приклади даних — `db/inspect.sql`; перевірки правил — `db/verify.sql`.

| Об’єкти | Робота |
|---|---|
| `set_actor` | Контекст активного працівника до завершення транзакції. |
| `create_customer`, `update_customer`, `delete_customer`, `restore_customer` | Клієнти, архівування й відновлення. |
| `delete_address`, `restore_address`, `delete_branch`, `restore_branch` | Архівування й відновлення адрес та відділень. |
| `create_shipment`, `add_parcel`, `change_status` | Оформлення, розрахунок ціни, контроль станів та історія. |
| `delete_shipment`, `restore_shipment` | Архівування неоплачених чернеток і скасованих відправлень. |
| `record_payment` | Оплата з блокуванням відправлення й перевіркою залишку. |
| `record_delivery_attempt`, `assign_to_run` | Спроби вручення та завантаження на рейс. |
| `fn_actor`, `fn_can_transition`, `fn_shipment_price`, `fn_shipment_balance` | Перевірка автора, переходів, ціни та заборгованості. |
| `trg_stamp_audit`, `trg_log_audit`, `trg_block_mutation` | Автор і час змін, журнал, заборона фізичного видалення або зміни історії. |
| Решта `trg_*` | Перевірки пакунків, оплат, видачі, вантажності; автоматична подія та перерахунок ціни. |
| `v_customers`, `v_shipments`, `v_parcels`, `v_payments` | Дані активних записів для репозиторіїв. |
| `v_customers_all`, `v_shipments_all`, `v_audit_log` | Перегляд архівованих записів і журналу. |
| `v_tracking_history`, `v_options`, `v_branch_directory`, `v_transport_manifest`, `v_tariffs` | Відстеження, довідники та перевезення. |

Переходи станів: `draft → accepted → in_transit → arrived → delivered`; скасування можливе з `draft` та неоплаченого `accepted`. Прийняте відправлення має хоча б один пакунок; видача вимагає повної оплати.

Ціна: `base_price + ceil(сумарна вага) × price_per_kg + declared_value × insurance_rate`, округлення до копійок. Після приймання ціна фіксується.

Процедури не завершують транзакцію: це робить Unit of Work або клієнт SQL. Застосунок передає UUID працівника; перевірка його активності та запис аудиту виконуються у БД.
