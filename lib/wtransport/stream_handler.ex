defmodule Wtransport.StreamHandler do
  alias Wtransport.Socket
  alias Wtransport.Stream

  @callback handle_stream(socket :: Socket.t(), stream :: Stream.t(), state :: term()) :: term()

  @callback handle_data(
              data :: String.t(),
              socket :: Socket.t(),
              stream :: Stream.t(),
              state :: term()
            ) :: term()

  defmacro __using__(_opts) do
    quote do
      @behaviour Wtransport.StreamHandler

      # Default behaviour

      def handle_stream(%Socket{} = _socket, %Stream{} = _stream, state), do: {:continue, state}

      def handle_data(_data, %Socket{} = _socket, %Stream{} = _stream, state),
        do: {:continue, state}

      defoverridable Wtransport.StreamHandler

      use GenServer, restart: :temporary

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
          {:continue, new_state} ->
            {:noreply, {socket, stream, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

            {:stop, :normal, {socket, stream, state}}
        end

        {:noreply, {socket, stream, state}}
      end
    end
  end
end
