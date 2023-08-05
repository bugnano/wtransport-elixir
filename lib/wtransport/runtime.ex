defmodule Wtransport.Runtime do
  use GenServer

  require Logger

  alias Wtransport.SessionRequest

  @enforce_keys [:shutdown_tx]
  defstruct [:shutdown_tx]

  # Client

  def start_link({wtransport_options, supervisor_pid}) do
    GenServer.start_link(__MODULE__, {wtransport_options, supervisor_pid})
  end

  # Server (callbacks)

  @impl true
  def init({wtransport_options, supervisor_pid}) do
    wtransport_options =
      Keyword.take(wtransport_options, [
        :host,
        :port,
        :certfile,
        :keyfile,
        :connection_handler,
        :stream_handler
      ])

    host = Keyword.fetch!(wtransport_options, :host)
    port = Keyword.fetch!(wtransport_options, :port)
    certfile = Keyword.fetch!(wtransport_options, :certfile)
    keyfile = Keyword.fetch!(wtransport_options, :keyfile)
    connection_handler = Keyword.fetch!(wtransport_options, :connection_handler)
    stream_handler = Keyword.fetch!(wtransport_options, :stream_handler)

    Logger.debug("Starting the wtransport runtime #{inspect(wtransport_options)}")
    {:ok, runtime} = Wtransport.Native.start_runtime(self(), host, port, certfile, keyfile)
    Logger.info("Started the wtransport runtime #{inspect(wtransport_options)}")

    initial_state = %{
      runtime: runtime,
      connection_handler: connection_handler,
      stream_handler: stream_handler,
      supervisor_pid: supervisor_pid
    }

    {:ok, initial_state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("terminate")

    Wtransport.Native.stop_runtime(state.runtime)

    :ok
  end

  @impl true
  def handle_call(:pop, _from, state) do
    [to_caller | new_state] = state
    {:reply, to_caller, new_state}
  end

  @impl true
  def handle_info({:session_request, %SessionRequest{} = request}, state) do
    Logger.debug(":session_request")

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        state.supervisor_pid,
        {state.connection_handler, {request, state}}
      )

    {:noreply, state}
  end
end
