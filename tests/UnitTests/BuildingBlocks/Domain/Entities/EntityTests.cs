using MusicaAprender.BuildingBlocks.Domain;
using Xunit;

namespace MusicaAprender.UnitTests.BuildingBlocks.Domain.Entities;

public sealed class EntityTests
{
    [Fact]
    public void Constructor_PreservesIdentifier()
    {
        var id = Guid.NewGuid();

        var entity = new TestEntity(id);

        Assert.Equal(id, entity.Id);
    }

    private sealed class TestEntity(Guid id) : Entity<Guid>(id);
}
