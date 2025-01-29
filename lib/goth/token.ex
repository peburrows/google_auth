defmodule Goth.Token do
  @moduledoc """
  Functions for retrieving the token from the Google API.
  """

  @type t :: %__MODULE__{
          token: String.t(),
          type: String.t(),
          scope: String.t(),
          expires: non_neg_integer,
          sub: String.t() | nil
        }

  defstruct [
    :token,
    :type,
    :scope,
    :sub,
    :expires,

    # Deprecated fields:
    :account
  ]

  @default_url "https://www.googleapis.com/oauth2/v4/token"
  @default_scopes ["https://www.googleapis.com/auth/cloud-platform"]

  @doc """
  Fetch the token from the Google API using the given `config`.

  Config may contain the following keys:

    * `:source` - the source to retrieve the token from.

      Supported values include:

        * `{:service_account, credentials}` - for fetching token using service account credentials

        * `{:refresh_token, credentials}` - for fetching token using refresh token

        * `{:workload_identity, credentials}` - for fetching token using workload identity

        * `:metadata` - for fetching token using Google internal metadata service

      If `:source` is not set, Goth will:

        * Check application environment. You can set it with: `config :goth, json: File.read!("credentials.json")`.

        * Check `GOOGLE_APPLICATION_CREDENTIALS` env variable that contains path to credentials file.

        * Check `GOOGLE_APPLICATION_CREDENTIALS_JSON` env variable that contains credentials JSON.

        * Check `~/.config/gcloud/application_default_credentials.json` file.

        * Check Google internal metadata service

        * Otherwise, raise an error.

      See "Source" section below for more information.

    * `:http_client` - a function that makes the HTTP request.

      Can be one of the following:

        * `fun` - same as `{fun, []}`

        * `{fun, opts}` - `fun` must be a 1-arity function that receives a keyword list with fields
          `:method`, `:url`, `:headers`, and `:body` along with any passed `opts`. The function must return
          `{:ok, %{status: status, headers: headers, body: body}}` or `{:error, exception}`.

          See "Custom HTTP Client" section below for more information.

      `fun` can also be an atom `:finch` to use the built-in [Finch](http://github.com/sneako/finch)-based
      client.

      Defaults to `{:finch, []}`.

  ## Source

  Source can be one of:

  #### Service account - `{:service_account, credentials}`

  Same as `{:service_account, credentials, []}`

  #### Service account - `{:service_account, credentials, options}`

  The `credentials` is a map and can contain the following keys:

    * `"private_key"`

    * `"client_email"`

  The `options` is a keywords list and can contain the following keys:

    * `:url` - the URL of the authentication service, defaults to:
      `"https://www.googleapis.com/oauth2/v4/token"`

    * `:scopes` - the list of token scopes, defaults to `#{inspect(@default_scopes)}` (ignored if `:claims` present)

    * `:claims` - self-signed JWT extra claims. Should be a map with string keys only.
      A self-signed JWT will be [exchanged for a Google-signed ID token](https://cloud.google.com/functions/docs/securing/authenticating#exchanging_a_self-signed_jwt_for_a_google-signed_id_token)

  #### Refresh token - `{:refresh_token, credentials}`

  Same as `{:refresh_token, credentials, []}`

  #### Refresh token - `{:refresh_token, credentials, options}`

  The `credentials` is a map and can contain the following keys:

    * `"refresh_token"`

    * `"client_id"`

    * `"client_secret"`

  The `options` is a keywords list and can contain the following keys:

    * `:url` - the URL of the authentication service, defaults to:
      `"https://www.googleapis.com/oauth2/v4/token"`

  #### Workload identity - `{:workload_identity, credentials}`

  The `credentials` is a map and can contain the following keys:

    * `"token_url"`

    * `"audience"`

    * `"subject_token_type"`

    * `"subject_token"`

    * `"credential_source"` - information about how to retrieve the subject token if not provided, can contain the following keys:
      * `"format"` - including a `"type"` of `"json"` or `"text"` and optionally `"subject_token_field_name"` if `"json"`

      * `"file"` - file to read the subject token from

      * `"url"` - url to fetch the subject token from

      * `"headers"` - any headers to pass to the url

  #### Google metadata server - `:metadata`

  Same as `{:metadata, []}`

  #### Google metadata server - `{:metadata, options}`

  The `options` is a keywords list and can contain the following keys:

    * `:account` - the name of the account to generate the token for, defaults to `"default"`

    * `:url` - the URL of the metadata server, defaults to `"http://metadata.google.internal"`

    * `:audience` - the audience you want an identity token for, default to `nil`
      If this parameter is provided, an identity token is returned instead of an access token

  ## Custom HTTP Client

  To use a custom HTTP client, define a function that receives a keyword list with fields
  `:method`, `:url`, `:headers`, and `:body`. The function must return
  `{:ok, %{status: status, headers: headers, body: body}}` or `{:error, exception}`.

  Here's an example with Finch:

      defmodule MyApp do
        def request_with_finch(options) do
          {method, options} = Keyword.pop!(options, :method)
          {url, options} = Keyword.pop!(options, :url)
          {headers, options} = Keyword.pop!(options, :headers)
          {body, options} = Keyword.pop!(options, :body)

          Finch.build(method, url, headers, body)
          |> Finch.request(Goth.Finch, options)
        end
      end

  And here is how it can be used:

      iex> Goth.Token.fetch(source: source, http_client: &MyApp.request_with_finch/1)
      {:ok, %Goth.Token{...}}

      iex> Goth.Token.fetch(source: source, http_client: {&MyApp.request_with_finch/1, receive_timeout: 5000})
      {:ok, %Goth.Token{...}}

  ## Examples

  #### Generate a token using a service account credentials file:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> Goth.Token.fetch(source: {:service_account, credentials})
      {:ok, %Goth.Token{...}}

  You can generate a credentials file containing service account using `gcloud` utility like this:

      $ gcloud iam service-accounts keys create --key-file-type=json --iam-account=... credentials.json

  #### Generate a cloud function invocation token using a service account credentials file:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      ...> claims = %{"target_audience" => "https://<GCP_REGION>-<PROJECT_ID>.cloudfunctions.net/<CLOUD_FUNCTION_NAME>"}
      ...> Goth.Token.fetch(source: {:service_account, credentials, [claims: claims]})
      {:ok, %Goth.Token{...}}

  #### Generate an impersonated token using a service account credentials file:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      ...> claims = %{"sub" => "<IMPERSONATED_ACCOUNT_EMAIL>"}
      ...> Goth.Token.fetch(source: {:service_account, credentials, [claims: claims]})
      {:ok, %Goth.Token{...}}

  #### Retrieve the token using a refresh token:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> Goth.Token.fetch(source: {:refresh_token, credentials})
      {:ok, %Goth.Token{...}}

  You can generate a credentials file containing refresh token using `gcloud` utility like this:

      $ gcloud auth application-default login

  #### Retrieve the token using the Google metadata server:

      iex> Goth.Token.fetch(source: :metadata)
      {:ok, %Goth.Token{...}}

  See [Storing and retrieving instance metadata](https://cloud.google.com/compute/docs/storing-retrieving-metadata)
  for more information on metadata server.


  #### Passing custom Finch options

      iex> Goth.Token.fetch(source: source, http_client: {:finch, pool_timeout: 5000})
      {:ok, %Goth.Token{...}}

  """
  @doc since: "1.3.0"
  @spec fetch(keyword | map()) :: {:ok, t()} | {:error, Exception.t()}
  def fetch(config)

  def fetch(config) when is_list(config) do
    config |> Map.new() |> fetch()
  end

  def fetch(config) when is_map(config) do
    config
    |> Map.put_new(:source, {:default, []})
    |> Map.put_new(:http_client, {:finch, []})
    |> request()
  end

  defp request(%{source: {:default, opts}} = config) do
    case Goth.Config.get(:token_source) do
      {:ok, :oauth_jwt} ->
        {:ok, private_key} = Goth.Config.get(:private_key)
        {:ok, client_email} = Goth.Config.get(:client_email)

        credentials = %{
          "private_key" => private_key,
          "client_email" => client_email
        }

        request(%{config | source: {:service_account, credentials, opts}})

      {:ok, :oauth_refresh} ->
        {:ok, refresh_token} = Goth.Config.get(:refresh_token)
        {:ok, client_id} = Goth.Config.get(:client_id)
        {:ok, client_secret} = Goth.Config.get(:client_secret)

        credentials = %{
          "refresh_token" => refresh_token,
          "client_id" => client_id,
          "client_secret" => client_secret
        }

        request(%{config | source: {:refresh_token, credentials, opts}})

      {:ok, :metadata} ->
        request(%{config | source: {:metadata, opts}})

      {:ok, :workload_identity} ->
        {:ok, url} = Goth.Config.get(:token_url)
        {:ok, audience} = Goth.Config.get(:audience)
        {:ok, subject_token_type} = Goth.Config.get(:subject_token_type)
        {:ok, credential_source} = Goth.Config.get(:credential_source)
        {:ok, service_account_impersonation_url} = Goth.Config.get(:service_account_impersonation_url)

        credentials = %{
          "token_url" => url,
          "audience" => audience,
          "subject_token_type" => subject_token_type,
          "credential_source" => credential_source,
          "service_account_impersonation_url" => service_account_impersonation_url
        }

        request(%{config | source: {:workload_identity, credentials, opts}})
    end
  end

  defp request(%{source: {:service_account, credentials}} = config) do
    request(%{config | source: {:service_account, credentials, []}})
  end

  defp request(%{source: {:service_account, credentials, options}} = config)
       when is_map(credentials) and is_list(options) do
    url = Keyword.get(options, :url, @default_url)

    claims =
      Keyword.get_lazy(options, :claims, fn ->
        scope = options |> Keyword.get(:scopes, @default_scopes) |> Enum.join(" ")
        %{"scope" => scope}
      end)

    unless claims |> Map.keys() |> Enum.all?(&is_binary/1),
      do: raise("expected service account claims to be a map with string keys, got a map: #{inspect(claims)}")

    jwt = jwt_encode(claims, credentials)

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
    body = "grant_type=#{grant_type}&assertion=#{jwt}"

    response = request(config.http_client, method: :post, url: url, headers: headers, body: body)

    case handle_response(response) do
      {:ok, token} ->
        sub = Map.get(claims, "sub", token.sub)
        scope = Map.get(claims, "scope", token.scope)
        {:ok, %{token | scope: scope, sub: sub}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp request(%{source: {:refresh_token, credentials}} = config) do
    request(%{config | source: {:refresh_token, credentials, []}})
  end

  defp request(%{source: {:refresh_token, credentials, options}} = config)
       when is_map(credentials) and is_list(options) do
    url = Keyword.get(options, :url, @default_url)
    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]
    refresh_token = Map.fetch!(credentials, "refresh_token")
    client_id = Map.fetch!(credentials, "client_id")
    client_secret = Map.fetch!(credentials, "client_secret")

    body =
      URI.encode_query(
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: client_id,
        client_secret: client_secret
      )

    response = request(config.http_client, method: :post, url: url, headers: headers, body: body)
    handle_response(response)
  end

  defp request(%{source: :metadata} = config) do
    request(%{config | source: {:metadata, []}})
  end

  defp request(%{source: {:metadata, options}} = config) when is_list(options) do
    {url, audience} = metadata_options(options)
    headers = [{"metadata-flavor", "Google"}]
    response = request(config.http_client, method: :get, url: url, headers: headers, body: "")

    case audience do
      nil -> handle_response(response)
      _ -> handle_jwt_response(response)
    end
  end

  defp request(%{source: {:workload_identity, credentials}} = config) do
    request(%{config | source: {:workload_identity, credentials, []}})
  end

  defp request(%{source: {:workload_identity, credentials, options}} = config)
       when is_map(credentials) and is_list(options) do
    %{
      "token_url" => token_url,
      "audience" => audience,
      "subject_token_type" => subject_token_type
    } = credentials

    subject_token =
      case credentials do
        %{"subject_token" => subject_token} ->
          subject_token

        %{"credential_source" => credential_source} ->
          subject_token_from_credential_source(credential_source, config)
      end

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    body =
      URI.encode_query(%{
        "audience" => audience,
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "requested_token_type" => "urn:ietf:params:oauth:token-type:access_token",
        "scope" => List.first(@default_scopes),
        "subject_token_type" => subject_token_type,
        "subject_token" => subject_token
      })

    response = request(config.http_client, method: :post, url: token_url, headers: headers, body: body)

    handle_workload_identity_response(response, config)
  end

  defp metadata_options(options) do
    account = Keyword.get(options, :account, "default")
    audience = Keyword.get(options, :audience, nil)
    path = "/computeMetadata/v1/instance/service-accounts/"
    base_url = Keyword.get(options, :url, "http://metadata.google.internal")

    url =
      case audience do
        nil -> "#{base_url}#{path}#{account}/token"
        audience -> "#{base_url}#{path}#{account}/identity?audience=#{audience}"
      end

    {url, audience}
  end

  defp subject_token_from_credential_source(%{"url" => url, "headers" => headers, "format" => format}, config) do
    with {:ok, %{status: 200, body: body}} <-
           request(config.http_client, method: :get, url: url, headers: Enum.to_list(headers), body: "") do
      subject_token_from_binary(body, format)
    end
  end

  defp subject_token_from_credential_source(%{"file" => file, "format" => format}, _config) do
    File.read!(file) |> subject_token_from_binary(format)
  end

  # the default file type if not specified is "text"
  defp subject_token_from_credential_source(%{"file" => file}, _config) do
    File.read!(file)
  end

  defp subject_token_from_binary(binary, %{"type" => "text"}), do: binary

  defp subject_token_from_binary(binary, %{"type" => "json", "subject_token_field_name" => field}),
    do: binary |> Jason.decode!() |> Map.fetch!(field)

  defp handle_jwt_response({:ok, %{status: 200, body: body}}) do
    {:ok, build_token(%{"id_token" => body})}
  end

  defp handle_jwt_response(response), do: handle_response(response)

  defp handle_workload_identity_response(
         {:ok, %{status: 200, body: body}},
         %{source: {:workload_identity, %{"service_account_impersonation_url" => url}, options}} = config
       ) do
    %{"access_token" => token, "token_type" => type} = Jason.decode!(body)

    headers = [{"content-type", "text/json"}, {"Authorization", "#{type} #{token}"}]
    body = Jason.encode!(%{scope: Keyword.get(options, :scopes, @default_scopes)})
    response = request(config.http_client, method: :post, url: url, headers: headers, body: body)

    handle_response(response)
  end

  defp handle_workload_identity_response(response, _config), do: handle_response(response)

  defp handle_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    {:ok, build_token(body)}
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, attrs} -> {:ok, build_token(attrs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_response({:ok, response}) do
    message = """
    unexpected status #{response.status} from Google

    #{response.body}
    """

    {:error, RuntimeError.exception(message)}
  end

  defp handle_response({:error, exception}) do
    {:error, exception}
  end

  defp jwt_encode(claims, %{"private_key" => private_key, "client_email" => client_email}) do
    jwk = JOSE.JWK.from_pem(private_key)
    header = %{"alg" => "RS256", "typ" => "JWT"}
    unix_time = System.os_time(:second)

    default_claims = %{
      "iss" => client_email,
      "aud" => "https://www.googleapis.com/oauth2/v4/token",
      "exp" => unix_time + 3600,
      "iat" => unix_time
    }

    claims = Map.merge(default_claims, claims)

    JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact() |> elem(1)
  end

  defp build_token(%{"access_token" => _} = attrs) do
    %__MODULE__{
      expires: System.os_time(:second) + attrs["expires_in"],
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: attrs["scope"],
      sub: attrs["sub"]
    }
  end

  defp build_token(%{"id_token" => jwt}) when is_binary(jwt) do
    %JOSE.JWT{fields: fields} = JOSE.JWT.peek_payload(jwt)

    %__MODULE__{
      expires: fields["exp"],
      token: jwt,
      type: "Bearer",
      scope: fields["aud"],
      sub: fields["sub"]
    }
  end

  defp build_token(%{"accessToken" => token, "expireTime" => expire_time}) do
    {:ok, datetime, 0} = DateTime.from_iso8601(expire_time)

    %__MODULE__{
      expires: DateTime.to_unix(datetime),
      token: token,
      type: "Bearer"
    }
  end

  defp request({:finch, extra_options}, options) do
    Goth.__finch__(options ++ extra_options)
  end

  defp request({mod, _} = config, options) when is_atom(mod) do
    Goth.HTTPClient.request(config, options[:method], options[:url], options[:headers], options[:body], [])
  end

  defp request({fun, extra_options}, options) when is_function(fun, 1) do
    fun.(options ++ extra_options)
  end

  # Everything below is deprecated.

  alias Goth.Client
  alias Goth.TokenStore

  # Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  # scope or multiple scopes joined by a space. See [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/googlescopes) for all available scopes.

  # `sub` needs to be specified if impersonation is used to prevent cache
  # leaking between users.

  # ## Example
  #     iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
  #     {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  @deprecated "Use Goth.fetch/1 instead"
  def for_scope(info, sub \\ nil)

  @spec for_scope(scope :: String.t(), sub :: String.t() | nil) :: {:ok, t} | {:error, any()}
  def for_scope(scope, sub) when is_binary(scope) do
    case TokenStore.find({:default, scope}, sub) do
      :error -> retrieve_and_store!({:default, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @spec for_scope(info :: {String.t() | atom(), String.t()}, sub :: String.t() | nil) ::
          {:ok, t} | {:error, any()}
  def for_scope({account, scope}, sub) do
    case TokenStore.find({account, scope}, sub) do
      :error -> retrieve_and_store!({account, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc false
  # Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  def from_response_json(scope, sub \\ nil, json)

  @spec from_response_json(String.t(), String.t() | nil, String.t()) :: t
  def from_response_json(scope, sub, json) when is_binary(scope) do
    {:ok, attrs} = json |> Jason.decode()

    %__MODULE__{
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: scope,
      sub: sub,
      expires: :os.system_time(:seconds) + attrs["expires_in"],
      account: :default
    }
  end

  @spec from_response_json(
          {atom() | String.t(), String.t()},
          String.t() | nil,
          String.t()
        ) :: t
  def from_response_json({account, scope}, sub, json) do
    {:ok, attrs} = json |> Jason.decode()

    %__MODULE__{
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: scope,
      sub: sub,
      expires: :os.system_time(:seconds) + attrs["expires_in"],
      account: account
    }
  end

  # Retrieve a new access token from the API. This is useful for expired tokens,
  # although `Goth` automatically handles refreshing tokens for you, so you should
  # rarely if ever actually need to call this method manually.
  @doc false
  @spec refresh!(t() | {any(), any()}) :: {:ok, t()}
  def refresh!(%__MODULE__{account: account, scope: scope, sub: sub}),
    do: refresh!({account, scope}, sub)

  def refresh!(%__MODULE__{account: account, scope: scope}), do: refresh!({account, scope})

  @doc false
  @spec refresh!({any(), any()}, any()) :: {:ok, t()}
  def refresh!({account, scope}, sub \\ nil), do: retrieve_and_store!({account, scope}, sub)

  @doc false
  def queue_for_refresh(%__MODULE__{} = token) do
    diff = token.expires - :os.system_time(:seconds)

    if diff < 10 do
      # just do it immediately
      Task.async(fn ->
        __MODULE__.refresh!(token)
      end)
    else
      :timer.apply_after((diff - 10) * 1000, __MODULE__, :refresh!, [token])
    end
  end

  defp retrieve_and_store!({account, scope}, sub) do
    Client.get_access_token({account, scope}, sub: sub)
    |> case do
      {:ok, token} ->
        TokenStore.store({account, scope}, sub, token)
        {:ok, token}

      other ->
        other
    end
  end
end
