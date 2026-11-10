---
title: AI connections
description: Connect an AI coding assistant to Morrow's local projects, service status, mail, and debugging tools through MCP.
group: Workspace
order: 9
---
Morrow includes a local Model Context Protocol (MCP) server. An AI app starts it when needed using the bundled `morrow` command. No extra server installation, API key, listening port, or Homebrew dependency is required.

## Connect an AI app

1. Open **Settings → AI** and enable **Connect AI apps**.
2. Choose **Add** beside Claude Desktop, Cursor, VS Code, or Windsurf.
3. Restart that AI app and approve its Morrow tools when prompted.

**Added** means the app's configuration contains Morrow; it does not mean an AI session is currently connected. Client approval and reconnection happen in the AI app. To verify a connection, ask the assistant to list your Morrow sites.

Morrow adds only its own `morrow` server entry. Other servers and preferences are preserved, and a private backup is saved beside any edited configuration file. A conflicting Morrow entry, malformed JSON, or JSON with comments is left untouched. For those files, use **Copy Setup** and merge the configuration in the client's editor. VS Code uses a `servers` object; the other supported JSON clients use `mcpServers`.

For **Codex** or **Claude Code**, use **Other apps → Copy Setup** to copy the appropriate registration command, then run it in Terminal. Morrow does not rewrite those apps' account or TOML configuration files. Other local MCP clients can use the copied JSON configuration.

## Choose what to share

- **Projects and services:** registered sites and hosting status, saved runtime installations, defaults, folder versions, and project health checks.
- **Debug data:** opt-in access to database/mail service logs, captured PHP requests, dumps, and query insights.
- **Mail:** opt-in access to captured test message summaries and original email source.

All tools are read-only. They cannot run shell commands, install software, start or stop services, change project files, execute SQL, delete mail, or read Morrow's stored credentials. The mail source tool does not mark messages as read. Project health runs the same bounded inspection as the app and does not execute project scripts.

Data you permit can be sent to your AI app's provider. Captures, logs, and test mail may contain sensitive project data. These permissions are local to this Mac and are not included in iCloud workspace sync. Turn off **Connect AI apps** to deny subsequent tool calls, including calls from clients that are already connected. Turning off either optional permission revokes that category without removing the client configuration.

## Available tools

| Tool | Result |
| --- | --- |
| `status` | Actual proxy, DNS, routing, and service state |
| `list_sites` | Registered project routes, HTTPS selections, and current hosting state |
| `site_info` | One site's configuration and folder runtime selections |
| `list_services` | Database, SMTP, and S3 IDs, versions, ports, and current state |
| `list_runtimes` | Saved runtime installations, binary availability, and defaults |
| `project_health` | Framework detection, requirements, and project readiness |
| `service_logs` | Last 32 KiB of an owned database or mail log |
| `requests` | Latest 20 captured requests, or up to 50 events for a selected request |
| `list_mail` | Up to 50 message summaries, optionally filtered by project tag or search |
| `mail_source` | First 64 KiB of a captured email's MIME source |

`site_info`, `project_health`, and `requests` accept a registered domain, site ID, or project folder. Without a site argument, they use the folder from which the client started the server, or the `--site` argument supplied at startup. They cannot inspect an arbitrary unregistered folder. The site argument selects context; it is not an access restriction on other registered sites.

Results are bounded to 512 KiB. Request messages are limited to 1 MiB. Oversized results ask the assistant to narrow its selection. Runtime lists use saved inventory; discover new installations through Morrow's Runtimes page first.

## Terminal setup

```sh
morrow mcp enable
morrow mcp add cursor
morrow mcp status
morrow mcp access debug on
morrow mcp access mail on
```

To revoke access or remove a client entry:

```sh
morrow mcp disable
morrow mcp remove cursor
```

Removing an entry requires restarting the AI client to close an existing process. Disable access first if you want existing connections denied immediately.

For manual client configuration, run `morrow mcp config` or `morrow mcp config --client vscode`. Use the installed app's bundled executable so app updates keep the connection current. `morrow mcp serve` communicates only over stdin/stdout and exits when its client disconnects; it is not an interactive Terminal prompt.

See the [CLI reference](/docs/cli-reference) for all commands and [Dumps](/docs/dumps) to enable project capture before asking an assistant to inspect requests.
