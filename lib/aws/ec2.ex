defmodule AWS.EC2 do
  @moduledoc """
  https://github.com/aws-beam/aws-elixir does not include an EC2 client as of
  Wed Sep 22 14:36:47 CEST 2021. If this functionality is inlcuded, remove this
  module.
  """

  def describe_network_interfaces(client, input, options \\ []) do
    request(client, "DescribeNetworkInterfaces", input, options)
  end

  @spec request(AWS.Client.t(), binary(), map(), list()) ::
          {:ok, Poison.Parser.t() | nil, Poison.Response.t()}
          | {:error, Poison.Parser.t()}
          | {:error, HTTPoison.Error.t()}
  defp request(client, action, input, options) do
    client = %{client | service: "ec2"}
    host = build_host("ec2", client)
    url = build_url(host, client)

    headers = [
      {"Host", host},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    input = Map.merge(input, %{"Action" => action, "Version" => "2016-11-15"})
    payload = AWS.Util.encode_query(input)
    headers = AWS.Signature.sign_v4(client, now(), "POST", url, headers, payload)

    case HTTPoison.post(url, payload, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""} = response} ->
        {:ok, nil, response}

      {:ok, %HTTPoison.Response{status_code: 200, body: body} = response} ->
        {:ok, AWS.XML.decode!(body), response}

      {:ok, %HTTPoison.Response{body: body}} ->
        error = AWS.XML.decode!(body)
        {:error, error}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, %HTTPoison.Error{reason: reason}}
    end
  end

  defp build_host(_endpoint_prefix, %{region: "local"}) do
    "localhost"
  end

  defp build_host(endpoint_prefix, %{region: region, endpoint: endpoint}) do
    "#{endpoint_prefix}.#{region}.#{endpoint}"
  end

  defp build_url(host, %{:proto => proto, :port => port}) do
    "#{proto}://#{host}:#{port}/"
  end

  defp now do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
