defmodule Compose do
  @moduledoc """
  Provides a `docker compose` client. Usually it is used through the Space
  module.
  """
  defstruct ctx: "default", prj: "", dir: "."

  defp discard(_), do: :nop

  defp dockercmd(), do: System.find_executable("docker")
  defp baseargs(%__MODULE__{ctx: ctx, prj: prj}), do: ["-c", ctx, "compose", "-p", prj]

  defp switchargs(c = %__MODULE__{ctx: "default"}, "up"),
    do: baseargs(c) ++ ["up", "-d", "--no-color"]

  defp switchargs(c, "up"), do: baseargs(c) ++ ["up", "--no-color"]
  defp switchargs(c, "down"), do: baseargs(c) ++ ["down", "--no-color"]

  defp flush_loop(logfun) do
    # Crashes when unexpected messages are received.
    receive do
      {_port, {:data, data}} ->
        data
        |> List.to_string()
        |> String.split("\n")
        |> Enum.map(&String.trim(&1))
        |> Enum.each(fn s ->
          if String.length(s) > 0 do
            logfun.(s)
          end
        end)

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

  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle.html
  defp waitrunning(c, logfun) do
    case ps(c) do
      {:ok, [%{"State" => state} | _]} ->
        logfun.("task state is #{state}")

        case state do
          "Provisioning" ->
            Process.sleep(3000)
            waitrunning(c, logfun)

          "Pending" ->
            Process.sleep(2000)
            waitrunning(c, logfun)

          "Activating" ->
            Process.sleep(1000)
            waitrunning(c, logfun)

          "Running" ->
            :ok

          other ->
            {:error, "task state skipped Running, now is #{other}"}
        end

      {:ok, []} ->
        {:error, "no data available"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def up(c, logfun \\ &discard/1)

  def up(c = %__MODULE__{ctx: "default"}, logfun) do
    switch(c, "up", logfun)
  end

  def up(c = %__MODULE__{}, logfun) do
    with :ok <- switch(c, "up", logfun),
         logfun.("waiting for state to become RUNNING"),
         :ok <- waitrunning(c, logfun) do
      :ok
    end
  end

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
