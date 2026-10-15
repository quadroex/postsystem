using System.Text;
using Npgsql;
using PostSystem.Data;

Console.OutputEncoding = Encoding.UTF8;
var connection = Environment.GetEnvironmentVariable("POSTSYSTEM_CONNECTION");
if (string.IsNullOrWhiteSpace(connection))
{
    Console.Error.WriteLine("Задайте POSTSYSTEM_CONNECTION для навчальної бази з db/001_schema.sql–004_indexes.sql.");
    return 1;
}

await using var factory = new PostalUnitOfWorkFactory(connection);
var suite = new IntegrationSuite(factory, connection);
return await suite.RunAsync();

internal sealed class IntegrationSuite(PostalUnitOfWorkFactory factory, string connectionString)
{
    private readonly Guid _actor = SeedData.OperatorId;
    private readonly ShipmentRegistration _paidRequest = SampleRegistration.Create("TEST");
    private int _passed;
    private int _failed;

    public async Task<int> RunAsync()
    {
        await TestAsync("Спільна транзакція зберігає клієнтів, відправлення, місце й оплату", PaidRegistrationAsync);
        await TestAsync("Помилка другого запису відкочує перший і його аудит", FailedSecondWriteAsync);
        await TestAsync("Dispose без Commit відкочує транзакцію", DisposeRollbackAsync);
        await TestAsync("Явний Rollback відкочує всі пов'язані сутності", ExplicitRollbackAsync);
        await TestAsync("Soft delete клієнта, відновлення та аудит автора", CustomerLifecycleAsync);
        await TestAsync("Soft delete чернетки зберігає рядок та історію", ShipmentLifecycleAsync);
        await TestAsync("Заборонений перехід статусу відхиляється", InvalidTransitionAsync);
        await TestAsync("Переплата відхиляється без нового платежу", OverpaymentAsync);
        await TestAsync("Видача неоплаченого відправлення відхиляється", UnpaidDeliveryAsync);
        await TestAsync("Прийняте відправлення не дозволяє додавати місця", AcceptedParcelAsync);
        await TestAsync("Маршрут оплаченого відправлення завершується видачею", DeliveryAsync);
        await TestAsync("Конфлікт email під час відновлення не втрачає даних", RestoreConflictAsync);
        await TestAsync("Завершений Unit of Work відхиляє повторні запити", CompletedUnitAsync);
        await TestAsync("Невідомий автор змін відхиляється", UnknownActorAsync);
        await TestAsync("Дві одночасні оплати не перевищують вартість", ConcurrentPaymentsAsync);
        await TestAsync("Роль застосунку не може читати базову таблицю", DirectTableAccessAsync);
        await TestAsync("Готівкова оплата підтримує відсутній референс", CashWithoutReferenceAsync);
        Console.WriteLine($"Перевірки: {_passed} успішно, {_failed} помилок.");
        return _failed == 0 ? 0 : 1;
    }

    private async Task PaidRegistrationAsync()
    {
        var shipment = await new ShipmentService(factory).RegisterPaidAsync(_paidRequest, _actor);
        Check(shipment.TotalPrice > 0m && shipment.PaidAmount == shipment.TotalPrice, "Відправлення не оплачене повністю.");
        await using var unit = await BeginAsync();
        var saved = await unit.Shipments.FindAsync(shipment.Id);
        Check(saved is { Status: "accepted" }, "Стан не збережено.");
        Check(await unit.Customers.FindAsync(_paidRequest.Sender.Id) is not null, "Немає відправника.");
        Check(await unit.Customers.FindAsync(_paidRequest.Recipient.Id) is not null, "Немає одержувача.");
        Check((await unit.Parcels.ListAsync(shipment.Id)).Count == 1, "Немає місця.");
        Check((await unit.Payments.ListAsync(shipment.Id)).Sum(p => p.Amount) == shipment.TotalPrice, "Оплату не збережено.");
        var events = await unit.Shipments.TrackAsync(shipment.TrackingNumber);
        Check(events.Any(e => e.Status == "accepted") && events.All(e => e.ActorId == _actor), "Історія або автор неправильні.");
        Check((await unit.Audit.ListAsync(shipment.Id)).Count > 0, "Немає аудиту відправлення.");
    }

