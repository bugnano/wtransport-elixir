defmodule Wtransport.SocketHandler do
  alias Wtransport.Socket
  alias Wtransport.Stream

  @callback handle_connection(socket :: Socket.t(), state :: term()) :: term()

  @callback handle_datagram(
              dgram :: String.t(),
              socket :: Socket.t(),
              state :: term()
            ) :: term()

  defmacro __using__(_opts) do
    quote do
      @behaviour Wtransport.SocketHandler

      # Default behaviour

      def handle_connection(%Socket{} = _socket, state), do: {:continue, state}

      def handle_datagram(_dgram, %Socket{} = _socket, state), do: {:continue, state}

      defoverridable Wtransport.SocketHandler

      use GenServer, restart: :temporary

      # Client

      def start_link({%Socket{} = socket, stream_handler}) do
        GenServer.start_link(__MODULE__, {socket, stream_handler})
      end

      # Server (callbacks)

      @impl true
      def init({%Socket{} = socket, stream_handler}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.init")
        IO.inspect(socket)

        state = %{}

        {:ok, {socket, stream_handler, state}, {:continue, :session_request}}
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
      def handle_continue(:session_request, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_continue :session_request")

        case handle_connection(socket, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_session_request(socket, :ok, self())

            {:noreply, {socket, stream_handler, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:ok, {}} = Wtransport.Native.reply_session_request(socket, :error, self())

            {:stop, :normal, {socket, stream_handler, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :error")
        IO.inspect(error)

        {:stop, :normal, {socket, stream_handler, state}}
      end

      @impl true
      def handle_info({:datagram_received, dgram}, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :datagram_received")

        case handle_datagram(dgram, socket, state) do
          {:continue, new_state} ->
            {:noreply, {socket, stream_handler, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:stop, :normal, {socket, stream_handler, state}}
        end

        {:noreply, {socket, stream_handler, state}}
      end

      @impl true
      def handle_info({:accept_stream, %Stream{} = stream}, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :accept_stream")

        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Wtransport.DynamicSupervisor,
            {stream_handler, {socket, stream}}
          )

        {:noreply, {socket, stream_handler, state}}
      end
    end
  end
end
