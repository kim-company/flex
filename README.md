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

## Usage

First, create an AWS client with your credentials:

```elixir
client = AWS.Client.create(
  System.get_env("AWS_ACCESS_KEY_ID"),
  System.get_env("AWS_SECRET_ACCESS_KEY"),
  "us-east-1"
)
```

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
{:ok, info} = Flex.run(client, task)
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
:ok = Flex.wait_status(client, cluster_arn, task_arn, "RUNNING")

# Wait for task to stop
:ok = Flex.wait_status(client, cluster_arn, task_arn, "STOPPED")
```

### Getting Task Information

```elixir
{:ok, info} = Flex.describe(client, cluster_arn, task_arn)
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
{:ok, ip} = Flex.public_ip(client, cluster_arn, task_arn)
# => {:ok, "54.123.45.67"}
```

### Stopping a Task

```elixir
:ok = Flex.stop(client, cluster_arn, task_arn, "Manual stop")
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

### `Flex.run/2`

Runs an ECS task (non-blocking). Takes an AWS client and task configuration. Returns task information including ARN and status.

### `Flex.describe/3`

Retrieves current information about a task. Takes an AWS client, cluster ARN, and task ARN.

### `Flex.wait_status/4`

Blocks until a task reaches the desired status. Takes an AWS client, cluster ARN, task ARN, and desired status. Uses exponential backoff with a maximum wait time of ~126 seconds.

### `Flex.stop/4`

Stops a running task with a reason message. Takes an AWS client, cluster ARN, task ARN, and reason.

### `Flex.public_ip/3`

Retrieves the public IPv4 address of a task (works for both Fargate and managed instances). Takes an AWS client, cluster ARN, and task ARN.
