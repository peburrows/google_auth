use Mix.Config

config :goth,
  json: "test/data/test-credentials.json" |> Path.expand() |> File.read!()

config :goth, config_root_dir: "test/missing"

# config :bypass, enable_debug_log: true
