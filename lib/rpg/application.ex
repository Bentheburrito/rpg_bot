defmodule RPG.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    client_opts = [
      access_token: System.fetch_env!("MX_ACCESS_TOKEN"),
      homeserver: System.fetch_env!("MX_HOMESERVER_URL"),
      storage: Polyjuice.Client.Storage.Ets.open(),
      user_id: System.fetch_env!("MX_USER_ID")
    ]

    children = [
      {Phoenix.PubSub, name: RPG.PubSub},
      {DynamicSupervisor, name: RPG.PartySupervisor},
      RPG,
      {RPG.Consumer, client_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RPG.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
