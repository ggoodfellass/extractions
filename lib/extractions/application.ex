defmodule Extractions.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Extractions.Worker.start_link(arg)
      # {Extractions.Worker, arg}
      :hackney_pool.child_spec(:seaweedfs_upload_pool, [timeout: 5000, max_connections: 1000]),
      :hackney_pool.child_spec(:seaweedfs_download_pool, [timeout: 5000, max_connections: 1000])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    :ets.new(:storage_servers, [:set, :public, :named_table])
    opts = [strategy: :one_for_one, name: Extractions.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
