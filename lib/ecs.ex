defmodule ECS do
  @flexi_vars "vars.json"

  defstruct [:port, :sec_group, :td, :subnets]

  defp get_value(val, []), do: {:ok, val}
  defp get_value(vars, [h | t]) do
    case Map.fetch(vars, h) do
      {:ok, next} -> get_value(next, t)
      :error -> {:error, "#{h} is missing from #{@flexi_vars}"}
    end
  end

  defp from_vars(vars) do
    with {:ok, port} <- get_value(vars, ["gw_port", "value"]),
         {:ok, sec_group} <- get_value(vars, ["sec_group_id", "value"]),
         {:ok, subnets} <- get_value(vars, ["subnet_ids", "value"]),
         {:ok, td} <- get_value(vars, ["td_arn", "value"]) do
      {:ok, %__MODULE__{port: port, sec_group: sec_group, subnets: subnets, td: td}}
    end
  end

  def client(dir) do
    varspath = Path.join([dir, @flexi_vars])
    with {:ok, json} <- File.read(varspath),
         {:ok, vars} <- Jason.decode(json),
         {:ok, data} <- from_vars(vars) do
      {:ok, data}
    end
  end

  def up(_ = %__MODULE__{}, _) do
    {:error, "not implemented"}
  end

  def down(_ = %__MODULE__{}, _) do
    {:error, "not implemented"}
  end

  def gateway_addr(_ = %__MODULE__{}) do
    {:error, "not implemented"}
  end

  def logs(_ = %__MODULE__{}, _) do
    {:error, "not implemented"}
  end

  def info(_ = %__MODULE__{}) do
    {:error, "not implemented"}
  end

end
