# Система управління поштовими відправленнями

PostgreSQL 18 · C# / .NET 10. Відправлення між відділеннями: клієнти, посилки, відстеження, перевезення та оплата.

## 1 стадія — схема БД

Відкрити [postsystem.drawio](docs/design/postsystem.drawio) у diagrams.net через **File → Open from → Device**. На схемі наведено поля, типи, PK, FK та кратність зв’язків. [DBML](docs/design/schema.dbml) можна імпортувати в dbdiagram.io; [ER у Markdown](docs/design/er.md) доступна в GitHub.

## 2 стадія — сутності

Перевірити [каталог сутностей](docs/entities.md): 20 предметних таблиць і `audit_log`, разом **21**. Для кожної вказано призначення, поля та ключі.
