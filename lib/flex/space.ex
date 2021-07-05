defmodule Flex.Space do
  defstruct driver: %Composex{}, token: nil

  @rsa_pub_b64  "rsa.pub.b64"
  @rsa          "rsa"
  @flexi_env    "flexi.env"
  @gateway_port 8080

  defp find_executable(name) do
    ["bin", name]
    |> Path.join()
    |> Path.absname()
  end

  def clone(ctx, old, new) do
    {:ok, _files} = File.cp_r(old, new)
    cmd = find_executable("keygen") # From bin/flexi/admin/
    {_, 0} = System.shell("#{cmd} 2>/dev/null", [cd: new])

    {:ok, rawkey} =
      [new, @rsa_pub_b64]
      |> Path.join()
      |> File.read()
    key = String.trim(rawkey)

    envpath = Path.join([new, @flexi_env])
    {:ok, env} = File.read(envpath)
    newenv = Regex.replace(~r/PUBKEY=/, env, "PUBKEY="<>key)
    :ok = File.write(envpath, newenv)

    driver = %Composex{dir: new, prj: Path.basename(new), ctx: ctx}
    {:ok, %__MODULE__{driver: driver}}
  end

  def up(s = %__MODULE__{driver: d}, logfun \\ &IO.puts/1) do
    :ok = Composex.up(d, logfun)
    {:ok, addr} = Composex.gateway(d, @gateway_port)

    keypath = Path.join([d.dir, @rsa])
    cmd = find_executable("authorise") # From bin/flexi/admin/
    {rawtoken, 0} = System.shell("#{cmd} -a #{addr} -k #{keypath} 2>/dev/null")

    {:ok, %__MODULE__{s | token: String.trim(rawtoken)}}
  end

  def down(%__MODULE__{driver: d}, logfun \\ &IO.puts/1), do: Composex.down(d, logfun)
  def logs(%__MODULE__{driver: d}, dev \\ :stdio), do: Composex.logs(d, dev)
  def ps(%__MODULE__{driver: d}), do: Composex.ps(d)

end
