defmodule Goth.Config do
  @moduledoc false

  # `Goth.Config` is a `GenServer` that holds the current configuration.
  # This configuration is loaded from one of four places:

  # 1. a JSON string passed in via your application's config
  # 2. a ENV variable passed in via your application's config
  # 3. The Application Default Credentials, as defined by
  #    https://developers.google.com/identity/protocols/application-default-credentials
  # 4. an `init/1` callback on a custom config module. This init function is
  #    passed the current config and must return an `{:ok, config}` tuple

  # The `Goth.Config` server exists mostly for other parts of your application
  # (or other libraries) to pull the current configuration state,
  # via `Goth.Config.get/1`. If necessary, you can also set config values via
  # `Goth.Config.set/2`

  use GenServer
  require Logger

  # this using macro isn't actually necessary,
  defmacro __using__(_opts) do
    quote do
      @behaviour Goth.Config
    end
  end

  @configuration_file "configurations/config_default"
  @credentials_file "application_default_credentials.json"
  @optional_callbacks init: 1

  @doc """
  A callback executed when the Goth.Config server starts.

  The sole argument is the `:goth` configuration as stored in the
  application environment. It must return `{:ok, keyword}` with the updated
  list of configuration.

  To have your module's `init/1` callback called at startup, add your module
  as the `:config_module` in the application environment:

      config :goth, config_module: MyConfig
  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()}

  def start_link(envs) do
    GenServer.start_link(__MODULE__, envs, name: __MODULE__)
  end

  def init(envs) do
    {:ok, dynamic_config} = config_mod_init(envs)

    dynamic_config
    |> Keyword.pop(:disabled, false)
    |> load_and_init()
  end

  defp ensure_started do
    envs = Application.get_all_env(:goth)

    case Supervisor.start_child(Goth.Supervisor, {__MODULE__, envs}) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, {{e, _}, _}} ->
        raise e
    end
  end

  defp get_configuration_path(nil) do
    case :os.type() do
      {:win32, _} ->
        config_dir = System.get_env("APPDATA") || ""
        Path.join([config_dir, "gcloud"])

      {:unix, _} ->
        home_dir = System.get_env("HOME") || ""
        Path.join([home_dir, ".config/gcloud"])
    end
  end

  defp get_configuration_path(config_root_dir), do: config_root_dir

  defp get_configuration_file(nil), do: @configuration_file

  defp get_configuration_file(configuration_file), do: configuration_file

  defp get_credentials_file(nil), do: @credentials_file

  defp get_credentials_file(credentials_file), do: credentials_file

  # We have been configured as `disabled` so just start with an empty configuration
  defp load_and_init({true, _config}) do
    {:ok, %{}}
  end

  defp load_and_init({false, app_config}) do
    config =
      from_json(app_config) ||
        from_config(app_config) ||
        from_creds_file() ||
        from_creds_env() ||
        from_gcloud_adc(app_config) ||
        from_metadata(app_config)

    config =
      config
      |> map_config()
      |> Enum.map(fn {account, config} ->
        actor_email = Keyword.get(app_config, :actor_email) || Map.get(config, "actor_email")
        project_id = determine_project_id(config, app_config)

        {
          account,
          config
          |> Map.put("project_id", project_id)
          |> Map.put("actor_email", actor_email)
        }
      end)
      |> Enum.into(%{})

    {:ok, config}
  end

  def map_config(config) when is_map(config), do: %{default: config}

  def map_config(config) when is_list(config) do
    config
    |> Enum.map(fn config ->
      {
        config["client_email"],
        config
      }
    end)
    |> Enum.into(%{})
  end

  def add_config(config) when is_map(config) do
    ensure_started()
    config = set_token_source(config)
    GenServer.call(__MODULE__, {:add_config, config["client_email"], config})
  end

  defp config_mod_init(config) do
    case Keyword.get(config, :config_module) do
      nil ->
        {:ok, config}

      mod ->
        if Code.ensure_loaded?(mod) and function_exported?(mod, :init, 1) do
          mod.init(config)
        else
          {:ok, config}
        end
    end
  end

  defp from_json(config) do
    case Keyword.get(config, :json) do
      nil -> nil
      {:system, var} -> decode_json(System.get_env(var))
      json -> decode_json(json)
    end
  end

  defp from_config(config) do
    Keyword.get(config, :config)
  end

  defp from_creds_file do
    case System.get_env("GOOGLE_APPLICATION_CREDENTIALS") do
      nil -> nil
      filename -> filename |> File.read!() |> decode_json()
    end
  end

  defp from_creds_env do
    case System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON") do
      nil -> nil
      data -> decode_json(data)
    end
  end

  # Search the well-known path for application default credentials provided
  # by the gcloud sdk. Note there are different paths for unix and windows.
  defp from_gcloud_adc(config) do
    config_root_dir = Keyword.get(config, :config_root_dir)

    path_root = get_configuration_path(config_root_dir)

    credentials_file =
      Keyword.get(config, :credentials_file)
      |> get_credentials_file()

    credential_data =
      Path.join([path_root, credentials_file])
      |> get_credential_data()

    configuration_file =
      Keyword.get(config, :configuration_file)
      |> get_configuration_file()

    configuration_data =
      Path.join([path_root, configuration_file])
      |> get_configuration_data()

    cond do
      configuration_data && credential_data ->
        Map.merge(credential_data, configuration_data)

      configuration_data ->
        configuration_data

      credential_data ->
        credential_data

      true ->
        nil
    end
  end

  defp get_credential_data(credential_file) do
    if File.regular?(credential_file) do
      credential_file |> File.read!() |> decode_json()
    else
      nil
    end
  end

  def get_configuration_data(configuration_file) do
    with true <- File.regular?(configuration_file),
         configuration_data <- configuration_file |> File.read!() |> decode_ini(),
         project_id when not is_nil(project_id) <- configuration_data["core"]["project"],
         actor_email when not is_nil(actor_email) <- configuration_data["core"]["account"] do
      %{"project_id" => project_id, "actor_email" => actor_email}
    else
      _ ->
        nil
    end
  end

  defp from_metadata(_config) do
    %{"token_source" => :metadata}
  end

  defp determine_project_id(config, dynamic_config) do
    case Keyword.get(dynamic_config, :project_id) || System.get_env("GOOGLE_CLOUD_PROJECT") ||
           System.get_env("GCLOUD_PROJECT") || System.get_env("DEVSHELL_PROJECT_ID") ||
           config["project_id"] || config["quota_project_id"] do
      nil ->
        project_id_from_metadata()

      project_id ->
        project_id
    end
  end

  defp project_id_from_metadata do
    Goth.Client.retrieve_metadata_project()
  rescue
    e ->
      if Map.get(e, :reason) == :nxdomain do
        Logger.error("""
        Failed to retrieve project data from GCE internal metadata service.
        Either you haven't configured your GCP credentials, you aren't running on GCE, or both.
        Please see README.md for instructions on configuring your credentials.\
        """)
      else
        Logger.error(Exception.message(e))
      end

      reraise e, __STACKTRACE__
  end

  # Decodes JSON (if configured) and sets oauth token source
  defp decode_json(json) do
    json
    |> Jason.decode!()
    |> set_token_source
  end

  defp decode_ini(contents) do
    String.split(contents, "\n", trim: true)
    |> Enum.reduce(%{current_header: ""}, fn line, accumulator ->
      if String.match?(line, ~r/^\[.+\]$/) do
        [_original, header] = Regex.run(~r/^\[(.+)\]$/, line)
        %{accumulator | current_header: header}
      else
        [key, value] = String.split(line, " = ", trim: true)
        Map.update(accumulator, accumulator[:current_header], %{key => value}, &Map.put(&1, key, value))
      end
    end)
    |> Map.delete(:current_header)
  end

  defp set_token_source(%{"private_key" => _} = map) do
    Map.put(map, "token_source", :oauth_jwt)
  end

  defp set_token_source(%{"refresh_token" => _, "client_id" => _, "client_secret" => _} = map) do
    Map.put(map, "token_source", :oauth_refresh)
  end

  defp set_token_source(%{"type" => "external_account"} = map) do
    Map.put(map, "token_source", :workload_identity)
  end

  defp set_token_source(list) when is_list(list) do
    Enum.map(list, fn config ->
      set_token_source(config)
    end)
  end

  @doc """
  Set a value in the config.
  """
  @spec set(String.t() | atom, any()) :: :ok
  def set(key, value) when is_atom(key), do: key |> to_string |> set(value)

  def set(key, value), do: set(:default, key, value)

  def set(account, key, value) do
    ensure_started()
    GenServer.call(__MODULE__, {:set, account, key, value})
  end

  @doc """
  Retrieve a value from the config.
  """
  @spec get(String.t() | atom()) :: {:ok, any()} | :error
  def get(key) when is_atom(key), do: key |> to_string() |> get()
  def get(key), do: get(:default, key)

  @spec get(String.t() | atom(), String.t() | atom()) :: {:ok, any()} | :error
  def get(account, key) when is_atom(key) do
    get(account, key |> to_string())
  end

  def get(account, key) do
    ensure_started()
    GenServer.call(__MODULE__, {:get, account, key})
  end

  def handle_call({:set, account, key, value}, _from, keys) do
    {:reply, :ok, put_in(keys, [account, key], value)}
  end

  def handle_call({:add_config, account, config}, _from, keys) do
    {:reply, :ok, Map.put(keys, account, config)}
  end

  def handle_call({:get, account, key}, _from, keys) do
    case Map.fetch(keys, account) do
      {:ok, config} -> {:reply, Map.fetch(config, key), keys}
      :error -> {:reply, :error, keys}
    end
  end
end
