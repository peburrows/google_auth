defmodule Goth.TokenTest do
  use ExUnit.Case, async: true

  test "fetch/1 with service account" do
    bypass = Bypass.open()
    default_scope = "https://www.googleapis.com/auth/cloud-platform"

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = featch_request_body(conn)

      assert %{
               "aud" => "https://www.googleapis.com/oauth2/v4/token",
               "iss" => "alice@example.com",
               "scope" => ^default_scope
             } = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"#{default_scope}","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == default_scope
    assert token.sub == nil
  end

  test "fetch/1 with service account and impersonating user" do
    bypass = Bypass.open()
    default_scope = "https://www.googleapis.com/auth/cloud-platform"

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = featch_request_body(conn)

      assert %{
               "iss" => "alice@example.com",
               "scope" => ^default_scope,
               "sub" => "bob@example.com"
             } = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"#{default_scope}","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    creds = random_service_account_credentials()
    bypass_url = "http://localhost:#{bypass.port}"
    claims = %{"sub" => "bob@example.com", "scope" => default_scope}
    service_account_source = {:service_account, creds, url: bypass_url, claims: claims}

    {:ok, token} = Goth.Token.fetch(%{source: service_account_source})
    assert token.token == "dummy"
    assert token.scope == default_scope
    assert token.sub == "bob@example.com"
  end

  test "fetch/1 with service account and multiple scopes" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = featch_request_body(conn)

      assert %{"scope" => "aaa bbb"} = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"aaa bbb","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}", scopes: ["aaa", "bbb"]}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.scope == "aaa bbb"
  end

  test "fetch/1 with service account and OAuth ID token response" do
    bypass = Bypass.open()

    cloud_function_url = "https://europe-west1-project-id.cloudfunctions.net/test-function"

    jwk_es256 = JOSE.JWK.generate_key({:ec, :secp256r1})
    header = %{"alg" => "ES256", "typ" => "JWT"}

    payload = %{
      "aud" => cloud_function_url,
      "azp" => "example@project-id.iam.gserviceaccount.com",
      "email" => "example@project-id.iam.gserviceaccount.com",
      "email_verified" => true,
      "exp" => 1_623_761_103,
      "iat" => 1_623_757_503,
      "iss" => "https://accounts.google.com",
      "sub" => "110725120108142672649"
    }

    jwt = JOSE.JWS.sign(jwk_es256, Jason.encode!(payload), header) |> JOSE.JWS.compact() |> elem(1)

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"id_token":"#{jwt}"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}", scopes: [cloud_function_url]}
    }

    assert {:ok,
            %{
              token: ^jwt,
              scope: ^cloud_function_url,
              expires: 1_623_761_103,
              type: "Bearer",
              sub: "110725120108142672649"
            }} = Goth.Token.fetch(config)
  end

  test "fetch/1 with invalid response" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, fn conn ->
      body = ~s|bad|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"}
    }

    {:error, %Jason.DecodeError{}} = Goth.Token.fetch(config)

    Bypass.down(bypass)
    {:error, error} = Goth.Token.fetch(config)
    assert error.reason == :econnrefused
  end

  test "fetch/1 with refresh token" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:refresh_token, %{"client_id" => "aaa", "client_secret" => "bbb", "refresh_token" => "ccc"},
         url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == "dummy_scope"
  end

  test "fetch/1 from instance metadata" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert conn.request_path == "/computeMetadata/v1/instance/service-accounts/alice/token"

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source: {:metadata, account: "alice", url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  test "fetch/1 from workload identity" do
    token_bypass = Bypass.open()
    sa_token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(sa_token_bypass, fn conn ->
      assert conn.request_path ==
               "/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"

      body = ~s|{"accessToken":"dummy_sa","expireTime":"2024-06-30T00:00:00Z"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.put(
        "service_account_impersonation_url",
        "http://localhost:#{sa_token_bypass.port}/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"
      )

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy_sa"
    assert token.scope == nil
  end

  test "fetch/1 from direct workload identity" do
    token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-direct-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  test "fetch/1 from direct workload identity, json format" do
    token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-direct-workload-identity-json.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  test "fetch/1 from workload identity, subject_token supplied" do
    token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-direct-workload-identity-json.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  test "fetch/1 from url-based workload identity" do
    token_bypass = Bypass.open()
    subject_token_bypass = Bypass.open()

    Bypass.expect(subject_token_bypass, fn conn ->
      assert conn.request_path == "/get/credentials"

      body = File.read!("test/data/workload-identity-token.json")
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-url-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.update!("credential_source", fn source ->
        Map.put(source, "url", "http://localhost:#{subject_token_bypass.port}/get/credentials")
      end)

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  defp random_service_account_credentials do
    %{
      "private_key" => random_private_key(),
      "client_email" => "alice@example.com",
      "token_uri" => "/"
    }
  end

  defp random_private_key do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:ok, private_key}
    :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
  end

  defp featch_request_body(%Plug.Conn{} = conn) do
    assert {:ok, req_body, _} = Plug.Conn.read_body(conn)
    URI.decode_query(req_body)
  end

  def jwt_decode(jwt) when is_binary(jwt), do: jwt |> JOSE.JWT.peek_payload() |> Map.get(:fields)
end
