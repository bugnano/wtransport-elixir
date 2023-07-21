defmodule Wtransport.SocketHandler do
  use GenServer, restart: :temporary

  # Client

  def start_link(%Wtransport.Socket{} = socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  # Server (callbacks)

  @impl true
  def init(%Wtransport.Socket{} = socket) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.init")
    IO.inspect(socket)

    state = %{}

    {:ok, {socket, state}, {:continue, :session_request}}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.terminate")
    IO.inspect(reason)
    IO.inspect(state)

    Wtransport.Runtime.pid_crashed(self())

    :ok
  end

  @impl true
  def handle_continue(:session_request, {%Wtransport.Socket{} = socket, state}) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.handle_continue :session_request")

    case handle_connection(socket, state) do
      {:continue, new_state} ->
        {:ok, {}} = Wtransport.Native.reply_session_request(socket, :ok, self())

        {:noreply, {socket, new_state}}

      _ ->
        IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

        {:ok, {}} = Wtransport.Native.reply_session_request(socket, :error, self())

        {:stop, :normal, {socket, state}}
    end
  end

  @impl true
  def handle_info({:error, error}, {%Wtransport.Socket{} = socket, state}) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :error")
    IO.inspect(error)

    {:stop, :normal, {socket, state}}
  end

  @impl true
  def handle_info({:datagram_received, dgram}, {%Wtransport.Socket{} = socket, state}) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :datagram_received")

    case handle_datagram(dgram, socket, state) do
      {:continue, new_state} -> {:noreply, {socket, new_state}}

      _ ->
        IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

        # TODO -- Handle native side

        {:stop, :normal, {socket, state}}
    end

    {:noreply, {socket, state}}
  end

  # Functions to be overridden

  def handle_connection(%Wtransport.Socket{} = _socket, state) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.handle_connection")
    {:continue, state}
  end

  def handle_datagram(dgram, %Wtransport.Socket{} = socket, state) do
    IO.puts("[FRI] -- Wtransport.SocketHandler.handle_datagram")

    :ok = Wtransport.Socket.send_datagram(socket, "Reply from FRI: -- #{dgram} -- END FRI")

    {:continue, state}
  end
end
