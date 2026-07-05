# Serena MCP Setup

Serena is trusted-local development tooling for code navigation and editing
through the Model Context Protocol. It is not a `rails-mmd` runtime dependency.

## Install Serena

Install `uv` first. Follow the current Serena Quick Start path and install the
CLI with:

```sh
uv tool install -p 3.13 serena-agent
```

Then initialize Serena:

```sh
serena init
```

Do not install Serena through obsolete MCP/plugin marketplace shortcuts or
client-specific legacy commands. Prefer the current Serena CLI setup flow.

## Configure Codex

Prefer generated Codex configuration:

```sh
serena setup codex
```

Manual `~/.codex/config.toml` edits are allowed only when the generated setup is
unavailable or must be adapted locally. Do not commit user-local Codex config.

After setup, verify that the Serena MCP server is connected in Codex:

```text
/mcp
```

If the local Codex client cannot expose MCP status, record the reason as
skipped-environment evidence in the relevant PR.

## Create Or Activate This Project

This repository versions `.serena/project.yml`, which was created from the
repository root with an explicit Ruby language selection:

```sh
serena project create --language ruby --name rails-mmd .
```

In Codex or another MCP client, activate the project by name/path through Serena.
In a single-project client context where activation tools are intentionally
disabled, start Serena with the project:

```sh
serena start-mcp-server --project <repo-root-or-name>
```

For Codex, Serena's generated setup uses the Codex context. The official manual
shape is:

```toml
[mcp_servers.serena]
startup_timeout_sec = 15
command = "serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex"]
```

The Codex app may not start sessions in the project directory, so activate the
current repository with Serena at the start of a session when needed.

## Health Check

Run these checks from the repository root:

```sh
serena --help
test -f .serena/project.yml
grep -Fx 'project_name: "rails-mmd"' .serena/project.yml
grep -Fx '- ruby' .serena/project.yml
serena project index
```

If Serena is unavailable, if the local client cannot report MCP status, or if
indexing cannot run in the local environment, record that as
skipped-environment evidence instead of substituting another tool. For indexing
failures, record the command, exit status, local Ruby/LSP setup detail when
shown, and the first relevant error line. During this setup issue, the observed
local failure was Ruby language-server startup termination before any Ruby
source existed in the repository; the later Ruby gem bootstrap issue owns the
repo Ruby version and first analyzable Ruby files.

## Versioned And Local State

Versioned:

- `.serena/project.yml`

User-local:

- `.serena/project.local.yml`
- `~/.codex/config.toml`
- Global/user Serena configuration
- Serena caches, logs, temporary files, dashboards, and runtime state
- Serena-managed language-server dependency/cache/log locations

Serena project memories live under `.serena/memories/` and are
versionable/reviewable by design. This setup does not commit automatically
generated or onboarding memories. Future team-reviewed `.serena/memories/**`
files may be versioned only through a later human-approved issue that defines
review and revert ownership.

## Security Boundary

Serena can execute shell commands and modify files. Use it only on a trusted
local machine with a trusted client and trusted repository.

Use sandboxing for security-sensitive work or whenever the machine, repository,
client, or package-manager configuration is not fully trusted. Do not expose
Serena network services beyond localhost without an explicit future
human-approved decision.

Keep Serena tool approvals narrow unless the current task intentionally requires
file-modifying or shell-executing tools.
