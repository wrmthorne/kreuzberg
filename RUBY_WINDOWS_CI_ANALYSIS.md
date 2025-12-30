# Ruby Windows CI Failure Analysis and Fix

## Summary
The Ruby Windows CI job fails during the native extension compilation with cargo fingerprint validation errors. The root cause is a mismatch between the cached FFI build artifacts and the Ruby extension build environment.

## Root Cause Analysis

### What's Happening
1. **FFI Caching Step**: The CI builds and caches the FFI library with `CARGO_TARGET_DIR=C:\t`
2. **Ruby Extension Build**: When building the Ruby gem native extension (`rake compile`), cargo is invoked from a nested directory: `packages/ruby/ext/kreuzberg_rb/native/`
3. **Target Directory Mismatch**: The Ruby extension compilation expects to find or reuse the FFI artifacts, but:
   - The cached FFI was built with target directory `C:\t`
   - The Ruby extension creates its own nested target directory: `packages/ruby/tmp/x64-mingw-ucrt/kreuzberg_rb/3.2.9/target/`
   - Cargo's fingerprint validation fails because the fingerprint database paths don't match

### Error Signature
```
failed to read `D:\a\kreuzberg\kreuzberg\packages\ruby\tmp\x64-mingw-ucrt\kreuzberg_rb\3.2.9\target\release\.fingerprint\kreuzberg-rb-881a73544cf77ab6\lib-kreuzberg_rb`
The system cannot find the file specified. (os error 2)
```

This error occurs because:
1. Cargo tries to read the fingerprint file from the nested tmp directory
2. The fingerprint database was created in `C:\t` (the FFI build step)
3. When the paths change, cargo can't validate if a rebuild is needed and fails

### Why Windows Only?
- **Windows Path Length**: Windows has MAX_PATH limitations (260 characters), so the build uses short paths (`C:\t`)
- **Cross-Compilation Nesting**: The Ruby native extension builder creates deeply nested `tmp/` directories, combining with the short-path workaround causes path conflicts
- **Linux/Mac**: Don't have the MAX_PATH issue, so they use normal relative paths (`target/`), avoiding the conflict
- **Cache Invalidation**: The cache key includes platform-specific hashes, but doesn't account for different CARGO_TARGET_DIR values

## Current CI Flow (Windows)

1. **Checkout repository** → Working dir: `D:\a\kreuzberg\kreuzberg\`
2. **Configure MAX_PATH mitigation** → Sets `CARGO_TARGET_DIR=C:\t`
3. **Build/restore FFI** → Builds or restores kreuzberg-ffi to `C:\t/release/`
4. **Build Ruby gem** → Runs `rake compile` from `packages/ruby/`
   - Triggers: `bundle exec rake compile`
   - Which calls: `ruby -I. ../../../../ext/kreuzberg_rb/extconf.rb`
   - Which invokes: `cargo rustc` from `packages/ruby/ext/kreuzberg_rb/native/`
   - Creates target directory: `packages/ruby/tmp/x64-mingw-ucrt/kreuzberg_rb/3.2.9/target/`
5. **Cargo fails** → Fingerprint validation errors due to path mismatch

## Solutions

### Solution 1: Clean Cargo Cache Before Ruby Build (Quick Fix)
**Risk Level**: Low
**Impact**: Slight performance hit (rebuild FFI for Ruby extension)

Add a cargo cache clean step before building the Ruby gem:

```yaml
- name: Clean cargo cache for Ruby build
  if: runner.os == 'Windows'
  shell: bash
  run: cargo clean -p kreuzberg-rb --release
