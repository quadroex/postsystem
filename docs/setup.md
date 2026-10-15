# Запуск

Потрібні PostgreSQL 18, клієнт `psql` і .NET SDK 10. Локальний сервер у pgAdmin використовує порт **5433**; для іншого сервера змінити параметр порту.

## Через pgAdmin

1. У дереві сервера натиснути правою кнопкою **Databases → Create → Database**, назва `postsystem`.
2. Відкрити **Query Tool** саме для `postsystem`.
3. Послідовно відкрити й виконати `db/001_schema.sql`, `db/002_seed.sql`, `db/003_logic.sql`, `db/004_indexes.sql`.
4. Виконати `db/demo.sql` один раз, потім `db/verify.sql`. Перевірки завершуються `ROLLBACK`, приклади залишаються в базі.
5. Оновити дерево **Schemas → postal**. Тут містяться Tables, Views, Functions та Procedures.

Скрипт схеми призначений для порожньої БД. Для повторного встановлення обрати іншу назву БД.

## Через PowerShell

Із кореня репозиторію:

```powershell
$env:PGPASSWORD = '<пароль postgres>'
./scripts/Install.ps1 -Port 5433
& 'C:/Program Files/PostgreSQL/18/bin/psql.exe' -X -v ON_ERROR_STOP=1 -h localhost -p 5433 -U postgres -d postsystem -f db/demo.sql
& 'C:/Program Files/PostgreSQL/18/bin/psql.exe' -X -v ON_ERROR_STOP=1 -h localhost -p 5433 -U postgres -d postsystem -f db/verify.sql
```

`Install.ps1` створює БД за потреби й виконує встановлення однією транзакцією. Якщо схема `postal` вже існує, скрипт зупиняється.

## Доступ застосунку

```powershell
$env:POSTSYSTEM_APP_PASSWORD = '<новий пароль застосунку>'
./scripts/Create-AppLogin.ps1 -Port 5433
$env:POSTSYSTEM_CONNECTION = "Host=localhost;Port=5433;Database=postsystem;Username=postsystem_local;Password=$env:POSTSYSTEM_APP_PASSWORD"
Remove-Item Env:PGPASSWORD
```

Роль `postsystem_app` дозволяє читати представлення та виконувати процедури. Логін `postsystem_local` успадковує її права. Паролі зберігаються лише в оточенні поточного процесу; у файлах проєкту їх немає.

Команди застосунку наведено в README.
