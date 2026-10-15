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

## 5 стадія — процедури, функції, тригери та View

Виконати `db/inspect.sql`: **17 процедур, 15 функцій, 26 тригерів, 12 представлень**. Призначення об’єктів — у [переліку API](docs/database-api.md). Після встановлення всіх SQL-файлів виконати `db/verify.sql`; очікуваний результат — «Усі перевірки пройдено». `db/demo.sql` запускати один раз: він створює оплачене відправлення `PSDEMO000001` із двома пакунками й журналом змін.

## 6 стадія — індекси

Виконати `db/explain_indexes.sql`: у каталозі є **B-tree** та **GIN**, далі показано плани запитів. [Опис індексів](docs/indexes.md); SQL створення — `db/004_indexes.sql`.

## 7 стадія — Repository + Unit of Work

Налаштувати прикладний логін за [інструкцією](docs/setup.md), потім виконати:

```powershell
dotnet build PostSystem.slnx
dotnet run --project src/PostSystem.Cli -- demo
dotnet run --project tests/PostSystem.IntegrationTests
```

Очікується **17 успішних перевірок**. Демо показує спільний commit клієнтів, відправлення, пакунка й оплати, відкат помилкової операції, soft delete та аудит. Сценарії з commit залишають навчальні дані з унікальними номерами; решта відкочуються.

Реалізація: `src/PostSystem.Data/Repositories.cs`, `PostalUnitOfWork.cs`, `DatabaseSession.cs`, `ShipmentService.cs`. Репозиторії використовують одну транзакцію; читання йде через `v_*`, зміни — через `CALL`. `db/005_access.sql` закриває прикладній ролі прямий доступ до таблиць.

```powershell
dotnet run --project src/PostSystem.Cli -- list
dotnet run --project src/PostSystem.Cli -- track PSDEMO000001
dotnet run --project src/PostSystem.Cli -- help
```

Результати перевірки — [docs/verification.md](docs/verification.md). GitHub Actions повторює встановлення й перевірки на PostgreSQL 18.
