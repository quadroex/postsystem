# Система управління поштовими відправленнями

PostgreSQL 18 · C# / .NET 10. Відправлення між відділеннями: клієнти, посилки, відстеження, перевезення та оплата.

## 1 стадія — схема БД

Відкрити [postsystem.drawio](docs/design/postsystem.drawio) у diagrams.net через **File → Open from → Device**. На схемі наведено поля, типи, PK, FK та кратність зв’язків. [DBML](docs/design/schema.dbml) можна імпортувати в dbdiagram.io; [ER у Markdown](docs/design/er.md) доступна в GitHub.

## 2 стадія — сутності

Перевірити [каталог сутностей](docs/entities.md): 20 предметних таблиць і `audit_log`, разом **21**. Для кожної вказано призначення, поля та ключі.

## 3 стадія — вимоги, soft delete та аудит

Відкрити [вимоги R01–R18](docs/requirements.md). У `customers`, `addresses`, `branches`, `shipments` перевірити `deleted_at/deleted_by` та `updated_at/updated_by`. Функціональна перевірка після встановлення — `db/verify.sql`: архівування, відновлення, автор змін та збереження історії.

## 4 стадія — PostgreSQL

Встановити БД за [інструкцією](docs/setup.md). Таблиці й початкові дані — `db/001_schema.sql`, `db/002_seed.sql`. У pgAdmin відкрити **postsystem → Schemas → postal → Tables**: має бути 21 таблиця. Приклади номерів відстеження: `PS0000000001`, `PS0000000002`, `PS0000000003`.
