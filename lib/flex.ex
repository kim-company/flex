defmodule Flex do
  use Bitwise, only_operators: true
  require Logger

  # TODO(phil): find a clearer way to describe this stuff. These are the type
  # specs/info of the associated struct fields.
  # - tags: [%{key: "key", value: "value"}]
  # - env: [%{key: "key", value: "value"}]
  # - container_name: when overriding environment vars, the container name has
  # to be specified.
  defstruct [
    :id,
    :task_definition,
    :subnet_ids,
    :security_group_ids,
    :cluster_arn,
    :tags,
    :env,
    :container_name
  ]

  # See eventual consistency guidelines at
  # https://docs.aws.amazon.com/cli/latest/reference/ecs/run-task.html#run-task
  @backoff_wait_base_secs 2

  # Mind that doing 5 attempts means blocking for 126 seconds.
  # 126 = Enum.map(0..5, fn v -> 2 <<< v end) |> Enum.sum()
  @backoff_max_attempts 5

  @doc """
  run a fargate task, non blocking. To ensure the task is actuall running, poll
  its description with `describe`.
  """
  def run(opts = %__MODULE__{}) do
    data = %{
      tags: opts.tags,
      name: opts.id,
      launchType: "FARGATE",
      taskDefinition: opts.task_definition,
      cluster: opts.cluster_arn,
      networkConfiguration: %{
        awsvpcConfiguration: %{
          assignPublicIp: "ENABLED",
          securityGroups: opts.security_group_ids,
          subnets: opts.subnet_ids
        }
      },
      overrides: %{
        containerOverrides: [
          %{
            name: opts.container_name,
            environment: opts.env
          }
        ]
      }
    }

    # See: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_RunTask.html
    case AWS.ECS.run_task(client(), data) do
      {:ok, %{"failures" => [], "tasks" => [data | []]}, _} -> take_task_info(data)
      {:error, error} -> parse_error(error)
    end
  end

  def describe(cluster_arn, task_arn) do
    data = %{
      cluster: cluster_arn,
      tasks: [task_arn]
    }

    case AWS.ECS.describe_tasks(client(), data) do
      {:ok, %{"failures" => [], "tasks" => [data]}, _} -> take_task_info(data)
      {:ok, %{"failures" => [%{"reason" => "MISSING"}], "tasks" => []}, _} -> {:error, :not_found}
      {:error, error} -> parse_error(error)
    end
  end

  @doc """
  Waits until `desired_status` is both the `last_status` and `desired_status`
  of the specified task.  Possible status values are described at
  https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle.html
  """
  def wait_status(cluster_arn, task_arn, desired_status) do
    wait_status(cluster_arn, task_arn, desired_status, @backoff_max_attempts, 0)
  end

  @doc "Stops a task. `reason` will be visibile in the console"
  def stop(cluster_arn, task_arn, reason) do
    data = %{
      cluster: cluster_arn,
      task: task_arn,
      reason: reason
    }

    case AWS.ECS.stop_task(client(), data) do
      {:ok, %{"task" => data}, _} -> take_task_info(data)
      {:error, error} -> parse_error(error)
    end
  end

  @doc "Retrieves the public IPv4 of the specified task"
  def public_ip(cluster_arn, task_arn) do
    with {:ok, task} <- describe(cluster_arn, task_arn) do
      take_public_ip(task.network_interface.id)
    end
  end

  defp client() do
    id = Application.get_env(:flex, :access_key_id)
    secret = Application.get_env(:flex, :secret_access_key)
    region = Application.get_env(:flex, :region)

    AWS.Client.create(id, secret, region)
  end

  defp find_detail([], name, :fail),
    do: {:error, "could not find #{name} within task detail attachments"}

  defp find_detail([], _, default), do: {:ok, default}

  defp find_detail([h | t], name, default) do
    case Map.get(h, "name") do
      ^name -> {:ok, Map.get(h, "value")}
      _ -> find_detail(t, name, default)
    end
  end

  defp take_net_iface(%{"attachments" => [%{"details" => details} | []]}) do
    with {:ok, pip} <- find_detail(details, "privateIPv4Address", nil),
         {:ok, pdns} <- find_detail(details, "privateDnsName", nil),
         {:ok, iface} <- find_detail(details, "networkInterfaceId", nil) do
      {:ok,
       %{
         private_ip: pip,
         private_dns: pdns,
         id: iface
       }}
    end
  end

  defp take_net_iface(%{"attachments" => []}), do: {:ok, nil}

  defp take_task_info(data) do
    with {:ok, iface} <- take_net_iface(data) do
      {:ok,
       %{
         desired_status: Map.get(data, "desiredStatus"),
         task_arn: Map.get(data, "taskArn"),
         last_status: Map.get(data, "lastStatus"),
         network_interface: iface
       }}
    end
  end

  defp parse_error(%{"Response" => %{"Errors" => %{"Error" => %{"Message" => message}}}}),
    do: {:error, message}

  defp parse_error({:unexpected_response, %{body: json}}) do
    with {:ok, body} <- Jason.decode(json) do
      {:error,
       body["message"] || body["Message"] ||
         raise("Could not find message in body: #{inspect(body)}")}
    end
  end

  defp parse_error(error), do: {:error, error}

  defp backoff_wait_secs(n), do: @backoff_wait_base_secs <<< n

  defp wait_status(_, _, desired, max_attempts, attempts) when attempts >= max_attempts do
    {:error, "wait status: task did not reach status #{desired} in #{max_attempts} calls"}
  end

  defp wait_status(cluster_arn, task_arn, desired, max_attempts, attempt) do
    case describe(cluster_arn, task_arn) do
      {:ok, %{desired_status: ^desired, last_status: ^desired}} ->
        :ok

      {:ok, %{desired_status: ^desired, last_status: status}} ->
        wait = backoff_wait_secs(attempt)

        Logger.info(
          "wait status (attempt=#{attempt + 1}, wait=#{wait}s): have #{status}, want #{desired}"
        )

        Process.sleep(wait * 1000)
        wait_status(cluster_arn, task_arn, desired, max_attempts, attempt - 1)

      {:ok, %{desired_status: other, last_status: _}} ->
        {:error, "wait status: desired status switched to #{other}"}

      {:error, reason} ->
        {:error, "wait status: #{reason}"}
    end
  end

  defp take_public_ip(eni_id) do
    data = %{
      "NetworkInterfaceId.1" => eni_id
    }

    case Flex.EC2.describe_network_interfaces(client(), data) do
      {:ok,
       %{
         "DescribeNetworkInterfacesResponse" => %{"networkInterfaceSet" => %{"item" => interface}}
       }, _http} ->
        ip =
          interface
          |> Map.get("association", %{})
          |> Map.get("publicIp")

        {:ok, ip}

      {:error, error} ->
        parse_error(error)
    end
  end
end
