defmodule Wtransport.Handler do
  use GenServer

  # Client

  def start_link(%Wtransport.SessionRequest{} = request) do
    GenServer.start_link(__MODULE__, request)
  end

  # Server (callbacks)

  @impl true
  def init(%Wtransport.SessionRequest{} = request) do
    IO.puts("[FRI] -- Wtransport.Handler.init")
    IO.inspect(request)

    send(self(), {:session_request, request})
    initial_state = %{}

    {:ok, initial_state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("[FRI] -- Wtransport.Handler.terminate")
    IO.inspect(reason)
    IO.inspect(state)

    :ok
  end

  @impl true
  def handle_call(:pop, _from, state) do
    [to_caller | new_state] = state
    {:reply, to_caller, new_state}
  end

  @impl true
  def handle_cast({:push, element}, state) do
    new_state = [element | state]
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:session_request, %Wtransport.SessionRequest{} = request}, state) do
    IO.puts("[FRI] -- Wtransport.Handler.handle_info :session_request")

    case handle_session_request(request, state) do
      {:ok, new_state} ->
        {:ok, {}} = Wtransport.Native.reply_session_request(request, :ok, self())

        {:noreply, new_state}

      _ ->
        IO.puts("[FRI] -- Terminating Wtransport.Handler")

        {:ok, {}} = Wtransport.Native.reply_session_request(request, :error, self())

        DynamicSupervisor.terminate_child(Wtransport.DynamicSupervisor, self())

        {:stop, :normal, state}
    end
  end

  # Functions to be overridden

  def handle_session_request(%Wtransport.SessionRequest{} = _request, state) do
    IO.puts("[FRI] -- Wtransport.Handler.handle_session_request")
    {:ok, state}
  end
end
