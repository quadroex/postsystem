using Npgsql;

namespace PostSystem.Data;

public sealed class PostalUnitOfWorkFactory : IPostalUnitOfWorkFactory, IAsyncDisposable
{
    private readonly NpgsqlDataSource _dataSource;

    public PostalUnitOfWorkFactory(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _dataSource = NpgsqlDataSource.Create(connectionString);
    }

    public async Task<IPostalUnitOfWork> BeginAsync(Guid actorId, CancellationToken cancellationToken = default)
    {
        var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        NpgsqlTransaction transaction;
        try { transaction = await connection.BeginTransactionAsync(cancellationToken); }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }

        var session = new DatabaseSession(connection, transaction);
        try
        {
            await session.ExecuteAsync("CALL postal.set_actor($1)", cancellationToken, actorId);
            return new PostalUnitOfWork(session);
        }
        catch
        {
            await session.DisposeAsync();
            throw;
        }
    }

    public ValueTask DisposeAsync() => _dataSource.DisposeAsync();
}

internal sealed class PostalUnitOfWork : IPostalUnitOfWork
{
    private readonly DatabaseSession _session;

    public PostalUnitOfWork(DatabaseSession session)
    {
        _session = session;
        Customers = new CustomerRepository(session);
        Shipments = new ShipmentRepository(session);
        Parcels = new ParcelRepository(session);
        Payments = new PaymentRepository(session);
        Audit = new AuditRepository(session);
        References = new ReferenceRepository(session);
    }

    public ICustomerRepository Customers { get; }
    public IShipmentRepository Shipments { get; }
    public IParcelRepository Parcels { get; }
    public IPaymentRepository Payments { get; }
    public IAuditRepository Audit { get; }
    public IReferenceRepository References { get; }
    public Task CommitAsync(CancellationToken cancellationToken = default) => _session.CommitAsync(cancellationToken);
    public Task RollbackAsync(CancellationToken cancellationToken = default) => _session.RollbackAsync(cancellationToken);
    public ValueTask DisposeAsync() => _session.DisposeAsync();
}
