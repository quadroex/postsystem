using Npgsql;

namespace PostSystem.Data;

internal sealed class CustomerRepository(DatabaseSession session) : ICustomerRepository
{
    private const string Columns = "id, full_name, email, phone, updated_at, updated_by";

    public Task CreateAsync(CustomerDraft c, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.create_customer($1, $2, $3, $4)", cancellationToken,
            c.Id, c.FullName, c.Email, c.Phone);

    public Task UpdateAsync(CustomerDraft c, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.update_customer($1, $2, $3, $4)", cancellationToken,
            c.Id, c.FullName, c.Email, c.Phone);

    public Task DeleteAsync(Guid id, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.delete_customer($1)", cancellationToken, id);

    public Task RestoreAsync(Guid id, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.restore_customer($1)", cancellationToken, id);

    public async Task<Customer?> FindAsync(Guid id, CancellationToken cancellationToken = default) =>
        (await session.QueryAsync($"SELECT {Columns} FROM postal.v_customers WHERE id = $1",
            r => Map(r), cancellationToken, id)).SingleOrDefault();

    public async Task<Customer?> FindIncludingDeletedAsync(Guid id, CancellationToken cancellationToken = default) =>
        (await session.QueryAsync($"SELECT {Columns}, deleted_at FROM postal.v_customers_all WHERE id = $1",
            r => Map(r, true), cancellationToken, id)).SingleOrDefault();

    public Task<IReadOnlyList<Customer>> ListAsync(CancellationToken cancellationToken = default) =>
        session.QueryAsync($"SELECT {Columns} FROM postal.v_customers ORDER BY full_name, id LIMIT 100",
            r => Map(r), cancellationToken);

    private static Customer Map(NpgsqlDataReader r, bool includeDeleted = false) =>
        new(r.GetGuid(0), r.GetString(1), NullableString(r, 2), r.GetString(3), r.GetDateTime(4),
            r.GetGuid(5), includeDeleted && !r.IsDBNull(6) ? r.GetDateTime(6) : null);

    private static string? NullableString(NpgsqlDataReader r, int i) => r.IsDBNull(i) ? null : r.GetString(i);
}

internal sealed class ShipmentRepository(DatabaseSession session) : IShipmentRepository
{
    private const string Columns = "id, tracking_number, sender_id, recipient_id, sender_name, recipient_name, " +
        "origin_branch_name, destination_branch_name, status_code, price, paid_amount, updated_at, updated_by";

    public Task CreateAsync(ShipmentDraft s, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.create_shipment($1, $2, $3, $4, $5, $6, $7, $8)", cancellationToken,
            s.Id, s.TrackingNumber, s.SenderId, s.RecipientId, s.OriginBranchId, s.DestinationBranchId,
            s.ServiceTypeId, s.DeclaredValue);

    public Task ChangeStatusAsync(Guid id, int statusId, string note, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.change_status($1, $2, $3)", cancellationToken, id, statusId, note);

    public Task DeleteAsync(Guid id, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.delete_shipment($1)", cancellationToken, id);

    public Task RestoreAsync(Guid id, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.restore_shipment($1)", cancellationToken, id);

    public async Task<Shipment?> FindAsync(Guid id, CancellationToken cancellationToken = default) =>
        (await session.QueryAsync($"SELECT {Columns} FROM postal.v_shipments WHERE id = $1",
            r => Map(r), cancellationToken, id)).SingleOrDefault();

    public async Task<Shipment?> FindIncludingDeletedAsync(Guid id, CancellationToken cancellationToken = default) =>
        (await session.QueryAsync($"SELECT {Columns}, deleted_at FROM postal.v_shipments_all WHERE id = $1",
            r => Map(r, true), cancellationToken, id)).SingleOrDefault();

    public async Task<Shipment?> FindByTrackingAsync(string trackingNumber, CancellationToken cancellationToken = default) =>
        (await session.QueryAsync($"SELECT {Columns} FROM postal.v_shipments WHERE tracking_number = $1",
            r => Map(r), cancellationToken, trackingNumber)).SingleOrDefault();

    public Task<IReadOnlyList<Shipment>> ListAsync(CancellationToken cancellationToken = default) =>
        session.QueryAsync($"SELECT {Columns} FROM postal.v_shipments ORDER BY updated_at DESC, id LIMIT 100",
            r => Map(r), cancellationToken);

    public Task<IReadOnlyList<TrackingEvent>> TrackAsync(string trackingNumber, CancellationToken cancellationToken = default) =>
        session.QueryAsync("""
            SELECT tracking_number, status_code, note, occurred_at, recorded_by
            FROM postal.v_tracking_history WHERE tracking_number = $1 ORDER BY occurred_at, event_id
            """, r => new TrackingEvent(r.GetString(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2),
                r.GetDateTime(3), r.GetGuid(4)), cancellationToken, trackingNumber);

    private static Shipment Map(NpgsqlDataReader r, bool includeDeleted = false) =>
        new(r.GetGuid(0), r.GetString(1), r.GetGuid(2), r.GetGuid(3), r.GetString(4), r.GetString(5),
            r.GetString(6), r.GetString(7), r.GetString(8), r.GetDecimal(9), r.GetDecimal(10),
            r.GetDateTime(11), r.GetGuid(12), includeDeleted && !r.IsDBNull(13) ? r.GetDateTime(13) : null);
}

internal sealed class ParcelRepository(DatabaseSession session) : IParcelRepository
{
    public Task AddAsync(ParcelDraft p, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.add_parcel($1, $2, $3, $4, $5, $6, $7)", cancellationToken,
            p.Id, p.ShipmentId, p.Description, p.WeightKg, p.LengthCm, p.WidthCm, p.HeightCm);

    public Task<IReadOnlyList<Parcel>> ListAsync(Guid shipmentId, CancellationToken cancellationToken = default) =>
        session.QueryAsync("""
            SELECT id, shipment_id, description, weight_kg
            FROM postal.v_parcels WHERE shipment_id = $1 ORDER BY id
            """, r => new Parcel(r.GetGuid(0), r.GetGuid(1), r.GetString(2), r.GetDecimal(3)),
            cancellationToken, shipmentId);
}

internal sealed class PaymentRepository(DatabaseSession session) : IPaymentRepository
{
    public Task RecordAsync(PaymentDraft p, CancellationToken cancellationToken = default) =>
        session.ExecuteAsync("CALL postal.record_payment($1, $2, $3, $4, $5)", cancellationToken,
            p.Id, p.ShipmentId, p.Amount, p.PaymentMethodId, p.Reference);

    public Task<IReadOnlyList<Payment>> ListAsync(Guid shipmentId, CancellationToken cancellationToken = default) =>
        session.QueryAsync("""
            SELECT id, shipment_id, amount, method_name, reference
            FROM postal.v_payments WHERE shipment_id = $1 ORDER BY paid_at, id
            """, r => new Payment(r.GetGuid(0), r.GetGuid(1), r.GetDecimal(2), r.GetString(3),
                r.IsDBNull(4) ? null : r.GetString(4)), cancellationToken, shipmentId);
}

internal sealed class AuditRepository(DatabaseSession session) : IAuditRepository
{
    public Task<IReadOnlyList<AuditEntry>> ListAsync(Guid entityId, CancellationToken cancellationToken = default) =>
        session.QueryAsync("""
            SELECT id, entity_name, entity_id, operation, changed_by, changed_at, old_data::text, new_data::text
            FROM postal.v_audit_log WHERE entity_id = $1 ORDER BY id
            """, r => new AuditEntry(r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetString(3),
                r.GetGuid(4), r.GetDateTime(5), r.IsDBNull(6) ? null : r.GetString(6),
                r.IsDBNull(7) ? null : r.GetString(7)), cancellationToken, entityId.ToString());
}

internal sealed class ReferenceRepository(DatabaseSession session) : IReferenceRepository
{
    public Task<IReadOnlyList<ReferenceOption>> ListAsync(CancellationToken cancellationToken = default) =>
        session.QueryAsync("SELECT option_type, id, code, name FROM postal.v_options ORDER BY option_type, id",
            r => new ReferenceOption(r.GetString(0), r.GetInt32(1), r.GetString(2), r.GetString(3)), cancellationToken);
}
