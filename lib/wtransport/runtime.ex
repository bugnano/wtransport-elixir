defmodule Wtransport.Runtime do
  use GenServer

  alias Wtransport.Socket

  @enforce_keys [:shutdown_tx, :pid_crashed_tx]
  defstruct [:shutdown_tx, :pid_crashed_tx]


  # Client

  def start_link(_init_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def pid_crashed(pid) do
    GenServer.cast(__MODULE__, {:pid_crashed, pid})
  end

  # Server (callbacks)

  @impl true
  def init(_init_arg) do
    host = "localhost"
    port = 4433
    certfile = "/home/fri/mkcert/localhost+2.pem"
    keyfile = "/home/fri/mkcert/localhost+2-key.pem"

    IO.puts("[FRI] -- Wtransport.Runtime.init")
    IO.inspect(self())
    {:ok, runtime} = Wtransport.Native.start_runtime(self(), host, port, certfile, keyfile)
    IO.puts("[FRI] -- runtime")
    IO.inspect(runtime)

    initial_state = %{
      runtime: runtime
    }

    # Process.send_after(self(), :stop_runtime, 2500)

    {:ok, initial_state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("[FRI] -- Wtransport.Runtime.terminate")
    IO.inspect(reason)
    IO.inspect(state)

    Wtransport.Native.stop_runtime(state.runtime)

    :ok
  end

  @impl true
  def handle_call(:pop, _from, state) do
    [to_caller | new_state] = state
    {:reply, to_caller, new_state}
  end

  @impl true
  def handle_cast({:pid_crashed, pid}, state) do
    Wtransport.Native.pid_crashed(state.runtime, pid)

    {:noreply, state}
  end

  @impl true
  def handle_info(:stop_runtime, state) do
    IO.puts("[FRI] -- Wtransport.Runtime.handle_info :stop_runtime")
    {:ok, {}} = Wtransport.Native.stop_runtime(state.runtime)
    IO.puts("[FRI] -- After Wtransport.Runtime.handle_info :stop_runtime")
    {:noreply, state}
  end

  @impl true
  def handle_info({:session_request, %Socket{} = socket}, state) do
    IO.puts("[FRI] -- Wtransport.Runtime.handle_info :session_request")

    {:ok, _pid} =
      DynamicSupervisor.start_child(Wtransport.DynamicSupervisor, {Wtransport.SocketHandler, socket})

    {:noreply, state}
  end
end