```

**Location**: In `.github/workflows/ci-ruby.yaml` after "Build or restore FFI from cache" step

### Solution 2: Use Consistent CARGO_TARGET_DIR (Recommended)
**Risk Level**: Medium
**Impact**: Better caching, ensures consistency

Ensure the same `CARGO_TARGET_DIR` is used for both FFI and Ruby extension builds. Current issue is that the Ruby extension build inherits `CARGO_TARGET_DIR=C:\t` but creates its own nested structure.

Modify `packages/ruby/ext/kreuzberg_rb/extconf.rb` to respect parent CARGO_TARGET_DIR:

```ruby
# In extconf.rb, ensure FFI artifacts can be found
if ENV['CARGO_TARGET_DIR']
  ENV['CARGO_BUILD_TARGET_DIR'] = ENV['CARGO_TARGET_DIR']
end
```

### Solution 3: Disable FFI Cache for Windows Ruby Build (Most Robust)
**Risk Level**: Low
**Impact**: Slight performance cost, ensures fresh builds

Skip the FFI caching step for Windows Ruby builds, forcing a fresh compilation:

```yaml
- name: Build or restore FFI from cache
  id: ffi
  uses: ./.github/actions/build-and-cache-ffi
  with:
    platform: ${{ matrix.os }}
    ffi-crate: kreuzberg-rb
    cache-version: v1
    pdfium-version: ${{ env.PDFIUM_VERSION }}
    ort-version: ${{ env.ORT_VERSION }}
    skip-build-on-hit: ${{ runner.os != 'Windows' }}  # Skip cache hit on Windows
```

## Recommended Fix

**Implement Solution 1 (Quick) + Solution 3 (Long-term)**:

1. **Immediately**: Add cargo cache clean before Ruby extension build (minimal disruption)
2. **Long-term**: Investigate why the FFI cache causes issues with Ruby extension compilation and either:
   - Fix the caching mechanism to handle nested target directories
   - Or properly separate FFI caching from Ruby extension compilation

## Implementation

### Quick Fix (Add to `.github/workflows/ci-ruby.yaml`)

```yaml
- name: Clean cargo cache for Ruby native extension build
  if: runner.os == 'Windows'
  shell: bash
  run: |
    echo "Cleaning cargo cache to avoid fingerprint conflicts..."
    cargo clean --release -p kreuzberg-rb || true
    # Also clear the nested tmp directory cache
    rm -rf packages/ruby/tmp || true
```

Insert this step between:
- "Build or restore FFI from cache" (line ~240)
- "Print post-FFI build status (Windows)" (line ~241)

### Testing
1. Run the Windows Ruby CI job
2. Verify the "Clean cargo cache" step completes without errors
3. Verify the "Build Ruby gem" step completes successfully
4. Check that gems are built: `packages/ruby/pkg/*.gem`

## Alternative: Modify Caching Strategy

Update `.github/actions/build-and-cache-ffi/action.yml` to include target directory in cache key:

```yaml
- name: Add CARGO_TARGET_DIR to cache key
  id: adjust-cache-key
  shell: bash
  run: |
    TARGET_DIR_HASH=$(echo "${{ env.CARGO_TARGET_DIR || 'target' }}" | sha256sum | cut -c1-8)
    echo "target-dir-hash=$TARGET_DIR_HASH" >> "$GITHUB_OUTPUT"
```

Then update the cache key generation to include this hash, ensuring different target directories don't share cache entries.

## Files to Modify

1. `.github/workflows/ci-ruby.yaml` - Add cargo cache clean step
2. (Optional) `.github/actions/build-and-cache-ffi/action.yml` - Improve cache key generation
3. (Optional) `packages/ruby/ext/kreuzberg_rb/extconf.rb` - Ensure proper environment variable handling

## Related Issues

- Windows MAX_PATH limitations requiring short paths (`C:\t`, `C:\b`)
- Cross-compilation with nested build directories
- Cargo cache invalidation with different target directories
- Ruby native extension building in a separate directory tree

## References

- Cargo book on build cache: https://doc.rust-lang.org/cargo/
- Ruby native extension builds: https://guides.rubyonrails.org/extension_dependencies.html
- Windows MAX_PATH issues: https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
