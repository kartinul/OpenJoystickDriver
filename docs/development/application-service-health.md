# Application Service Runtime Health

Run a bounded soak diagnostic against the installed application process:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless diagnose runtime \
  --seconds 300 \
  --interval-ms 1000 \
  --rss-limit-mib 0 \
  --footprint-limit-mib 512
```

Use `--json` for automation.

## Measurements

The sampler records:

- resident set size
- physical footprint, including dirty and compressed allocator pages
- linear RSS and footprint growth rates
- average process CPU
- file descriptor count and growth
- thread count and growth
- configurable high-water limits

A window shorter than 60 seconds is `insufficientData` unless a configured high-water limit is
exceeded. A stable run is evidence for the exercised workload, not proof that every path is
leak-free.

## Validation

Run the diagnostic against the signed installed build, not only `.build/debug`.

- Confirm that the sampled PID matches `ApplicationServiceManager.health()`.
- Keep a controller active for the requested window.
- Record the verdict and high-water limits.
- Reinstall or restart the application after changing its binary before collecting evidence.
