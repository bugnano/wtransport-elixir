defmodule Wtransport.Runtime do
  use GenServer
  use TypedStruct

  require Logger

  alias Wtransport.Runtime
  alias Wtransport.SessionRequest

  typedstruct do
    field(:shutdown_tx, reference(), enforce: true)
  end

  defmodule State do
    use TypedStruct

    typedstruct do
      field(:runtime, Runtime.t(), enforce: true)
      field(:connection_handler, atom(), enforce: true)
      field(:stream_handler, atom() | nil)
      field(:supervisor_pid, pid(), enforce: true)
    end
  end

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
    stream_handler = Keyword.get(wtransport_options, :stream_handler)

    Logger.debug("Starting the wtransport runtime #{inspect(wtransport_options)}")
    {:ok, runtime} = Wtransport.Native.start_runtime(self(), host, port, certfile, keyfile)
    Logger.info("Started the wtransport runtime #{inspect(wtransport_options)}")

    initial_state = %State{
      runtime: runtime,
      connection_handler: connection_handler,
      stream_handler: stream_handler,
      supervisor_pid: supervisor_pid
    }

    {:ok, initial_state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    Logger.debug("terminate")

    Wtransport.Native.stop_runtime(state.runtime)

    :ok
  end

  @impl true
  def handle_info({:wtransport_session_request, %SessionRequest{} = request}, %State{} = state) do
    Logger.debug(":wtransport_session_request")

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        state.supervisor_pid,
        {state.connection_handler, {request, state}}
      )

    {:noreply, state}
  end
end
