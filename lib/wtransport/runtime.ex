defmodule Wtransport.Runtime do
  use GenServer

  # Client

  def start_link(_init_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # Server (callbacks)

  @impl true
  def init(_init_arg) do
    host = "localhost"
    port = 4433
    cert_chain = "/home/fri/mkcert/localhost+2.pem"
    priv_key = "/home/fri/mkcert/localhost+2-key.pem"

    IO.puts("[FRI] -- Wtransport.Runtime.init")
    IO.inspect(self())
    {:ok, runtime} = Wtransport.Native.start_runtime(self(), host, port, cert_chain, priv_key)
    IO.puts("[FRI] -- runtime")
    IO.inspect(runtime)

    initial_state = %{
      runtime: runtime
    }

    Process.send_after(self(), :stop_runtime, 2500)

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
  def handle_cast({:push, element}, state) do
    new_state = [element | state]
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:stop_runtime, state) do
    IO.puts("[FRI] -- Wtransport.Runtime.handle_info :fri")
    {:ok, {}} = Wtransport.Native.stop_runtime(state.runtime)
    IO.puts("[FRI] -- After Wtransport.Runtime.handle_info :fri")
    {:noreply, state}
  end
end
