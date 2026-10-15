namespace PostSystem.Data;

public interface ICustomerRepository
{
    Task CreateAsync(CustomerDraft customer, CancellationToken cancellationToken = default);
    Task UpdateAsync(CustomerDraft customer, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid id, CancellationToken cancellationToken = default);
    Task RestoreAsync(Guid id, CancellationToken cancellationToken = default);
    Task<Customer?> FindAsync(Guid id, CancellationToken cancellationToken = default);
    Task<Customer?> FindIncludingDeletedAsync(Guid id, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Customer>> ListAsync(CancellationToken cancellationToken = default);
}

public interface IShipmentRepository
{
    Task CreateAsync(ShipmentDraft shipment, CancellationToken cancellationToken = default);
    Task ChangeStatusAsync(Guid id, int statusId, string note, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid id, CancellationToken cancellationToken = default);
    Task RestoreAsync(Guid id, CancellationToken cancellationToken = default);
    Task<Shipment?> FindAsync(Guid id, CancellationToken cancellationToken = default);
    Task<Shipment?> FindIncludingDeletedAsync(Guid id, CancellationToken cancellationToken = default);
    Task<Shipment?> FindByTrackingAsync(string trackingNumber, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Shipment>> ListAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<TrackingEvent>> TrackAsync(string trackingNumber, CancellationToken cancellationToken = default);
}

public interface IParcelRepository
{
    Task AddAsync(ParcelDraft parcel, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Parcel>> ListAsync(Guid shipmentId, CancellationToken cancellationToken = default);
}

public interface IPaymentRepository
{
    Task RecordAsync(PaymentDraft payment, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Payment>> ListAsync(Guid shipmentId, CancellationToken cancellationToken = default);
}

public interface IAuditRepository
{
    Task<IReadOnlyList<AuditEntry>> ListAsync(Guid entityId, CancellationToken cancellationToken = default);
}

public interface IReferenceRepository
{
    Task<IReadOnlyList<ReferenceOption>> ListAsync(CancellationToken cancellationToken = default);
}

public interface IPostalUnitOfWork : IAsyncDisposable
{
    ICustomerRepository Customers { get; }
    IShipmentRepository Shipments { get; }
    IParcelRepository Parcels { get; }
    IPaymentRepository Payments { get; }
    IAuditRepository Audit { get; }
    IReferenceRepository References { get; }
    Task CommitAsync(CancellationToken cancellationToken = default);
    Task RollbackAsync(CancellationToken cancellationToken = default);
}

public interface IPostalUnitOfWorkFactory
{
    Task<IPostalUnitOfWork> BeginAsync(Guid actorId, CancellationToken cancellationToken = default);
}

public static class SeedData
{
    public static readonly Guid OperatorId = Guid.Parse("00000000-0000-0000-0000-000000000001");
    public const int OriginBranchId = 1;
    public const int DestinationBranchId = 2;
    public const int StandardServiceId = 1;
    public const int CardPaymentId = 2;
}
