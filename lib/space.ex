defmodule Space do
  @moduledoc """
  Provides a wrapper around the Compose driver. Under the hood explots `docker
  compose` with multiple context support to bring containers/tasks up.
  """
  @moduledoc since: "0.1.0"

  defstruct driver: %Compose{}, token: nil

  @rsa_pub_b64 "rsa.pub.b64"
  @rsa "rsa"
  @flexi_env "flexi.env"
  @gateway_port 8080

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

  defp authorise(s = %__MODULE__{driver: d}, addr) do
    keypath = Path.join([d.dir, @rsa])
    cmd = find_executable("authorise")
    {rawtoken, code} = System.shell("#{cmd} -a #{addr} -k #{keypath} 2>/dev/null")

    case code do
      0 -> {:ok, %__MODULE__{s | token: String.trim(rawtoken)}}
      code -> {:error, "authorise exited with code #{code}"}
    end
  end

  defp tokenbody(token) do
    token
    |> String.split(".")
    |> Enum.at(1)
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end

  def token_version(token) do
    token
    |> tokenbody()
    |> Map.get("version")
  end

  def token_addr(token) do
    token
    |> tokenbody()
    |> Map.get("addr")
  end

  def addr(s = %__MODULE__{}, port \\ @gateway_port), do: Compose.gateway(s, port)

  def recover(ctx, dir) do
    driver = %Compose{ctx: ctx, prj: Path.basename(dir), dir: dir}

    with {:ok, addr} <- Compose.gateway(driver, @gateway_port) do
      authorise(%__MODULE__{driver: driver}, addr)
    end
  end

  def up(s = %__MODULE__{driver: d}, logfun \\ &IO.puts/1) do
    with :ok <- Compose.up(d, logfun),
         {:ok, addr} <- Compose.gateway(d, @gateway_port) do
      authorise(s, addr)
    end
  end

  def down(%__MODULE__{driver: d}, logfun \\ &IO.puts/1), do: Compose.down(d, logfun)
  def logs(%__MODULE__{driver: d}, dev \\ :stdio), do: Compose.logs(d, dev)
  def ps(%__MODULE__{driver: d}), do: Compose.ps(d)

  def client(%__MODULE__{token: token}), do: Flex.client!(token)
end
