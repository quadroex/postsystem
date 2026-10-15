using System.Globalization;
using System.Text;
using Npgsql;
using PostSystem.Data;

Console.OutputEncoding = Encoding.UTF8;
using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cancellation.Cancel(); };

try
{
    if (args.Length == 0 || args[0] is "help" or "--help" or "-h")
    {
        PrintHelp();
        return 0;
    }

    var connectionString = Environment.GetEnvironmentVariable("POSTSYSTEM_CONNECTION");
    if (string.IsNullOrWhiteSpace(connectionString))
        throw new ArgumentException("Задайте рядок підключення у змінній POSTSYSTEM_CONNECTION.");
    var actorValue = Environment.GetEnvironmentVariable("POSTSYSTEM_ACTOR_ID");
    var actorId = string.IsNullOrWhiteSpace(actorValue) ? SeedData.OperatorId : Guid.Parse(actorValue);
    await using var factory = new PostalUnitOfWorkFactory(connectionString);
    await RunAsync(factory, actorId, args, cancellation.Token);
    return 0;
}
catch (OperationCanceledException)
{
    Console.Error.WriteLine("Операцію скасовано. Незавершені зміни відкочено.");
    return 130;
}
catch (PostgresException e)
{
    Console.Error.WriteLine($"База даних відхилила операцію [{e.SqlState}]: {e.MessageText}");
    return 2;
}
catch (NpgsqlException)
{
    Console.Error.WriteLine("Не вдалося виконати запит. Перевірте сервер і POSTSYSTEM_CONNECTION.");
    return 1;
}
catch (Exception e) when (e is ArgumentException or FormatException or OverflowException or InvalidOperationException)
{
    Console.Error.WriteLine(e.Message);
    return 1;
}

