defmodule Space do
  @moduledoc """
  Provides a wrapper around the Compose driver. Under the hood explots `docker
  compose` with multiple context support to bring containers/tasks up.
  """

  defstruct driver: %Compose{}

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

  defp readkey(dir, file) do
    path = Path.join([dir, file])

    with {:ok, rawkey} <- File.read(path) do
      {:ok, String.trim(rawkey)}
    end
  end

  def clone(ctx, old, new) do
    with {:ok, _files} = File.cp_r(old, new),
         cmd = find_executable("keygen"),
         # Does not have any reason not to work. If it does not, crash - no
         # problem.
         {_, 0} = System.shell("#{cmd} 2>/dev/null", cd: new),
         {:ok, key} <- readkey(new, @rsa_pub_b64),
         envpath = Path.join([new, @flexi_env]),
         {:ok, env} <- File.read(envpath),
         newenv = Regex.replace(~r/PUBKEY=/, env, "PUBKEY=" <> key),
         :ok <- File.write(envpath, newenv) do
      driver = %Compose{dir: new, prj: Path.basename(new), ctx: ctx}
      {:ok, %__MODULE__{driver: driver}}
    end
  end

  def authorise(%__MODULE__{driver: d}, addr) do
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
    {:ok, %__MODULE__{driver: driver}}
  end

  def up(s = %__MODULE__{driver: d}, logfun \\ &IO.puts/1) do
    with :ok <- Compose.up(d, logfun),
         {:ok, addr} <- Compose.gateway(d, @gateway_port),
         {:ok, token} <- authorise(s, addr) do
      {:ok, token}
    end
  end

  def addr(%__MODULE__{driver: d}, port \\ @gateway_port), do: Compose.gateway(d, port)
  def down(%__MODULE__{driver: d}, logfun \\ &IO.puts/1), do: Compose.down(d, logfun)
  def logs(%__MODULE__{driver: d}, dev \\ :stdio), do: Compose.logs(d, dev)
  def ps(%__MODULE__{driver: d}), do: Compose.ps(d)
end
