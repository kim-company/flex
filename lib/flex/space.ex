defmodule Flex.Space do
  defstruct dir: nil, token: nil, id: nil, ctx: "default"

  @rsa_pub_b64  "rsa.pub.b64"
  @rsa          "rsa"
  @flexi_env    "flexi.env"
  @gateway_port 8080

  defp find_executable(name) do
    ["bin", name]
    |> Path.join()
    |> Path.absname()
  end

  def clone(old, new) do
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

    {:ok, %__MODULE__{dir: new, id: Path.basename(new)}}
  end

  def up(s = %__MODULE__{dir: dir, id: id, ctx: ctx}, logfun \\ &IO.puts/1) do
    c = %Composex{ctx: ctx, prj: id, dir: dir}
    :ok = Composex.up(c, logfun)
    {:ok, addr} = Composex.gateway(c, @gateway_port)

    keypath = Path.join([dir, @rsa])
    cmd = find_executable("authorise") # From bin/flexi/admin/
    {rawtoken, 0} = System.shell("#{cmd} -a #{addr} -k #{keypath} 2>/dev/null")

    {:ok, %__MODULE__{s | token: String.trim(rawtoken)}}
  end

  def down(%__MODULE__{dir: dir, id: id, ctx: ctx}, logfun \\ &IO.puts/1) do
    Composex.down(%Composex{ctx: ctx, prj: id, dir: dir}, logfun)
  end

  def logs(%__MODULE__{dir: dir, id: id, ctx: ctx}, dev \\ :stdio) do
    Composex.logs(%Composex{dir: dir, prj: id, ctx: ctx}, dev)
  end

  def ps(%__MODULE__{dir: dir, id: id, ctx: ctx}) do
    Composex.ps(%Composex{dir: dir, prj: id, ctx: ctx})
  end

end