static async Task RunAsync(IPostalUnitOfWorkFactory factory, Guid actorId, string[] a, CancellationToken ct)
{
    if (a[0] == "demo")
    {
        Require(a, 1);
        await DemoAsync(factory, actorId, ct);
        return;
    }

    await using var unit = await factory.BeginAsync(actorId, ct);
    switch (a[0])
    {
        case "list":
            Require(a, 1);
            foreach (var shipment in await unit.Shipments.ListAsync(ct)) PrintShipment(shipment);
            break;
        case "customers":
            Require(a, 1);
            foreach (var c in await unit.Customers.ListAsync(ct))
                Console.WriteLine($"{c.Id} | {c.FullName} | {c.Email} | {c.Phone}");
            break;
        case "options":
            Require(a, 1);
            foreach (var o in await unit.References.ListAsync(ct))
                Console.WriteLine($"{o.Type,-15} {o.Id,2} | {o.Code,-14} | {o.Name}");
            break;
        case "track":
            Require(a, 2);
            var tracked = await FindShipmentAsync(unit, a[1], ct);
            PrintShipment(tracked);
            foreach (var e in await unit.Shipments.TrackAsync(a[1], ct))
                Console.WriteLine($"{e.OccurredAt:yyyy-MM-dd HH:mm:ss} UTC | {e.Status} | {e.Note}");
            foreach (var p in await unit.Parcels.ListAsync(tracked.Id, ct))
                Console.WriteLine($"Місце: {p.Description}, {p.WeightKg:0.###} кг");
            foreach (var p in await unit.Payments.ListAsync(tracked.Id, ct))
                Console.WriteLine($"Оплата: {p.Amount:0.00} грн | {p.Method} | {p.Reference}");
            break;
        case "customer-add":
            Require(a, 4);
            var customerId = Guid.NewGuid();
            await unit.Customers.CreateAsync(new CustomerDraft(customerId, a[1], a[2], a[3]), ct);
            Console.WriteLine($"Клієнт: {customerId}");
            break;
        case "customer-update":
            Require(a, 5);
            await unit.Customers.UpdateAsync(new CustomerDraft(Guid.Parse(a[1]), a[2], a[3], a[4]), ct);
            break;
        case "customer-delete":
            Require(a, 2);
            await unit.Customers.DeleteAsync(Guid.Parse(a[1]), ct);
            break;
        case "customer-restore":
            Require(a, 2);
            await unit.Customers.RestoreAsync(Guid.Parse(a[1]), ct);
            break;
        case "create":
            Require(a, 9);
            var id = Guid.NewGuid();
            var tracking = "UA" + Guid.NewGuid().ToString("N")[..22].ToUpperInvariant();
            await unit.Shipments.CreateAsync(new ShipmentDraft(id, tracking, Guid.Parse(a[1]), Guid.Parse(a[2]),
                Number(a[3]), Number(a[4]), Number(a[5]), Amount(a[6])), ct);
            await unit.Parcels.AddAsync(new ParcelDraft(Guid.NewGuid(), id, a[8], Amount(a[7]), 30m, 20m, 10m), ct);
            PrintShipment(await unit.Shipments.FindAsync(id, ct) ?? throw new InvalidOperationException("Відправлення не знайдено."));
            break;
        case "status":
            Require(a, 4);
            var changed = await FindShipmentAsync(unit, a[1], ct);
            await unit.Shipments.ChangeStatusAsync(changed.Id, Number(a[2]), a[3], ct);
            break;
        case "pay":
            Require(a, 4, 5);
            var payable = await FindShipmentAsync(unit, a[1], ct);
            var reference = a.Length == 5 && a[4] != "-" ? a[4] : null;
            await unit.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(), payable.Id, Amount(a[2]), Number(a[3]), reference), ct);
            break;
        case "shipment-delete":
            Require(a, 2);
            await unit.Shipments.DeleteAsync(Guid.Parse(a[1]), ct);
            break;
        case "shipment-restore":
            Require(a, 2);
            await unit.Shipments.RestoreAsync(Guid.Parse(a[1]), ct);
            break;
        case "audit":
            Require(a, 2);
            foreach (var e in await unit.Audit.ListAsync(Guid.Parse(a[1]), ct))
                Console.WriteLine($"{e.Id} | {e.Entity} | {e.Operation} | {e.OccurredAt:O} | {e.ActorId}\n  Було: {e.OldData}\n  Стало: {e.NewData}");
            break;
        default:
            throw new ArgumentException("Невідома команда. Доступні команди: help.");
    }
    await unit.CommitAsync(ct);
    Console.WriteLine("Готово.");
}

static async Task DemoAsync(IPostalUnitOfWorkFactory factory, Guid actorId, CancellationToken ct)
{
    var request = SampleRegistration.Create();
    var shipment = await new ShipmentService(factory).RegisterPaidAsync(request, actorId, ct);
    Console.WriteLine("Однією транзакцією створено двох клієнтів, відправлення, місце та оплату.");
    PrintShipment(shipment);

    var rollbackId = Guid.NewGuid();
    await using (var failed = await factory.BeginAsync(actorId, ct))
    {
        await failed.Customers.CreateAsync(new CustomerDraft(rollbackId, "Перевірка відкочування",
            $"rollback.{rollbackId:N}@example.test", "+380671112233"), ct);
        try
        {
            await failed.Parcels.AddAsync(new ParcelDraft(Guid.NewGuid(), Guid.NewGuid(), "Помилкове місце", -1m, 1m, 1m, 1m), ct);
            throw new InvalidOperationException("Перевірка відкочування не спрацювала.");
        }
        catch (PostgresException e) when (e.SqlState is "23503" or "23514" or "P0002")
        {
            await failed.RollbackAsync(ct);
        }
    }

    await using (var check = await factory.BeginAsync(actorId, ct))
    {
        if (await check.Customers.FindIncludingDeletedAsync(rollbackId, ct) is not null)
            throw new InvalidOperationException("Клієнт залишився після відкочування.");
        await check.Customers.DeleteAsync(request.Recipient.Id, ct);
        if (await check.Customers.FindAsync(request.Recipient.Id, ct) is not null ||
            (await check.Customers.FindIncludingDeletedAsync(request.Recipient.Id, ct))?.DeletedAt is null)
            throw new InvalidOperationException("Перевірка Soft delete не спрацювала.");
        await check.Customers.RestoreAsync(request.Recipient.Id, ct);
        var audit = await check.Audit.ListAsync(request.Recipient.Id, ct);
        await check.CommitAsync(ct);
        Console.WriteLine($"Відкочування і Soft delete перевірено. Записів аудиту клієнта: {audit.Count}.");
    }
    await ExpectRejectedAsync(factory, actorId,
        u => u.Shipments.ChangeStatusAsync(shipment.Id, 5, "Спроба пропустити перевезення", ct), ct);
    await ExpectRejectedAsync(factory, actorId,
        u => u.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(), shipment.Id, 1m, 2,
            "OVER" + Guid.NewGuid().ToString("N")), ct), ct);
    Console.WriteLine("Заборонений перехід статусу та переплату відхилено.");
    Console.WriteLine($"Перегляд історії: track {shipment.TrackingNumber}");
}