    private async Task FailedSecondWriteAsync()
    {
        var first = NewCustomer();
        var second = NewCustomer() with { Email = first.Email };
        await using (var unit = await BeginAsync())
        {
            await unit.Customers.CreateAsync(first);
            await ExpectAsync<PostgresException>(() => unit.Customers.CreateAsync(second), e => e.SqlState == "23505");
            await ExpectAsync<InvalidOperationException>(() => unit.CommitAsync());
            await unit.RollbackAsync();
        }
        await using var verify = await BeginAsync();
        Check(await verify.Customers.FindIncludingDeletedAsync(first.Id) is null, "Перший запис залишився.");
        Check(await verify.Customers.FindIncludingDeletedAsync(second.Id) is null, "Другий запис залишився.");
        Check((await verify.Audit.ListAsync(first.Id)).Count == 0, "Аудит не відкочено.");
    }

    private async Task DisposeRollbackAsync()
    {
        var customer = NewCustomer();
        await using (var unit = await BeginAsync())
            await unit.Customers.CreateAsync(customer);
        await using var verify = await BeginAsync();
        Check(await verify.Customers.FindIncludingDeletedAsync(customer.Id) is null, "Dispose не відкотив запис.");
    }

    private async Task ExplicitRollbackAsync()
    {
        var request = SampleRegistration.Create("ROLL");
        await using (var unit = await BeginAsync())
        {
            await CreateDraftAsync(unit, request);
            await unit.Shipments.ChangeStatusAsync(request.Shipment.Id, 2, "Прийнято");
            var shipment = await unit.Shipments.FindAsync(request.Shipment.Id) ?? throw new InvalidOperationException("Немає чернетки.");
            await unit.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(), shipment.Id, shipment.TotalPrice, 2, "ROLL" + shipment.Id.ToString("N")));
            await unit.RollbackAsync();
        }
        await using var verify = await BeginAsync();
        Check(await verify.Shipments.FindIncludingDeletedAsync(request.Shipment.Id) is null, "Відправлення не відкочено.");
        Check(await verify.Customers.FindIncludingDeletedAsync(request.Sender.Id) is null, "Клієнта не відкочено.");
        Check((await verify.Parcels.ListAsync(request.Shipment.Id)).Count == 0, "Місце не відкочено.");
        Check((await verify.Payments.ListAsync(request.Shipment.Id)).Count == 0, "Платіж не відкочено.");
        Check((await verify.Audit.ListAsync(request.Shipment.Id)).Count == 0, "Аудит не відкочено.");
    }

    private async Task CustomerLifecycleAsync()
    {
        var customer = NewCustomer();
        await using var unit = await BeginAsync();
        await unit.Customers.CreateAsync(customer);
        var original = await unit.Customers.FindAsync(customer.Id) ?? throw new InvalidOperationException("Клієнта не створено.");
        var updated = customer with { FullName = "Оновлене ім'я" };
        await unit.Customers.UpdateAsync(updated);
        var changed = await unit.Customers.FindAsync(customer.Id);
        Check(changed?.FullName == updated.FullName && changed.UpdatedBy == _actor && changed.UpdatedAt >= original.UpdatedAt,
            "Автор або час зміни не оновлені.");
        await unit.Customers.DeleteAsync(customer.Id);
        Check(await unit.Customers.FindAsync(customer.Id) is null, "Видалений клієнт видимий в активному розрізі.");
        var deleted = await unit.Customers.FindIncludingDeletedAsync(customer.Id);
        Check(deleted?.DeletedAt is not null && deleted.UpdatedBy == _actor, "Рядок або автор видалення втрачені.");
        await unit.Customers.RestoreAsync(customer.Id);
        Check((await unit.Customers.FindIncludingDeletedAsync(customer.Id)) is { DeletedAt: null }, "Клієнта не відновлено.");
        var audit = await unit.Audit.ListAsync(customer.Id);
        Check(audit.Count >= 4 && audit.All(a => a.ActorId == _actor), "Аудит життєвого циклу неповний.");
        Check(audit.Any(a => a.OldData?.Contains(customer.FullName, StringComparison.Ordinal) == true &&
            a.NewData?.Contains(updated.FullName, StringComparison.Ordinal) == true), "У журналі немає старого та нового імені.");
    }

    private async Task ShipmentLifecycleAsync()
    {
        var request = SampleRegistration.Create("SOFT");
        await using var unit = await BeginAsync();
        await CreateDraftAsync(unit, request);
        await unit.Shipments.DeleteAsync(request.Shipment.Id);
        Check(await unit.Shipments.FindAsync(request.Shipment.Id) is null, "Видалена чернетка видима.");
        Check((await unit.Shipments.FindIncludingDeletedAsync(request.Shipment.Id))?.DeletedAt is not null, "Рядок чернетки втрачено.");
        await unit.Shipments.RestoreAsync(request.Shipment.Id);
        Check(await unit.Shipments.FindAsync(request.Shipment.Id) is not null, "Чернетку не відновлено.");
        Check((await unit.Parcels.ListAsync(request.Shipment.Id)).Count == 1, "Місце втрачено після відновлення.");
        Check((await unit.Shipments.TrackAsync(request.Shipment.TrackingNumber)).Count > 0, "Історію втрачено.");
    }

    private Task InvalidTransitionAsync() => ExpectRuleAsync(unit =>
        unit.Shipments.ChangeStatusAsync(_paidRequest.Shipment.Id, 5, "Пропущено перевезення"));

    private async Task OverpaymentAsync()
    {
        await ExpectRuleAsync(unit => unit.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(),
            _paidRequest.Shipment.Id, 1m, 2, "OVER" + Guid.NewGuid().ToString("N"))));
        await using var verify = await BeginAsync();
        Check((await verify.Payments.ListAsync(_paidRequest.Shipment.Id)).Count == 1, "Невдала переплата залишила платіж.");
    }

    private async Task UnpaidDeliveryAsync()
    {
        var request = SampleRegistration.Create("DEBT");
        await ExpectRuleAsync(async unit =>
        {
            await CreateDraftAsync(unit, request);
            foreach (var status in new[] { 2, 3, 4 })
                await unit.Shipments.ChangeStatusAsync(request.Shipment.Id, status, "Перевірка боргу");
            await unit.Shipments.ChangeStatusAsync(request.Shipment.Id, 5, "Спроба видачі");
        });
        await using var verify = await BeginAsync();
        Check(await verify.Shipments.FindIncludingDeletedAsync(request.Shipment.Id) is null, "Невдалу транзакцію не відкочено.");
    }

    private Task AcceptedParcelAsync() => ExpectRuleAsync(unit =>
        unit.Parcels.AddAsync(new ParcelDraft(Guid.NewGuid(), _paidRequest.Shipment.Id, "Зайве місце", 1m, 10m, 10m, 10m)));

    private async Task DeliveryAsync()
    {
        await using (var unit = await BeginAsync())
        {
            foreach (var status in new[] { 3, 4, 5 })
                await unit.Shipments.ChangeStatusAsync(_paidRequest.Shipment.Id, status, "Перевірка доставки");
            await unit.CommitAsync();
        }
        await using var verify = await BeginAsync();
        Check((await verify.Shipments.FindAsync(_paidRequest.Shipment.Id)) is { Status: "delivered" }, "Видачу не збережено.");
        var events = await verify.Shipments.TrackAsync(_paidRequest.Shipment.TrackingNumber);
        Check(new[] { "draft", "accepted", "in_transit", "arrived", "delivered" }.All(s => events.Any(e => e.Status == s)),
            "Історія доставки неповна.");
    }

    private async Task RestoreConflictAsync()
    {
        var original = NewCustomer();
        var replacement = NewCustomer() with { Email = original.Email };
        await using (var unit = await BeginAsync())
        {
            await unit.Customers.CreateAsync(original);
            await unit.Customers.DeleteAsync(original.Id);
            await unit.Customers.CreateAsync(replacement);
            await ExpectAsync<PostgresException>(() => unit.Customers.RestoreAsync(original.Id), e => e.SqlState == "23505");
            await unit.RollbackAsync();
        }
        await using var verify = await BeginAsync();
        Check(await verify.Customers.FindIncludingDeletedAsync(original.Id) is null, "Невдале відновлення не відкочено.");
        Check(await verify.Customers.FindIncludingDeletedAsync(replacement.Id) is null, "Заміщувальний клієнт залишився.");
    }

    private async Task CompletedUnitAsync()
    {
        await using var unit = await BeginAsync();
        await unit.CommitAsync();
        await ExpectAsync<InvalidOperationException>(() => unit.Customers.ListAsync());
        await ExpectAsync<InvalidOperationException>(() => unit.CommitAsync());
    }

    private Task UnknownActorAsync() => ExpectAsync<PostgresException>(async () =>
    {
        await using var unit = await factory.BeginAsync(Guid.NewGuid());
    }, e => e.SqlState == "28000");

    private async Task ConcurrentPaymentsAsync()
    {
        var request = SampleRegistration.Create("RACE");
        decimal price;
        await using (var setup = await BeginAsync())
        {
            await CreateDraftAsync(setup, request);
            await setup.Shipments.ChangeStatusAsync(request.Shipment.Id, 2, "Перевірка одночасних оплат");
            price = (await setup.Shipments.FindAsync(request.Shipment.Id))?.TotalPrice
                ?? throw new InvalidOperationException("Не вдалося прочитати вартість.");
            await setup.CommitAsync();
        }

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var ready = 0;
        async Task<bool> PayAsync()
        {
            await using var unit = await factory.BeginAsync(_actor, timeout.Token);
            if (Interlocked.Increment(ref ready) == 2) gate.SetResult();
            await gate.Task.WaitAsync(timeout.Token);
            try
            {
                await unit.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(), request.Shipment.Id, price,
                    2, "RACE" + Guid.NewGuid().ToString("N")), timeout.Token);
                await unit.CommitAsync(timeout.Token);
                return true;
            }
            catch (PostgresException e) when (e.SqlState == "23514")
            {
                await unit.RollbackAsync();
                return false;
            }
        }

        var results = await Task.WhenAll(PayAsync(), PayAsync());
        Check(results.Count(r => r) == 1, "Обидві оплати пройшли або обидві відхилено.");
        await using var verify = await BeginAsync();
        var payments = await verify.Payments.ListAsync(request.Shipment.Id);
        Check(payments.Count == 1 && payments.Sum(p => p.Amount) == price, "Після гонки збережено неправильну суму.");
    }

    private async Task ExpectRuleAsync(Func<IPostalUnitOfWork, Task> action)
    {
        await using var unit = await BeginAsync();
        await ExpectAsync<PostgresException>(() => action(unit), e => e.SqlState == "23514");
        await unit.RollbackAsync();
    }

    private async Task DirectTableAccessAsync()
    {
        await using var source = NpgsqlDataSource.Create(connectionString);
        await using var command = source.CreateCommand("SELECT id FROM postal.shipments LIMIT 1");
        await ExpectAsync<PostgresException>(async () => { await command.ExecuteScalarAsync(); },
            e => e.SqlState == "42501");
    }

    private async Task CashWithoutReferenceAsync()
    {
        var request = SampleRegistration.Create("CASH");
        await using var unit = await BeginAsync();
        await CreateDraftAsync(unit, request);
        await unit.Shipments.ChangeStatusAsync(request.Shipment.Id, 2, "Оплата готівкою");
        var paymentId = Guid.NewGuid();
        await unit.Payments.RecordAsync(new PaymentDraft(paymentId, request.Shipment.Id, 10m, 1, null));
        var payment = (await unit.Payments.ListAsync(request.Shipment.Id)).Single(p => p.Id == paymentId);
        Check(payment.Reference is null && payment.Amount == 10m, "Платіж без референсу збережено неправильно.");
    }

    private async Task TestAsync(string name, Func<Task> test)
    {
        try
        {
            await test();
            _passed++;
            Console.WriteLine($"PASS {name}");
        }
        catch (Exception e)
        {
            _failed++;
            var reason = e is PostgresException p ? $"[{p.SqlState}] {p.MessageText}" : e.Message;
            Console.Error.WriteLine($"FAIL {name}: {reason}");
        }
    }

    private Task<IPostalUnitOfWork> BeginAsync() => factory.BeginAsync(_actor);

    private static async Task CreateDraftAsync(IPostalUnitOfWork unit, ShipmentRegistration request)
    {
        await unit.Customers.CreateAsync(request.Sender);
        await unit.Customers.CreateAsync(request.Recipient);
        await unit.Shipments.CreateAsync(request.Shipment);
        await unit.Parcels.AddAsync(request.Parcel);
    }

    private static CustomerDraft NewCustomer()
    {
        var id = Guid.NewGuid();
        return new CustomerDraft(id, "Тестовий клієнт", $"test.{id:N}@example.test", "+380671112233");
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static async Task ExpectAsync<T>(Func<Task> action, Func<T, bool>? predicate = null) where T : Exception
    {
        try { await action(); }
        catch (T e) when (predicate is null || predicate(e)) { return; }
        throw new InvalidOperationException($"Очікувався виняток {typeof(T).Name}.");
    }
}
