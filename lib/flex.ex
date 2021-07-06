defmodule Flex do
  @moduledoc """
  Flex is an HTTP client that speaks with a flexi gateway. A client instance
  can be obtained from a gateway token. It is usually computed using
  Flexi's admin/authorise tool, or through the Flex.Space module.

  Use Flex.Space to bring up/down a Flexi space (i.e. Task or Container).
  """
  @moduledoc since: "0.1.0"

  # Flexi gateway API version
  @version "3"

  defp httperror(status, %{"error" => error}), do: "status #{status}: #{error}"
  defp httperror(status, _), do: "status #{status}"

  def read(client, file) do
    case Tesla.get(client, file) do
      {:error, reason} -> {:error, %{message: reason}}
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, "read: #{httperror(status, body)}"}
    end
  end

  def write(client, file, body) do
    case Tesla.put(client, file, body) do
      {:error, reason} -> {:error, %{message: reason}}
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "write: #{httperror(status, body)}"}
    end
  end

  defp startstop(client, action) do
    case read(client, action) do
      {:ok, _body} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def start(client), do: startstop(client, "start")
  def stop(client), do: startstop(client, "stop")
  def help(client), do: read(client, "help")

  defp tokenbody(token) do
    token
    |> String.split(".")
    |> Enum.at(1)
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end

  defp version(token) do
    token
    |> tokenbody()
    |> Map.get("version")
  end

  defp addr(token) do
    token
    |> tokenbody()
    |> Map.get("addr")
  end

  def client!(token) do
    have = version(token)

    if have != @version do
      raise "incompatible flexi version: want #{@version}, have #{have}"
    end

    middleware = [
      # TODO: https
      {Tesla.Middleware.BaseUrl, "http://#{addr(token)}"},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]},
      Tesla.Middleware.JSON
    ]

    adapter = {Tesla.Adapter.Mint, []}
    Tesla.client(middleware, adapter)
  end
end
