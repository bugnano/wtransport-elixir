defmodule Wtransport.SocketHandler do
  alias Wtransport.SessionRequest
  alias Wtransport.Socket
  alias Wtransport.Connection
  alias Wtransport.Stream

  @callback handle_session(socket :: Socket.t()) :: term()

  @callback handle_connection(socket :: Socket.t(), state :: term()) :: term()

  @callback handle_datagram(
              dgram :: String.t(),
              socket :: Socket.t(),
              state :: term()
            ) :: term()

  @callback handle_close(socket :: Socket.t(), state :: term()) :: term()

  @callback handle_error(
              reason :: String.t(),
              socket :: Socket.t(),
              state :: term()
            ) :: term()

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Wtransport.SocketHandler

      # Default behaviour

      def handle_session(%Socket{} = _socket), do: {:continue, %{}}

      def handle_connection(%Socket{} = _socket, state), do: {:continue, state}

      def handle_datagram(_dgram, %Socket{} = _socket, state), do: {:continue, state}

      def handle_close(%Socket{} = _socket, _state), do: :ok

      def handle_error(_reason, %Socket{} = _socket, _state), do: :ok

      defoverridable Wtransport.SocketHandler

      use GenServer, restart: :temporary

      # Client

      def start_link({%SessionRequest{} = request, stream_handler}) do
        GenServer.start_link(__MODULE__, {request, stream_handler})
      end

      # Server (callbacks)

      @impl true
      def init({%SessionRequest{} = request, stream_handler}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.init")

        socket = struct(%Socket{}, Map.from_struct(request))
        IO.inspect(socket)

        {:ok, {socket, stream_handler, request}, {:continue, :session_request}}
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
      def handle_continue(
            :session_request,
            {%Socket{} = socket, stream_handler, %SessionRequest{} = request}
          ) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_continue :session_request")

        case handle_session(socket) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(request.session_request_tx, :ok, self())

            {:noreply, {socket, stream_handler, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:ok, {}} =
              Wtransport.Native.reply_request(request.session_request_tx, :error, self())

            {:stop, :normal, {socket, stream_handler, %{}}}
        end
      end

      @impl true
      def handle_info(
            {:connection, %Connection{} = connection},
            {%Socket{} = socket, stream_handler, state}
          ) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :connection")

        socket = struct(socket, Map.from_struct(connection))
        IO.inspect(socket)

        case handle_connection(socket, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(connection.connection_tx, :ok, self())

            {:noreply, {socket, stream_handler, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:ok, {}} = Wtransport.Native.reply_request(connection.connection_tx, :error, self())

            {:stop, :normal, {socket, stream_handler, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :error")
        IO.inspect(error)

        handle_error(error, socket, state)

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
      end

      @impl true
      def handle_info(
            {:accept_stream, %Stream{} = stream},
            {%Socket{} = socket, stream_handler, state}
          ) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :accept_stream")

        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Wtransport.DynamicSupervisor,
            {stream_handler, {socket, stream}}
          )

        {:noreply, {socket, stream_handler, state}}
      end

      @impl true
      def handle_info(:conn_closed, {%Socket{} = socket, stream_handler, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :conn_closed")

        handle_close(socket, state)

        {:stop, :normal, {socket, stream_handler, state}}
      end
    end
  end
end
