defmodule Flex.Space do
  defstruct dir: nil, token: nil, id: nil, ctx: "default"

  @rsa_pub_b64  "rsa.pub.b64"
  @rsa          "rsa"
  @flexi_env    "flexi.env"
  @gateway_port 8080

  def init(parent, clone) do
    {:ok, _files} = File.cp_r(parent, clone)
    cmd = System.find_executable("keygen") # From bin/flexi/admin/
    {_, 0} = System.shell("#{cmd} 2>/dev/null", [cd: clone])

    {:ok, rawkey} =
      [clone, @rsa_pub_b64]
      |> Path.join()
      |> File.read()
    key = String.trim(rawkey)

    envpath = Path.join([clone, @flexi_env])
    {:ok, env} = File.read(envpath)
    newenv = Regex.replace(~r/^PUBKEY=$/, env, "PUBKEY="<>key)
    :ok = File.write(envpath, newenv)

    {:ok, %__MODULE__{dir: clone, id: Path.basename(clone)}}
  end

  def up(s = %__MODULE__{dir: dir, id: id, ctx: ctx}, logfun \\ &IO.puts/1) do
    c = %Composex{ctx: ctx, prj: id, dir: dir}
    :ok = Composex.up(c, logfun)
    {:ok, addr} = Composex.gateway(c, @gateway_port)

    {:ok, rawkey} =
      [dir, @rsa]
      |> Path.join()
      |> File.read()
    key = String.trim(rawkey)

    cmd = System.find_executable("authorise") # From bin/flexi/admin/
    {rawtoken, 0} = System.shell("#{cmd} -a #{addr} -k #{key}", [cd: dir])

    {:ok, %__MODULE__{s | token: String.trim(rawtoken)}}
  end

end
