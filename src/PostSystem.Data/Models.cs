namespace PostSystem.Data;

public sealed record CustomerDraft(Guid Id, string FullName, string Email, string Phone);
public sealed record ShipmentDraft(Guid Id, string TrackingNumber, Guid SenderId, Guid RecipientId,
    int OriginBranchId, int DestinationBranchId, int ServiceTypeId, decimal DeclaredValue);
public sealed record ParcelDraft(Guid Id, Guid ShipmentId, string Description,
    decimal WeightKg, decimal LengthCm, decimal WidthCm, decimal HeightCm);
public sealed record PaymentDraft(Guid Id, Guid ShipmentId, decimal Amount, int PaymentMethodId, string? Reference);

public sealed record Customer(Guid Id, string FullName, string? Email, string Phone,
    DateTime UpdatedAt, Guid UpdatedBy, DateTime? DeletedAt = null);
public sealed record Shipment(Guid Id, string TrackingNumber, Guid SenderId, Guid RecipientId,
    string SenderName, string RecipientName, string OriginBranch, string DestinationBranch,
    string Status, decimal TotalPrice, decimal PaidAmount, DateTime UpdatedAt, Guid UpdatedBy,
    DateTime? DeletedAt = null);
public sealed record Parcel(Guid Id, Guid ShipmentId, string Description, decimal WeightKg);
public sealed record Payment(Guid Id, Guid ShipmentId, decimal Amount, string Method, string? Reference);
public sealed record TrackingEvent(string TrackingNumber, string Status, string? Note,
    DateTime OccurredAt, Guid ActorId);
public sealed record AuditEntry(long Id, string Entity, string EntityId, string Operation,
    Guid ActorId, DateTime OccurredAt, string? OldData, string? NewData);
public sealed record ReferenceOption(string Type, int Id, string Code, string Name);
