defmodule Space do
  @moduledoc """
  Provides a wrapper around the Compose driver. Under the hood explots `docker
  compose` with multiple context support to bring containers/tasks up.
  """
  @moduledoc since: "0.1.0"

  defstruct driver: %Compose{}

  @rsa_pub_b64 "rsa.pub.b64"
  @rsa "rsa"
  @flexi_env "flexi.env"
  @gateway_port 8080
  @health_retries 5

  defp find_executable(name) do
    :flex
    |> :code.priv_dir()
    |> Path.join(name)
    |> Path.absname()
  end

  def clone!(ctx, old, new) do
    {:ok, _files} = File.cp_r(old, new)
    # From bin/flexi/admin/
    cmd = find_executable("keygen")
    {_, 0} = System.shell("#{cmd} 2>/dev/null", cd: new)

    {:ok, rawkey} =
      [new, @rsa_pub_b64]
      |> Path.join()
      |> File.read()

    key = String.trim(rawkey)

    envpath = Path.join([new, @flexi_env])
    {:ok, env} = File.read(envpath)
    newenv = Regex.replace(~r/PUBKEY=/, env, "PUBKEY=" <> key)
    :ok = File.write(envpath, newenv)

    driver = %Compose{dir: new, prj: Path.basename(new), ctx: ctx}
    {:ok, %__MODULE__{driver: driver}}
  end

  defp authorise(%__MODULE__{driver: d}, addr) do
    keypath = Path.join([d.dir, @rsa])
    cmd = find_executable("authorise")
    {rawtoken, code} = System.shell("#{cmd} -a #{addr} -k #{keypath} 2>/dev/null")

    case code do
      0 -> {:ok, String.trim(rawtoken)}
      code -> {:error, "authorise exited with code #{code}"}
    end
  end

  def recover(ctx, dir) do
    driver = %Compose{ctx: ctx, prj: Path.basename(dir), dir: dir}

    with {:ok, addr} <- Compose.gateway(driver, @gateway_port) do
      authorise(%__MODULE__{driver: driver}, addr)
    end
  end

  def up(s = %__MODULE__{driver: d}, logfun \\ &IO.puts/1) do
    with :ok <- Compose.up(d, logfun),
         {:ok, addr} <- Compose.gateway(d, @gateway_port),
         {:ok, token} <- authorise(s, addr),
         client <- Flex.client!(token),
         :ok <- Flex.waithealthy(client, @health_retries, logfun) do
      {:ok, client}
    else
      {:error, :health, :timeout} ->
        logfun.("rolling back after healthcheck timeout")
        :ok = Compose.down(d, logfun)
        {:error, "healthcheck timeout"}
    end
  end

  def addr(%__MODULE__{driver: d}, port \\ @gateway_port), do: Compose.gateway(d, port)

  def down(%__MODULE__{driver: d}, logfun \\ &IO.puts/1), do: Compose.down(d, logfun)
  def logs(%__MODULE__{driver: d}, dev \\ :stdio), do: Compose.logs(d, dev)
  def ps(%__MODULE__{driver: d}), do: Compose.ps(d)
end
