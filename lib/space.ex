defmodule Space do
  @moduledoc """
  Creates, authorises and destroyes spaces.
  """

  defstruct [:dir, :driver, :data, :token]

  @driver Driver.AWS

  @rsa_pub_b64 "rsa.pub.b64"
  @rsa "rsa"
  @flexi_env "env"
  @flexi_vars "vars.json"

  def env_path(dir), do: Path.join([dir, @flexi_env])
  def vars_path(dir), do: Path.join([dir, @flexi_vars])

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

  def clone(old, new) do
    with {:ok, _files} = File.cp_r(old, new),
         cmd = find_executable("keygen"),
         # Does not have any reason not to work. If it does not, crash - no
         # problem.
         {_, 0} = System.shell("#{cmd} 2>/dev/null", cd: new),
         {:ok, key} <- readkey(new, @rsa_pub_b64),
         envpath = env_path(new),
         {:ok, env} <- File.read(envpath),
         newenv = Regex.replace(~r/PUBKEY=/, env, "PUBKEY=" <> key),
         :ok <- File.write(envpath, newenv),
         {:ok, client} <- @driver.client(new) do
      {:ok, %__MODULE__{dir: new, driver: @driver, data: client}}
    end
  end

  def authorise(dir, addr) do
    keypath = Path.join([dir, @rsa])
    cmd = find_executable("authorise")
    {rawtoken, code} = System.shell("#{cmd} -a #{addr} -k #{keypath} 2>/dev/null")

    case code do
      0 -> {:ok, String.trim(rawtoken)}
      code -> {:error, "authorise exited with code #{code}"}
    end
  end

  def recover_data(dir) do
    with {:ok, client} <- @driver.client(dir) do
      {:ok, %__MODULE__{dir: dir, driver: @driver, data: client}}
    end
  end

  def recover(dir) do
    with {:ok, client} <- @driver.client(dir),
         envpath = env_path(dir),
         {:ok, env} = File.read(envpath),
         [raw | _ ] = Regex.run(~r/TOKEN=.*/, env, [captures: :first]),
         token = String.trim_leading(raw, "TOKEN=") do
      if token == nil do
        {:error, "could not extract TOKEN from env"}
      else
        {:ok, %__MODULE__{dir: dir, driver: @driver, data: client, token: token}}
      end
    end
  end

  def up(s = %__MODULE__{driver: driver}, id, logfun \\ &IO.puts/1) do
    with {:ok, newdata} <- driver.up(s.data, id, logfun),
         s = %{s | data: newdata},
         {:ok, addr} <- driver.gateway_addr(s.data),
         {:ok, token} <- authorise(s.dir, addr),
         envpath = env_path(s.dir),
         {:ok, env} <- File.read(envpath),
         newenv = env <> "\nTOKEN="<>token<>"\n",
         :ok <- File.write(envpath, newenv) do
      {:ok, %__MODULE__{s | token: token}}
    end
  end

  def down(s = %__MODULE__{}, reason, logfun \\ &IO.puts/1) do
    s.driver.down(s.data, reason, logfun)
  end

  def public_ip(s = %__MODULE__{}), do: s.driver.public_ip(s.data)
end
