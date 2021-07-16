defmodule Compose do
  @moduledoc """
  Provides a `docker compose` client. Usually it is used through the Space
  module.
  """
  defstruct ctx: "default", prj: "", dir: "."

  defp discard(_), do: :nop

  defp dockercmd(), do: System.find_executable("docker")
  defp baseargs(%__MODULE__{ctx: ctx, prj: prj}), do: ["-c", ctx, "compose", "-p", prj]

  defp switchargs(c = %__MODULE__{ctx: "default"}, "up"), do: baseargs(c) ++ ["up", "-d"]
  defp switchargs(c, "up"), do: baseargs(c) ++ ["up"]
  defp switchargs(c, "down"), do: baseargs(c) ++ ["down"]

  defp flush_loop(logfun) do
    # Crashes when unexpected messages are received.
    receive do
      {_port, {:data, data}} ->
        data
        |> List.to_string()
        |> String.trim()
        |> logfun.()

        flush_loop(logfun)
    end
  end

  defp switch(c = %__MODULE__{dir: dir}, onoff, logfun) do
    pid = spawn(fn -> flush_loop(logfun) end)
    opts = [:stderr_to_stdout, cd: dir, args: switchargs(c, onoff)]

    port = Port.open({:spawn_executable, dockercmd()}, opts)
    Port.connect(port, pid)
    ref = Port.monitor(port)

    receive do
      {:DOWN, ^ref, :port, _, :normal} -> :ok
      {:DOWN, ^ref, :port, _, reason} -> {:error, reason}
    end
  end

  def up(c = %__MODULE__{}, logfun \\ &discard/1), do: switch(c, "up", logfun)
  def down(c = %__MODULE__{}, logfun \\ &discard/1), do: switch(c, "down", logfun)

  def logs(c = %__MODULE__{dir: dir}, dev \\ :stdio) do
    opts = [stderr_to_stdout: true, into: IO.stream(dev, :line), cd: dir]

    case System.cmd(dockercmd(), baseargs(c) ++ ["logs"], opts) do
      {%IO.Stream{}, 0} -> :ok
      {_stream, status} -> {:error, "logs: exited with status #{status}"}
    end
  end

  def ps(c = %__MODULE__{dir: dir}) do
    {:ok, buf} = StringIO.open("")
    opts = [stderr_to_stdout: true, into: IO.stream(buf, :line), cd: dir]
    args = baseargs(c) ++ ["ps", "--format", "json"]

    case System.cmd(dockercmd(), args, opts) do
      {%IO.Stream{}, 0} -> Jason.decode(StringIO.flush(buf))
      {_stream, status} -> {:error, "ps: exited with status #{status}"}
    end
  end

  def gateway(c, portref \\ 8080) do
    case ps(c) do
      {:ok, [%{"Publishers" => pubs} | _]} ->
        case Enum.find(pubs, :not_found, fn x -> x["TargetPort"] == portref end) do
          :not_found -> {:error, "missing publisher with target port #{portref}"}
          %{"URL" => url} -> {:ok, url}
          _ -> {:error, "missing URL field in gateway publisher"}
        end

      {:ok, []} ->
        {:error, "no data available"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
