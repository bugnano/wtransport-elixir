defmodule Wtransport.Supervisor do
  # Automatically defines child_spec/1
  use DynamicSupervisor

  def start_link(init_arg) do
    name = Keyword.get(init_arg, :name, __MODULE__)

    {:ok, pid} = DynamicSupervisor.start_link(__MODULE__, init_arg, name: name)

    {:ok, _runtime_pid} =
      DynamicSupervisor.start_child(pid, {Wtransport.Runtime, {init_arg, pid}})

    {:ok, pid}
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
