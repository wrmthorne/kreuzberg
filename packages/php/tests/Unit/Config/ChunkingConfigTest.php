<?php

declare(strict_types=1);

namespace Kreuzberg\Tests\Unit\Config;

use Kreuzberg\Config\ChunkingConfig;
use PHPUnit\Framework\Attributes\CoversClass;
use PHPUnit\Framework\Attributes\Group;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * Unit tests for ChunkingConfig class.
 *
 * Tests construction with default values and property access.
 * The ChunkingConfig is defined by the extension and only supports:
 * - Constructor with no parameters
 * - Properties: maxChars (default 1000), maxOverlap (default 200), preset (nullable)
 *
 * Test Coverage:
 * - Construction with default values
 * - Property access (maxChars, maxOverlap, preset)
 */
#[CoversClass(ChunkingConfig::class)]
#[Group('unit')]
#[Group('config')]
final class ChunkingConfigTest extends TestCase
{
    #[Test]
    public function it_creates_with_default_values(): void
    {
        $config = new ChunkingConfig();

        $this->assertSame(1000, $config->maxChars);
        $this->assertSame(200, $config->maxOverlap);
        $this->assertNull($config->preset);
    }

    #[Test]
    public function it_can_access_max_chars_property(): void
    {
        $config = new ChunkingConfig();

        $this->assertIsInt($config->maxChars);
        $this->assertSame(1000, $config->maxChars);
    }

    #[Test]
    public function it_can_access_max_overlap_property(): void
    {
        $config = new ChunkingConfig();

        $this->assertIsInt($config->maxOverlap);
        $this->assertSame(200, $config->maxOverlap);
    }

    #[Test]
    public function it_can_access_preset_property(): void
    {
        $config = new ChunkingConfig();

        $this->assertNull($config->preset);
    }
}