static async Task ExpectRejectedAsync(IPostalUnitOfWorkFactory factory, Guid actorId,
    Func<IPostalUnitOfWork, Task> action, CancellationToken ct)
{
    await using var unit = await factory.BeginAsync(actorId, ct);
    try
    {
        await action(unit);
        throw new InvalidOperationException("База даних не відхилила помилкову операцію.");
    }
    catch (PostgresException e) when (e.SqlState == "23514")
    {
        await unit.RollbackAsync(ct);
    }
}

static async Task<Shipment> FindShipmentAsync(IPostalUnitOfWork unit, string tracking, CancellationToken ct) =>
    await unit.Shipments.FindByTrackingAsync(tracking, ct)
    ?? throw new ArgumentException("Активне відправлення з таким номером не знайдено.");

static void PrintShipment(Shipment s)
{
    Console.WriteLine($"{s.TrackingNumber} | {s.Status} | {s.OriginBranch} → {s.DestinationBranch}");
    Console.WriteLine($"  {s.SenderName} → {s.RecipientName} | вартість {s.TotalPrice:0.00}, сплачено {s.PaidAmount:0.00} грн | {s.Id}");
}

static int Number(string value) => int.Parse(value, NumberStyles.None, CultureInfo.InvariantCulture);
static decimal Amount(string value) => decimal.Parse(value, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign,
    CultureInfo.InvariantCulture);
static void Require(string[] values, params int[] counts)
{
    if (!counts.Contains(values.Length)) throw new ArgumentException("Неправильна кількість аргументів. Синтаксис: help.");
}

static void PrintHelp() => Console.WriteLine("""
    PostSystem — управління поштовими відправленнями

    dotnet run --project src/PostSystem.Cli -- <команда>

    demo                              Створення й оплата відправлення, перевірка відкочування та Soft delete
    list                              Останні 100 активних відправлень
    customers                         Активні клієнти, до 100 записів
    options                           Коди відділень, послуг, статусів і способів оплати
    track НОМЕР                       Відправлення, історія, місця та оплати
    customer-add "ПІБ" EMAIL ТЕЛЕФОН
    customer-update UUID "ПІБ" EMAIL ТЕЛЕФОН
    customer-delete UUID
    customer-restore UUID
    create SENDER_UUID RECIPIENT_UUID ORIGIN_ID DEST_ID SERVICE_ID VALUE WEIGHT "Опис"
    status НОМЕР STATUS_ID "Примітка"
    pay НОМЕР AMOUNT METHOD_ID [REFERENCE]
    shipment-delete UUID
    shipment-restore UUID
    audit UUID                        Автор, час, старі й нові дані змін

    create створює чернетку з одним місцем 30×20×10 см. Дробові числа: через крапку.
    Підключення: POSTSYSTEM_CONNECTION. Автор змін: POSTSYSTEM_ACTOR_ID, типово навчальний оператор.
    Інтеграційні перевірки: dotnet run --project tests/PostSystem.IntegrationTests
    """);
