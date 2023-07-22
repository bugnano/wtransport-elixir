defmodule Wtransport.StreamHandler do
  use GenServer, restart: :temporary

  alias Wtransport.Socket
  alias Wtransport.Stream

  # Client

  def start_link({%Socket{} = socket, %Stream{} = stream}) do
    GenServer.start_link(__MODULE__, {socket, stream})
  end

  # Server (callbacks)

  @impl true
  def init({%Socket{} = socket, %Stream{} = stream}) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.init")
    IO.inspect(socket)
    IO.inspect(stream)

    state = %{}

    {:ok, {socket, stream, state}, {:continue, :accept_stream}}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.terminate")
    IO.inspect(reason)
    IO.inspect(state)

    Wtransport.Runtime.pid_crashed(self())

    :ok
  end

  @impl true
  def handle_continue(:accept_stream, {%Socket{} = socket, %Stream{} = stream, state}) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.handle_continue :accept_stream")

    case handle_stream(socket, stream, state) do
      {:continue, new_state} ->
        {:ok, {}} = Wtransport.Native.reply_accept_stream(stream, :ok, self())

        {:noreply, {socket, stream, new_state}}

      _ ->
        IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

        {:ok, {}} = Wtransport.Native.reply_accept_stream(stream, :error, self())

        {:stop, :normal, {socket, stream, state}}
    end
  end

  @impl true
  def handle_info({:error, error}, {%Socket{} = socket, %Stream{} = stream, state}) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.handle_info :error")
    IO.inspect(error)

    {:stop, :normal, {socket, stream, state}}
  end

  @impl true
  def handle_info({:data_received, data}, {%Socket{} = socket, %Stream{} = stream, state}) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.handle_info :data_received")

    case handle_data(data, socket, stream, state) do
      {:continue, new_state} -> {:noreply, {socket, stream, new_state}}

      _ ->
        IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

        {:stop, :normal, {socket, stream, state}}
    end

    {:noreply, {socket, stream, state}}
  end

  # Functions to be overridden

  def handle_stream(%Socket{} = _socket, %Stream{} = _stream, state) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.handle_stream")
    {:continue, state}
  end

  def handle_data(data, %Socket{} = _socket, %Stream{} = stream, state) do
    IO.puts("[FRI] -- Wtransport.StreamHandler.handle_data")

    :ok = Stream.send(stream, "Reply from FRI: -- #{data} -- END FRI")

    {:continue, state}
  end
end
