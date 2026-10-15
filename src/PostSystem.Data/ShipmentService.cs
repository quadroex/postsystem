namespace PostSystem.Data;

public sealed record ShipmentRegistration(CustomerDraft Sender, CustomerDraft Recipient,
    ShipmentDraft Shipment, ParcelDraft Parcel, int PaymentMethodId, string PaymentReference);

public sealed class ShipmentService(IPostalUnitOfWorkFactory factory)
{
    public async Task<Shipment> RegisterPaidAsync(ShipmentRegistration request, Guid actorId,
        CancellationToken cancellationToken = default)
    {
        if (request.Shipment.SenderId != request.Sender.Id ||
            request.Shipment.RecipientId != request.Recipient.Id ||
            request.Parcel.ShipmentId != request.Shipment.Id)
            throw new ArgumentException("Ідентифікатори клієнтів, відправлення та місця не узгоджені.");

        await using var unit = await factory.BeginAsync(actorId, cancellationToken);
        await unit.Customers.CreateAsync(request.Sender, cancellationToken);
        await unit.Customers.CreateAsync(request.Recipient, cancellationToken);
        await unit.Shipments.CreateAsync(request.Shipment, cancellationToken);
        await unit.Parcels.AddAsync(request.Parcel, cancellationToken);
        await unit.Shipments.ChangeStatusAsync(request.Shipment.Id, 2, "Прийнято у відділенні", cancellationToken);
        var shipment = await unit.Shipments.FindAsync(request.Shipment.Id, cancellationToken)
            ?? throw new InvalidOperationException("Створене відправлення не знайдено.");
        await unit.Payments.RecordAsync(new PaymentDraft(Guid.NewGuid(), shipment.Id, shipment.TotalPrice,
            request.PaymentMethodId, request.PaymentReference), cancellationToken);
        var paidShipment = await unit.Shipments.FindAsync(shipment.Id, cancellationToken)
            ?? throw new InvalidOperationException("Оплачене відправлення не знайдено.");
        await unit.CommitAsync(cancellationToken);
        return paidShipment;
    }
}

public static class SampleRegistration
{
    public static ShipmentRegistration Create(string prefix = "DEMO")
    {
        var suffix = Guid.NewGuid().ToString("N");
        var sender = new CustomerDraft(Guid.NewGuid(), "Олена Коваль", $"sender.{suffix}@example.test", "+380671112233");
        var recipient = new CustomerDraft(Guid.NewGuid(), "Андрій Мельник", $"recipient.{suffix}@example.test", "+380672223344");
        var shipment = new ShipmentDraft(Guid.NewGuid(), prefix + suffix[..20].ToUpperInvariant(), sender.Id,
            recipient.Id, SeedData.OriginBranchId, SeedData.DestinationBranchId, SeedData.StandardServiceId, 1200m);
        var parcel = new ParcelDraft(Guid.NewGuid(), shipment.Id, "Книги", 2m, 30m, 20m, 10m);
        return new ShipmentRegistration(sender, recipient, shipment, parcel, SeedData.CardPaymentId, "REF" + suffix);
    }
}
