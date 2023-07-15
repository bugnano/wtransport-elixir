defmodule Wtransport.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Wtransport.Worker.start_link(arg)
      # {Wtransport.Worker, arg}
      {Wtransport.Runtime, []},
      {DynamicSupervisor, name: Wtransport.DynamicSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Wtransport.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
