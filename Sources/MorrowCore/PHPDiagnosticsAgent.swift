import Foundation

/// Original, dependency-free PHP bridge using the project's own public Symfony
/// and Laravel APIs. Embedded so the standalone CLI has no resource dependency.
enum PHPDiagnosticsAgent {
    static let source = #"""
<?php
namespace Morrow\Diagnostics;

if (!isset($__morrow)) { return; }

final class Recorder
{
    public static array $config = [];
    private static ?string $file = null;
    private static float $started = 0;
    private static int $count = 0;
    private static bool $finished = false;
    private static bool $handling = false;
    private static $handler = null;
    private static $fallback = null;

    public static function active(): bool
    {
        $settings = @json_decode(@file_get_contents(self::$config['settings']) ?: '', true);
        foreach (is_array($settings) ? $settings : [] as $project) {
            if ($project['path'] === self::$config['project']) { return $project['enabled'] === true; }
        }
        return false;
    }

    public static function begin(string $title): void
    {
        self::$file = null;
        self::$started = microtime(true);
        self::$count = 0;
        self::$finished = false;
        if (!self::active()) { return; }
        $files = glob(self::$config['output'].'/*.jsonl') ?: [];
        sort($files);
        foreach (array_slice($files, 0, max(0, count($files) - 199)) as $file) { @unlink($file); }
        self::$file = self::$config['output'].'/'.sprintf('%020.6f', self::$started).'-'.bin2hex(random_bytes(8)).'.jsonl';
        $handle = @fopen(self::$file, 'x');
        if (!$handle) { self::$file = null; return; }
        @chmod(self::$file, 0600);
        fclose($handle);
        self::event('request', $title, ['PHP' => PHP_VERSION, 'SAPI' => PHP_SAPI]);
    }

    public static function value($value, int $depth = 0, int &$budget = 2000)
    {
        if (--$budget < 0) { return '[Value limit]'; }
        if ($depth > 5) { return '[Depth limit]'; }
        if (is_string($value)) { return strlen($value) > 4096 ? substr($value, 0, 4096).'…' : $value; }
        if (is_resource($value)) { return '[Resource: '.get_resource_type($value).']'; }
        if (is_float($value) && !is_finite($value)) { return (string) $value; }
        if (is_object($value)) { $value = ['@class' => get_class($value)] + get_object_vars($value); }
        if (is_array($value)) {
            $out = []; $count = 0;
            foreach ($value as $key => $item) {
                if (++$count > 80 || $budget <= 0) { $out['…'] = '[Item limit]'; break; }
                $out[$key] = self::value($item, $depth + 1, $budget);
            }
            return $out;
        }
        return $value;
    }

    public static function event(string $kind, string $title, $value = null): bool
    {
        try {
            if (!self::$file || self::$count >= 500 || !self::active() || !is_file(self::$file)) { return false; }
            $file = null; $line = null;
            foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 35) as $frame) {
                $path = $frame['file'] ?? '';
                $resolved = realpath($path) ?: $path;
                $root = realpath(self::$config['project']) ?: self::$config['project'];
                if (str_starts_with($resolved, $root.'/') && !str_contains($resolved, '/vendor/')) {
                    $file = self::$config['project'].substr($resolved, strlen($root)); $line = $frame['line'] ?? null; break;
                }
            }
            $event = ['id' => basename(self::$file).':'.self::$count, 'kind' => $kind, 'time' => microtime(true),
                'title' => substr($title, 0, 4096), 'value' => self::value($value), 'file' => $file, 'line' => $line];
            $json = json_encode($event, JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
            if (!$json || strlen($json) > 65536) {
                $event['value'] = '[Value exceeded the 64 KB capture limit]';
                $json = json_encode($event, JSON_INVALID_UTF8_SUBSTITUTE);
            }
            clearstatcache(true, self::$file);
            if ((@filesize(self::$file) ?: 0) + strlen($json) + 1 > 1048576) { return false; }
            ++self::$count;
            return @file_put_contents(self::$file, $json."\n", FILE_APPEND | LOCK_EX) !== false;
        } catch (\Throwable $e) { return false; }
    }

    public static function finish(?int $status = null): void
    {
        if (self::$finished) { return; }
        self::$finished = true;
        self::event('response', 'Finished', ['status' => $status, 'duration_ms' => round((microtime(true) - self::$started) * 1000, 2)]);
    }

