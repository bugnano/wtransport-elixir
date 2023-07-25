defmodule WtransportEcho.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    wtransport_options = Application.fetch_env!(:wtransport_echo, :wtransport_options)

    children = [
      # Starts a worker by calling: WtransportEcho.Worker.start_link(arg)
      # {WtransportEcho.Worker, arg}
      {Wtransport.Supervisor, wtransport_options}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WtransportEcho.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
