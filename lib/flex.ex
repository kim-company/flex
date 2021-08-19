defmodule Flex do
  @moduledoc """
  Flex is an HTTP client that speaks with a flexi gateway. A client instance
  can be obtained from a gateway token. It is usually computed using
  Flexi's admin/authorise tool, or through the Space module.

  Use Space to bring up/down a Flexi space (i.e. Task or Container).
  """

  # Flexi gateway API version
  @version "3"
  @health_retries 8
  @health_wait 2000

  defstruct client: nil, space: nil

  defp tokenbody!(token) do
    token
    |> String.split(".")
    |> Enum.at(1)
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end

  def token_version!(token) do
    token
    |> tokenbody!()
    |> Map.get("version")
  end

  def token_addr!(token) do
    token
    |> tokenbody!()
    |> Map.get("addr")
  end

  defp waithealthy(_, 0, _), do: {:error, "healthcheck failed"}

  defp waithealthy(client, tries, logfun) do
    logfun.("healthcheck ##{tries} on /_health")

    # TODO: timeout might be more strict here.
    case Tesla.get(client, "_health") do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        logfun.("healthcheck ##{tries} failed: retring in #{@health_wait / 1000}s")
        Process.sleep(@health_wait)
        waithealthy(client, tries - 1, logfun)
    end
  end

  def client(token) do
    # TODO: do it safely
    have = token_version!(token)
    baseurl = "http://#{token_addr!(token)}"

    middleware = [
      # TODO: https
      {Tesla.Middleware.BaseUrl, baseurl},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]},
      Tesla.Middleware.JSON
    ]

    if have != @version do
      {:error, "incompatible flexi version: want #{@version}, have #{have}"}
    else
      adapter = {Tesla.Adapter.Hackney, [timeout: 1000 * 5]}
      {:ok, Tesla.client(middleware, adapter)}
    end
  end

  defp rollback(dir, logfun) do
    with {:ok, space} <- Space.recover_data(dir),
         :ok <- Space.down(space, "rollback after creation failure", logfun),
         {:ok, _files} <- File.rm_rf(dir) do
      :ok
    end
  end

  def new(id, old, new, logfun \\ &IO.puts/1) do
    tic = Time.utc_now()

    with {:ok, space} <- Space.clone(old, new),
         {:ok, space} <- Space.up(space, id, logfun),
         {:ok, client} <- client(space.token),
         :ok = waithealthy(client, @health_retries, logfun) do
      diff = Time.diff(Time.utc_now(), tic, :second)
      logfun.("flex dir=#{new} addr=#{token_addr!(space.token)} created in #{diff}s")
      {:ok, %__MODULE__{client: client, space: space}}
    else
      {:error, reason} ->
        logfun.("Rolling back after creation failure: #{reason}")
        rollback(new, logfun)
        {:error, reason}
    end
  end

  def recover(dir, logfun \\ &IO.puts/1) do
    with {:ok, space} <- Space.recover(dir),
         {:ok, client} <- client(space.token),
         :ok = waithealthy(client, @health_retries / 2, logfun) do
      {:ok, %__MODULE__{client: client, space: space}}
    else
      {:error, reason} ->
        logfun.("rolling back after recover failure: #{reason}")
        rollback(dir, logfun)
        {:error, reason}
    end
  end

  def recover_all(paths, logfun \\ &IO.puts/1) do
    {ok, broken} =
      paths
      |> Stream.map(fn path ->
        case recover(path, logfun) do
          {:ok, l} -> {:ok, l}
          {:error, reason} -> {:error, reason, path}
        end
      end)
      |> Enum.split_with(fn elem ->
        case elem do
          {:ok, _} -> true
          {:error, _, _} -> false
        end
      end)

    ok = Enum.map(ok, fn {:ok, l} -> l end)

    broken =
      Enum.map(broken, fn {:error, reason, path} ->
        logfun.("warning: found broken livesub folder at #{path}: #{reason}")
        {reason, path}
      end)

    {ok, broken}
  end

  def destroy(%__MODULE__{space: space}, logfun \\ &IO.puts/1) do
    tic = Time.utc_now()

    with :ok <- Space.down(space, "destroy action requested", logfun),
         {:ok, _files} <- File.rm_rf(space.dir) do
      diff = Time.diff(Time.utc_now(), tic, :second)
      logfun.("flex dir=#{space.dir} addr=#{token_addr!(space.token)} destroyed in #{diff}s")
      :ok
    end
  end

  defp httperror(status, %{"error" => error}), do: "status #{status}: #{error}"
  defp httperror(status, _), do: "status #{status}"

  def read(%__MODULE__{client: client}, file) do
    case Tesla.get(client, file) do
      {:error, reason} -> {:error, %{message: reason}}
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, "read: #{httperror(status, body)}"}
    end
  end

  def write(%__MODULE__{client: client}, file, body) do
    case Tesla.put(client, file, body) do
      {:error, reason} -> {:error, %{message: reason}}
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "write: #{httperror(status, body)}"}
    end
  end

  defp startstop(flex, action) do
    case read(flex, action) do
      {:ok, _body} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def start(flex = %__MODULE__{}), do: startstop(flex, "start")
  def stop(flex = %__MODULE__{}), do: startstop(flex, "stop")
  def help(flex = %__MODULE__{}), do: read(flex, "help")

  def is_running?(flex = %Flex{}) do
    case help(flex) do
      {:ok, h} ->
        tool =
          h
          |> Map.get("data", %{})
          |> Map.get("tool", %{})

        pid = Map.get(tool, "pid", nil)
        ec = Map.get(tool, "exit_code", nil)
        pid != nil && ec == nil

      _other ->
        false
    end
  end

  def public_ip(%__MODULE__{space: space}), do: Space.public_ip(space)
end
