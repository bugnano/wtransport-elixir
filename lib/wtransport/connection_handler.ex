defmodule Wtransport.ConnectionHandler do
  alias Wtransport.SessionRequest
  alias Wtransport.Session
  alias Wtransport.ConnectionRequest
  alias Wtransport.Connection
  alias Wtransport.StreamRequest

  @callback handle_session(session :: Session.t()) :: term()

  @callback handle_connection(connection :: Connection.t(), state :: term()) :: term()

  @callback handle_datagram(
              dgram :: String.t(),
              connection :: Connection.t(),
              state :: term()
            ) :: term()

  @callback handle_close(connection :: Connection.t(), state :: term()) :: term()

  @callback handle_error(
              reason :: String.t(),
              connection :: Connection.t(),
              state :: term()
            ) :: term()

  defmacro __using__(_opts) do
    quote location: :keep do
      require Logger

      @behaviour Wtransport.ConnectionHandler

      # Default behaviour

      def handle_session(%Session{} = _session), do: {:continue, %{}}

      def handle_connection(%Connection{} = _connection, state), do: {:continue, state}

      def handle_datagram(_dgram, %Connection{} = _connection, state), do: {:continue, state}

      def handle_close(%Connection{} = _connection, _state), do: :ok

      def handle_error(_reason, %Connection{} = _connection, _state), do: :ok

      defoverridable Wtransport.ConnectionHandler

      use GenServer, restart: :temporary

      # Client

      def start_link({%SessionRequest{} = request, stream_handler}) do
        GenServer.start_link(__MODULE__, {request, stream_handler})
      end

      # Server (callbacks)

      @impl true
      def init({%SessionRequest{} = request, stream_handler}) do
        Logger.debug("Wtransport.ConnectionHandler.init")

        session = struct(%Session{}, Map.from_struct(request))
        connection = struct(%Connection{session: session}, Map.from_struct(session))
        connection = struct(connection, Map.from_struct(request))

        {:ok, {connection, stream_handler, request}, {:continue, :session_request}}
      end

      @impl true
      def terminate(_reason, _state) do
        Logger.debug("Wtransport.ConnectionHandler.terminate")

        Wtransport.Runtime.pid_crashed(self())

        :ok
      end

      @impl true
      def handle_continue(
            :session_request,
            {%Connection{} = connection, stream_handler, %SessionRequest{} = request}
          ) do
        Logger.debug("Wtransport.ConnectionHandler.handle_continue :session_request")

        case handle_session(connection.session) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, stream_handler, new_state}}

          _ ->
            Logger.debug("Terminating Wtransport.ConnectionHandler")

            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, stream_handler, %{}}}
        end
      end

      @impl true
      def handle_info(
            {:connection_request, %ConnectionRequest{} = request},
            {%Connection{} = connection, stream_handler, state}
          ) do
        Logger.debug("Wtransport.ConnectionHandler.handle_info :connection_request")

        connection = struct(connection, Map.from_struct(request))

        case handle_connection(connection, state) do
          {:continue, new_state} ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, stream_handler, new_state}}

          _ ->
            Logger.debug("Terminating Wtransport.ConnectionHandler")

            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, stream_handler, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Connection{} = connection, stream_handler, state}) do
        Logger.debug("Wtransport.ConnectionHandler.handle_info :error")

        handle_error(error, connection, state)

        {:stop, :normal, {connection, stream_handler, state}}
      end

      @impl true
      def handle_info(
            {:datagram_received, dgram},
            {%Connection{} = connection, stream_handler, state}
          ) do
        Logger.debug("Wtransport.ConnectionHandler.handle_info :datagram_received")

        case handle_datagram(dgram, connection, state) do
          {:continue, new_state} ->
            {:noreply, {connection, stream_handler, new_state}}

          _ ->
            Logger.debug("Terminating Wtransport.ConnectionHandler")

            {:stop, :normal, {connection, stream_handler, state}}
        end
      end

      @impl true
      def handle_info(
            {:stream_request, %StreamRequest{} = request},
            {%Connection{} = connection, stream_handler, state}
          ) do
        Logger.debug("Wtransport.ConnectionHandler.handle_info :stream_request")

        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Wtransport.DynamicSupervisor,
            {stream_handler, {connection, request, state}}
          )

        {:noreply, {connection, stream_handler, state}}
      end

      @impl true
      def handle_info(:conn_closed, {%Connection{} = connection, stream_handler, state}) do
        Logger.debug("Wtransport.ConnectionHandler.handle_info :conn_closed")

        handle_close(connection, state)

        {:stop, :normal, {connection, stream_handler, state}}
      end
    end
  end
end
