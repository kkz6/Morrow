---
title: PHP dumps and request inspection
description: Inspect PHP dumps and Laravel queries, logs, views, and jobs in a native request timeline.
group: Everyday use
order: 4.7
---
## Enable capture for a folder

Open **Settings → Dumps → Add Folder** and select a PHP project. The folder uses its selected PHP version, or your global PHP default. Morrow adds its capture bridge to that folder’s hosted PHP requests and to new script commands launched through Morrow’s PHP shim. It does not edit your source, Composer dependencies, global PHP configuration, or project environment files.

Capture is local and opt-in. It is separate from iCloud workspace recipes. Existing serving processes and queue workers are not restarted. Captured web requests use a separate PHP pool with the same selected runtime.

```sh
morrow dumps on /path/to/project
cd /path/to/project
morrow tool exec php -- artisan your:command
morrow dumps list --project /path/to/project
```

Visit the project’s Morrow-hosted URL to capture web requests. Commands using a different PHP executable, `php -r`, and proxy sites are outside this integration. Explicit `auto_prepend_file` arguments and `-n` preserve the command’s chosen behavior.

## What appears

Each request or command has its own timeline, with expandable values, source locations, and completion duration. Filter by project or event type and search request URLs, SQL, event titles, source paths, bindings, and nested captured values. The event-type filter also limits the request list to requests containing that kind of event.

| Event | Support |
| --- | --- |
| `dump()` / `dd()` | Laravel 11+ and standalone Symfony VarDumper projects |
| SQL and bindings | Laravel 11+ with uncached local configuration |
| Logs and context | Laravel 11+ with uncached local configuration |
| Blade views | Laravel 11+ with uncached local configuration |
| Queue processing, completion, failures | New Laravel workers started through Morrow’s PHP shim |
| Request duration, status, fatal errors | Captured PHP requests |

Ordinary captured `dump()` output stays out of the response. `dd()` still displays its value and terminates normally. If capture is disabled or cannot write, the regular dumper displays the value. Native `var_dump()` is not intercepted. The bridge uses your project’s existing autoloader; it does not install Symfony or Laravel.

Laravel’s cached configuration skips automatic provider registration. Use uncached configuration in your local development project for query/log/view/job events. Morrow never clears an application’s configuration cache automatically. Earlier Laravel versions and frameworks that replace Symfony’s dump handler are not supported by this automatic integration. No OpenTelemetry extension is needed.

## Request and query insights

The selected request shows its captured duration, HTTP status when available, query count, total database time, and errors. Queries taking **100 ms or longer** get an amber duration. **Needs attention** narrows the request list to captured errors, HTTP 5xx responses, slow queries, or repeated query patterns.

When a SQL shape occurs at least three times within the same request and connection, **Repeated query patterns** shows the count and combined duration. Literal strings and numbers are normalized for comparison; quoted identifiers and operators are preserved. This is a heuristic to help investigate possible N+1 work, not proof of a bug. Intentional loops and batch processing can also repeat queries.

```sh
morrow dumps insights --project /path/to/project
morrow dumps insights --project /path/to/project --issues
morrow dumps insights --project /path/to/project --json
```

The CLI and app use the same analysis. Incomplete captures say **Completion not captured** instead of guessing a duration. Summaries describe captured events only; retention and event limits still apply. Query time is a sum of captured query durations, not an exclusive portion of request time. This is not a profiler, a complete application audit, or long-term performance monitoring.

## Pause and clear

Select the folder in Dumps and turn **Capture** off. New requests stop using the bridge; existing instrumented workers also stop writing events. Restarting a worker after disabling removes the bridge completely. Existing records stay available until cleared.

```sh
morrow dumps off /path/to/project
morrow dumps clear --project /path/to/project --yes
# Clear captures for all configured folders:
morrow dumps clear --yes
```

Capture records live in private files under `~/Library/Application Support/Morrow/diagnostics`. They are not uploaded. Web capture uses a separate PHP pool over a private Unix socket, so PHP capture settings cannot leak into other sites. It adds no public network port. Pools stay grouped under Morrow; idle capture pools stop with Sites. Values can contain private application data; enable capture only for local projects you intend to inspect.

Each project keeps at most 200 request files, with up to 500 events and 1 MB per request. The viewer reads the newest 200 requests within a 16 MB preview budget. Values have depth, item, and text limits to keep the viewer responsive. Clearing captures never deletes application files or databases.

## Existing PHP bootstrap settings

Morrow refuses to enable capture if the selected PHP configuration or a project `.user.ini` already defines `auto_prepend_file`. This preserves existing instrumentation. Disable that setting yourself before enabling Morrow capture, or keep using your existing debugger.
