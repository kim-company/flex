# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flex is an Elixir library for managing AWS ECS (Elastic Container Service) Fargate and managed instance tasks. It provides a high-level interface for running, describing, stopping, and monitoring ECS tasks with support for both Fargate and capacity provider launch types.

## Common Commands

### Development
```bash
# Get dependencies
mix deps.get

# Compile the project
mix compile

# Format code
mix format

# Run tests (if tests exist)
mix test
```

### Usage
The library requires callers to create and provide an AWS client:

```elixir
# Create AWS client
client = AWS.Client.create("YOUR_ACCESS_KEY", "YOUR_SECRET_KEY", "us-east-1")

# Configure task
task = %Flex{
  task_definition: "my-task:1",
  subnet_ids: ["subnet-123"],
  security_group_ids: ["sg-123"],
  cluster_arn: "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"
}

# Run task
{:ok, info} = Flex.run(client, task)
```

## Architecture

### Core Module: `Flex`

The `Flex` module (lib/flex.ex) is the main and only module in this library. It provides all functionality for ECS task management.

#### Key Struct Fields
- `task_definition`: ECS task definition to run
- `subnet_ids`: List of subnet IDs for networking
- `security_group_ids`: List of security group IDs
- `cluster_arn`: ECS cluster ARN
- `launch_type`: Either `:fargate` or `{:capacity_provider, id}`
- `env`: Environment variable overrides as list of `%{key: "KEY", value: "VALUE"}`
- `container_name`: Container name for environment overrides
- `log_prefix`: Optional log prefix for log router container
- `tags`: List of tags as `%{key: "KEY", value: "VALUE"}`
- `overrides`: Additional ECS task overrides

#### Primary Functions

**`run/2`** - Launches an ECS task (non-blocking)
- Parameters: `(client, %Flex{})`
- Takes an AWS client and a `%Flex{}` struct with configuration
- Returns `{:ok, task_info}` with task details including ARN, status, and network interface
- Automatically enables ECS managed tags and execute command
- For Fargate: assigns public IP and uses awsvpc networking
- For capacity providers: applies `distinctInstance` placement constraint

**`describe/3`** - Gets current task information
- Parameters: `(client, cluster_arn, task_arn)`
- Returns same task info structure as `run/2`
- Returns `{:error, :not_found}` if task doesn't exist

**`wait_status/4`** - Blocks until task reaches desired status
- Parameters: `(client, cluster_arn, task_arn, desired_status)`
- Uses exponential backoff (base: 2 seconds, max attempts: 5)
- Total max wait time: ~126 seconds
- Desired status values: "RUNNING", "STOPPED", etc. (see AWS ECS task lifecycle docs)

**`stop/4`** - Stops a running task
- Parameters: `(client, cluster_arn, task_arn, reason)`
- Returns `:ok` even if task is already stopped/not found

**`public_ip/3`** - Gets public IPv4 address of task
- Parameters: `(client, cluster_arn, task_arn)`
- Handles both Fargate (via network interface) and managed instances (via EC2 instance)

#### Internal Architecture

**AWS Client**: Callers must create and provide an `AWS.Client` instance to all API functions. This allows for better testability and flexibility in credential management. Create a client using `AWS.Client.create(access_key_id, secret_access_key, region)`.

**Launch Types**: The library supports two launch types with different networking:
- `:fargate` - Uses Fargate with awsvpc networking, public IP assignment
- `{:capacity_provider, id}` - Uses capacity provider with managed instances

**Network Interface Handling**: Fargate tasks have network interface details embedded in task attachments. Managed instances require additional EC2 API calls to resolve public IPs via container instance and EC2 instance lookups.

**Error Handling**: Multiple AWS response formats are parsed via `parse_error/1`, which handles both XML-style and JSON error responses.

**Backoff Logic**: `wait_status` uses exponential backoff with bitwise shift: `2 <<< attempt_number` seconds.

## Dependencies

- `aws`: AWS SDK for Elixir (primary dependency for ECS, EC2 APIs)
- Requires Elixir ~> 1.12
