defmodule Wtransport.Runtime do
  use GenServer

  alias Wtransport.SessionRequest

  @enforce_keys [:shutdown_tx, :pid_crashed_tx]
  defstruct [:shutdown_tx, :pid_crashed_tx]

  # Client

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def pid_crashed(pid) do
    GenServer.cast(__MODULE__, {:pid_crashed, pid})
  end

  # Server (callbacks)

  @impl true
  def init(init_arg) do
    host = Keyword.fetch!(init_arg, :host)
    port = Keyword.fetch!(init_arg, :port)
    certfile = Keyword.fetch!(init_arg, :certfile)
    keyfile = Keyword.fetch!(init_arg, :keyfile)
    connection_handler = Keyword.fetch!(init_arg, :connection_handler)
    stream_handler = Keyword.fetch!(init_arg, :stream_handler)

    IO.puts("[FRI] -- Wtransport.Runtime.init")
    IO.inspect(self())
    {:ok, runtime} = Wtransport.Native.start_runtime(self(), host, port, certfile, keyfile)
    IO.puts("[FRI] -- runtime")
    IO.inspect(runtime)

    initial_state = %{
      runtime: runtime,
      connection_handler: connection_handler,
      stream_handler: stream_handler
    }

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
  def handle_info({:session_request, %SessionRequest{} = request}, state) do
    IO.puts("[FRI] -- Wtransport.Runtime.handle_info :session_request")

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Wtransport.DynamicSupervisor,
        {state.connection_handler, {request, state.stream_handler}}
      )

    {:noreply, state}
  end
end
