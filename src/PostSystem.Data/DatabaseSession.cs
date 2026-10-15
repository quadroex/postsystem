using Npgsql;
using NpgsqlTypes;

namespace PostSystem.Data;

internal sealed class DatabaseSession(NpgsqlConnection connection, NpgsqlTransaction transaction)
{
    private bool _completed;
    private bool _faulted;
    private bool _disposed;

    public void EnsureActive()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_completed)
            throw new InvalidOperationException("Транзакцію вже завершено.");
        if (_faulted)
            throw new InvalidOperationException("Після помилки транзакцію потрібно скасувати.");
    }

    public async Task ExecuteAsync(string sql, CancellationToken cancellationToken, params object?[] values)
    {
        EnsureActive();
        try
        {
            await using var command = CreateCommand(sql, values);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch
        {
            _faulted = true;
            throw;
        }
    }

    public async Task<IReadOnlyList<T>> QueryAsync<T>(string sql, Func<NpgsqlDataReader, T> map,
        CancellationToken cancellationToken, params object?[] values)
    {
        EnsureActive();
        try
        {
            await using var command = CreateCommand(sql, values);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            var result = new List<T>();
            while (await reader.ReadAsync(cancellationToken))
                result.Add(map(reader));
            return result;
        }
        catch
        {
            _faulted = true;
            throw;
        }
    }

    public async Task CommitAsync(CancellationToken cancellationToken)
    {
        EnsureActive();
        try
        {
            await transaction.CommitAsync(cancellationToken);
            _completed = true;
        }
        catch
        {
            _faulted = true;
            throw;
        }
    }

    public async Task RollbackAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_completed)
            throw new InvalidOperationException("Транзакцію вже завершено.");
        await transaction.RollbackAsync(cancellationToken);
        _completed = true;
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        try
        {
            if (!_completed)
            {
                try { await transaction.RollbackAsync(CancellationToken.None); }
                catch (NpgsqlException) { }
            }
        }
        finally
        {
            _completed = true;
            try { await transaction.DisposeAsync(); }
            finally { await connection.DisposeAsync(); }
        }
    }

    private NpgsqlCommand CreateCommand(string sql, object?[] values)
    {
        var command = new NpgsqlCommand(sql, connection, transaction);
        foreach (var value in values)
            command.Parameters.Add(value is null
                ? new NpgsqlParameter { NpgsqlDbType = NpgsqlDbType.Text, Value = DBNull.Value }
                : new NpgsqlParameter { Value = value });
        return command;
    }
}
