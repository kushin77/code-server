# IDE Performance Profiler

The IDE performance profiler is available at `/performance-profiler` in the frontend app.

It surfaces locally recorded extension samples for activation, mount, load, and refresh work.

## Measurement hooks

- `recordExtensionProfilerSample(...)` records a single timing sample.
- `measureExtensionProfiler(...)` times synchronous work.
- `measureAsyncExtensionProfiler(...)` times async work.
- `useExtensionMountProfiler(...)` records component mount overhead.
- `useExtensionProfilerSnapshot()` reads the current local snapshot for rendering.

## Instrumented surfaces

The current profiler samples include:

- Ticket linking extension activation
- CI/CD status sidebar activation and pipeline fetches
- OpenTelemetry APM activation and refreshes
- Sentry error sidebar refreshes
- Figma embed mount and file fetches
- Docs editor mount and initial doc loads
- Feature flags panel mount and fetches
- PagerDuty incident panel mount and fetches

Samples are stored locally in the browser and can be reset from the profiler page.
