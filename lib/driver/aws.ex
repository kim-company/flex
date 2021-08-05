defmodule Driver.AWS do
  defstruct [:port, :sec_group, :task_def, :subnets, :cluster, :container_name, :task_arn, :env, :vars, :dir]

  @poll_delay 4000
  @aws_access_key_id "AWS_ACCESS_KEY_ID"
  @aws_secret_access_key "AWS_SECRET_ACCESS_KEY"
  @aws_region "AWS_REGION"

  defp client() do
    id = System.get_env(@aws_access_key_id)
    secret = System.get_env(@aws_secret_access_key)
    region = System.get_env(@aws_region)
    AWS.Client.create(id, secret, region)
  end

  defp get_value(map, keys, default \\ :fail)
  defp get_value(val, [], _), do: {:ok, val}
  defp get_value(vars, [h | t], default) do
    case Map.fetch(vars, h) do
      {:ok, next} -> get_value(next, t)
      :error ->
        case default do
          :fail -> {:error, "#{h} is missing from vars"}
          other -> {:ok, other}
        end
    end
  end

  defp from_vars(vars) do
    with {:ok, port} <- get_value(vars, ["gw_port", "value"]),
         {:ok, sec_group} <- get_value(vars, ["sec_group_id", "value"]),
         {:ok, subnets} <- get_value(vars, ["subnet_ids", "value"]),
         {:ok, cluster} <- get_value(vars, ["cluster_arn", "value"]),
         {:ok, container_name} <- get_value(vars, ["main_container_name", "value"]),
         {:ok, task_arn} <- get_value(vars, ["task_arn", "value"], nil),
         {:ok, task_def} <- get_value(vars, ["td_arn", "value"]) do
      {:ok, %__MODULE__{
        port: port,
        sec_group: sec_group,
        subnets: subnets,
        task_def: task_def,
        cluster: cluster,
        container_name: container_name,
        task_arn: task_arn,
      }}
    end
  end

  defp from_env(env) do
    map =
      env
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/.+=.+/, &1))
      |> Enum.map(fn elem ->
        [name | [value | []]] = Regex.split(~r/=/, elem, [trim: true, parts: 2])
        %{name: name, value: value}
      end)
    {:ok, map}
  end

  def client(dir) do
    varspath = Space.vars_path(dir)
    envpath = Space.env_path(dir)
    with {:ok, json} <- File.read(varspath),
         {:ok, vars} <- Jason.decode(json),
         {:ok, data} <- from_vars(vars),
         {:ok, raw} <- File.read(envpath),
         {:ok, env} <- from_env(raw) do
      {:ok, %__MODULE__{data | env: env, vars: vars, dir: dir}}
    end
  end

  defp find_detail([], name, :fail), do: {:error, "could not find #{name} within task detail attachments"}
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
      {:ok, %{
        private_ip: pip,
        private_dns: pdns,
        id: iface,
      }}
    end
  end

  defp take_task_info(data) do
    with {:ok, iface} <- take_net_iface(data) do
      {:ok, %{
        desired_status: Map.get(data, "desiredStatus"),
        task_arn: Map.get(data, "taskArn"),
        last_status: Map.get(data, "lastStatus"),
        net_iface: iface,
      }}
    end
  end

  defp parse_error(%{"Response" => %{"Errors" => %{"Error" => %{"Message" => message}}}}), do: {:error, message}
  defp parse_error({:unexpected_response, %{body: json}}) do
    with {:ok, body} <- Jason.decode(json) do
      {:error, Map.get(body, "message")}
    else
      _ -> {:error, "something was wrong with the AWS request/response"}
    end
  end
  defp parse_error(error), do: {:error, error}

  defp run_task(d = %__MODULE__{}, id) do
    data = %{
      tags: [%{key: "name", value: id}],
      name: id,
      launchType: "FARGATE",
      taskDefinition: d.task_def,
      cluster: d.cluster,
      networkConfiguration: %{
        awsvpcConfiguration: %{
          assignPublicIp: "ENABLED",
          securityGroups: [d.sec_group],
          subnets: d.subnets,
        }
      },
      overrides: %{
        containerOverrides: [
          %{
            name: d.container_name,
            environment: d.env,
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

  defp store_arn(d = %__MODULE__{}, arn) do
    newvars = Map.put(d.vars, :task_arn, %{
      "sensitive" => false,
      "type" => "string",
      "value" => arn,
    })
    d = %__MODULE__{d | task_arn: arn, vars: newvars}
    with {:ok, json} <- Jason.encode(d.vars),
         :ok <- File.write(Space.vars_path(d.dir), json) do
      {:ok, d}
    end
  end

  defp describe_task(cluster, arn) do
    data = %{
      cluster: cluster,
      tasks: [arn],
    }
    case AWS.ECS.describe_tasks(client(), data) do
      {:ok, %{"failures" => [], "tasks" => [data | []]}, _} -> take_task_info(data)
      {:error, error} -> parse_error(error)
    end
  end

  defp wait_running(_, _, 0, _), do: {:error, "wait running: attempts exhausted"}
  defp wait_running(cluster, arn, attempt, logfun) do
    case describe_task(cluster, arn) do
      {:ok, %{desired_status: "RUNNING", last_status: "RUNNING"}} -> :ok
      {:ok, %{desired_status: "RUNNING", last_status: state}} ->
        logfun.("waiting for running (attempt #{attempt}): state is #{state}, waiting #{@poll_delay/1000}s before retrying")
        Process.sleep(@poll_delay)
        wait_running(cluster, arn, attempt-1, logfun)
      {:ok, %{desired_status: other, last_status: _}} ->
        {:error, "wait running: desired state switched to #{other}"}
      {:error, reason} -> {:error, "wait running: #{reason}"}
    end
  end

  def up(d = %__MODULE__{}, id, logfun) do
    logfun.("issuing run_task command for task #{id}")
    with {:ok, info} <- run_task(d, id),
         arn = info.task_arn,
         logfun.("storing ARN (#{arn}) for task #{id}"),
         {:ok, d} <- store_arn(d, arn),
         logfun.("waiting for task #{id} to become running"),
         :ok <- wait_running(d.cluster, arn, 1000*60*5/@poll_delay, logfun) do
      {:ok, d}
    end
  end

  def stop_task(cluster, arn, reason) do
    data = %{
      cluster: cluster,
      task: arn,
      reason: reason,
    }
    case AWS.ECS.stop_task(client(), data) do
      {:ok, %{"task" => data}, _} -> take_task_info(data)
      {:error, error} -> parse_error(error)
    end
  end

  defp cleanup_stopped(d = %__MODULE__{}) do
    newvars = Map.delete(d.vars, "task_arn")
    with {:ok, json} <- Jason.encode(newvars),
         :ok <- File.write(Space.vars_path(d.dir), json) do
      {:ok, %__MODULE__{d | task_arn: nil, vars: newvars}}
    end
  end

  def down(d = %__MODULE__{task_arn: arn, cluster: cluster}, reason, logfun) do
    logfun.("issuing stop_task command for task #{arn}")
    with {:ok, _} <- stop_task(cluster, arn, reason),
         logfun.("cleaning up task variables"),
         {:ok, d} <- cleanup_stopped(d) do
      {:ok, d}
    end
  end

  defp take_public_ip(eni_id) do
    data = %{
      "NetworkInterfaceId.1" => eni_id,
    }
    case AWS.EC2.describe_network_interfaces(client(), data) do
      {:ok, %{"DescribeNetworkInterfacesResponse" => %{"networkInterfaceSet" => %{"item" => interface}}}, _http} ->
        ip =
          interface
          |> Map.get("association", %{})
          |> Map.get("publicIp")
        {:ok, ip}
      {:error, error} -> parse_error(error)
    end
  end

  def gateway_addr(d = %__MODULE__{}) do
    with {:ok, task} <- describe_task(d.cluster, d.task_arn),
         {:ok, ip} <- take_public_ip(task.net_iface.id) do
      {:ok, "#{ip}:#{d.port}"}
    end
  end

  def logs(_ = %__MODULE__{}, _) do
    # TODO: this one needs cloudwatch but might be very useful for fast
    # debugging.
    {:error, "logs: request not implemented"}
  end

  def info(%__MODULE__{cluster: cluster, task_arn: arn}), do: describe_task(cluster, arn)
end