    public static function dumps(): void
    {
        if (!class_exists(\Symfony\Component\VarDumper\VarDumper::class)) { return; }
        self::$handler ??= static function ($value) {
            if (self::$handling) { return; }
            self::$handling = true;
            try {
                $captured = self::event('dump', 'dump()', $value);
                $dd = false;
                foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 12) as $frame) {
                    if (($frame['function'] ?? '') === 'dd') { $dd = true; break; }
                }
                // dd() still displays its value and terminates normally. If the
                // capture is unavailable, preserve normal dump output as well.
                if (!$captured || $dd) {
                    if (self::$fallback) { (self::$fallback)($value); }
                    else {
                        $cloner = new \Symfony\Component\VarDumper\Cloner\VarCloner();
                        $dumper = PHP_SAPI === 'cli' ? new \Symfony\Component\VarDumper\Dumper\CliDumper() : new \Symfony\Component\VarDumper\Dumper\HtmlDumper();
                        $dumper->dump($cloner->cloneVar($value));
                    }
                }
            } finally { self::$handling = false; }
        };
        $previous = \Symfony\Component\VarDumper\VarDumper::setHandler(self::$handler);
        if ($previous !== self::$handler) { self::$fallback = $previous; }
    }
}

Recorder::$config = $__morrow;
unset($__morrow);
if (!Recorder::active()) { return; }

// Use the application’s autoloader without adding dependencies or editing it.
$autoload = Recorder::$config['project'].'/vendor/autoload.php';
if (is_file($autoload)) { require_once $autoload; }
Recorder::begin(PHP_SAPI === 'cli' ? 'CLI '.basename($_SERVER['argv'][0] ?? 'php') : ($_SERVER['REQUEST_METHOD'] ?? 'GET').' '.($_SERVER['REQUEST_URI'] ?? '/'));
Recorder::dumps();
// Modern Laravel leaves the handler alone when this format is selected.
$_SERVER['VAR_DUMPER_FORMAT'] = 'server';

register_shutdown_function(static function () {
    $error = error_get_last();
    if ($error && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) { Recorder::event('error', $error['message'], $error); }
    Recorder::finish(PHP_SAPI === 'cli' ? null : (http_response_code() ?: 200));
});

if (class_exists(\Illuminate\Support\ServiceProvider::class) && method_exists(\Illuminate\Foundation\Bootstrap\RegisterProviders::class, 'merge')) {
    class ServiceProvider extends \Illuminate\Support\ServiceProvider
    {
        public function boot(): void
        {
            $this->app->booted(static function () { Recorder::dumps(); });
            $events = $this->app['events'];
            $events->listen(\Illuminate\Database\Events\QueryExecuted::class, static function ($event) {
                Recorder::event('query', $event->sql, ['bindings' => $event->bindings, 'connection' => $event->connectionName, 'duration_ms' => $event->time]);
            });
            $events->listen(\Illuminate\Log\Events\MessageLogged::class, static function ($event) {
                Recorder::event('log', strtoupper($event->level).' '.$event->message, $event->context);
            });
            $this->app['view']->composer('*', static function ($view) { Recorder::event('view', $view->name(), ['path' => $view->getPath()]); });
            $events->listen(\Illuminate\Foundation\Http\Events\RequestHandled::class, static function ($event) { Recorder::finish($event->response->getStatusCode()); });
            $events->listen(\Illuminate\Queue\Events\JobProcessing::class, static function ($event) {
                Recorder::finish(); Recorder::begin('Job '.$event->job->resolveName());
                Recorder::event('job', 'Processing', ['queue' => $event->job->getQueue(), 'connection' => $event->connectionName]);
            });
            $events->listen(\Illuminate\Queue\Events\JobProcessed::class, static function ($event) { Recorder::event('job', 'Processed'); Recorder::finish(); });
            $events->listen(\Illuminate\Queue\Events\JobFailed::class, static function ($event) { Recorder::event('error', 'Job failed', ['exception' => $event->exception->getMessage()]); Recorder::finish(); });
        }
    }
    \Illuminate\Foundation\Bootstrap\RegisterProviders::merge([ServiceProvider::class]);
}
"""#
}
