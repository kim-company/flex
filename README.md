# Flex

An Elixir library for managing AWS ECS (Elastic Container Service) tasks. Flex provides a simple, high-level interface for running, monitoring, and managing Fargate and managed instance tasks.

## Installation

```elixir
def deps do
  [
    {:flex, git: "git@git.keepinmind.info:extra/flex.git"},
  ]
end
```

## Configuration

Add your AWS credentials to your application config:

```elixir
config :flex,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "us-east-1"
```

## Usage

### Running a Fargate Task

```elixir
# Define your task configuration
task = %Flex{
  id: "my-task",
  task_definition: "my-task-def:1",
  cluster_arn: "arn:aws:ecs:us-east-1:123456789:cluster/my-cluster",
  subnet_ids: ["subnet-abc123"],
  security_group_ids: ["sg-abc123"],
  container_name: "app",
  env: [
    %{name: "ENV_VAR", value: "value"}
  ],
  tags: [
    %{key: "Environment", value: "production"}
  ]
}

# Run the task
{:ok, info} = Flex.run(task)
# => {:ok, %{task_arn: "arn:aws:ecs:...", desired_status: "RUNNING", ...}}
```

### Using Capacity Providers

```elixir
task = %Flex{
  # ... other fields ...
  launch_type: {:capacity_provider, "my-capacity-provider"}
}
```

### Waiting for Task to Reach Status

```elixir
# Wait for task to be running
:ok = Flex.wait_status(cluster_arn, task_arn, "RUNNING")

# Wait for task to stop
:ok = Flex.wait_status(cluster_arn, task_arn, "STOPPED")
```

### Getting Task Information

```elixir
{:ok, info} = Flex.describe(cluster_arn, task_arn)
# => %{
#      desired_status: "RUNNING",
#      last_status: "RUNNING",
#      task_arn: "arn:aws:ecs:...",
#      network_interface: %{
#        private_ip: "10.0.1.5",
#        private_dns: "ip-10-0-1-5.ec2.internal",
#        id: "eni-abc123"
#      }
#    }
```

### Getting Public IP

```elixir
{:ok, ip} = Flex.public_ip(cluster_arn, task_arn)
# => {:ok, "54.123.45.67"}
```

### Stopping a Task

```elixir
:ok = Flex.stop(cluster_arn, task_arn, "Manual stop")
```

## Features

- **Fargate and Managed Instance Support**: Run tasks on both Fargate and capacity providers
- **Network Configuration**: Automatic awsvpc networking for Fargate with public IP assignment
- **Environment Variable Overrides**: Override container environment variables at runtime
- **Log Router Integration**: Support for log prefix configuration
- **ECS Execute Command**: Automatically enabled for all tasks
- **Exponential Backoff**: Built-in retry logic for status polling
- **Public IP Resolution**: Retrieve public IPs for both Fargate and EC2-backed tasks

## API Reference

### `Flex.run/1`

Runs an ECS task (non-blocking). Returns task information including ARN and status.

### `Flex.describe/2`

Retrieves current information about a task.

### `Flex.wait_status/3`

Blocks until a task reaches the desired status. Uses exponential backoff with a maximum wait time of ~126 seconds.

### `Flex.stop/3`

Stops a running task with a reason message.

### `Flex.public_ip/2`

Retrieves the public IPv4 address of a task (works for both Fargate and managed instances).
