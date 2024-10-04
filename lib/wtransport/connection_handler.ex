defmodule Wtransport.ConnectionHandler do
  alias Wtransport.SessionRequest
  alias Wtransport.Session
  alias Wtransport.ConnectionRequest
  alias Wtransport.Connection
  alias Wtransport.StreamRequest
  alias Wtransport.Runtime

  @callback handle_session(session :: Session.t()) :: {:continue, term()} | :close

  @callback handle_connection(connection :: Connection.t(), state :: term()) ::
              {:continue, term()} | :close

  @callback handle_datagram(dgram :: String.t(), connection :: Connection.t(), state :: term()) ::
              {:continue, term()} | :close

  @callback handle_close(connection :: Connection.t(), state :: term()) :: :ok

  @callback handle_error(reason :: String.t(), connection :: Connection.t(), state :: term()) ::
              :ok

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Wtransport.ConnectionHandler

      @impl Wtransport.ConnectionHandler
      def handle_session(%Session{} = _session), do: {:continue, %{}}

      @impl Wtransport.ConnectionHandler
      def handle_connection(%Connection{} = _connection, state), do: {:continue, state}

      @impl Wtransport.ConnectionHandler
      def handle_datagram(_dgram, %Connection{} = _connection, state), do: {:continue, state}

      @impl Wtransport.ConnectionHandler
      def handle_close(%Connection{} = _connection, _state), do: :ok

      @impl Wtransport.ConnectionHandler
      def handle_error(_reason, %Connection{} = _connection, _state), do: :ok

      defoverridable Wtransport.ConnectionHandler

      use GenServer, restart: :temporary

      require Logger

      # Client

      def start_link({%SessionRequest{} = request, %Runtime.State{} = runtime_state}) do
        GenServer.start_link(__MODULE__, {request, runtime_state})
      end

      # Server (callbacks)

      @impl true
      def init({%SessionRequest{} = request, %Runtime.State{} = runtime_state}) do
        Logger.debug("init")

        session = struct(Session, Map.from_struct(request))

        connection =
          struct(
            Connection,
            %{session: session}
            |> Map.merge(Map.from_struct(session))
            |> Map.merge(Map.from_struct(request))
            |> Map.merge(Map.from_struct(runtime_state))
          )

        {:ok, {connection, %{}}, {:continue, :wtransport_session_request}}
      end

      @impl true
      def terminate(_reason, {%Connection{} = connection, _state}) do
        if connection.request_tx != nil do
          Logger.debug("terminate")

          Wtransport.Native.reply_request(connection.request_tx, :pid_crashed, self())
        end

        :ok
      end

      @impl true
      def handle_continue(:wtransport_session_request, {%Connection{} = connection, state}) do
        Logger.debug(":wtransport_session_request")

        case handle_session(connection.session) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, new_state}}

          _ ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, state}}
        end
      end

      @impl true
      def handle_info(
            {:wtransport_connection_request, %ConnectionRequest{} = request},
            {%Connection{} = connection, state}
          ) do
        Logger.debug(":wtransport_connection_request")

        connection = struct(connection, Map.from_struct(request))

        case handle_connection(connection, state) do
          {:continue, new_state} ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, new_state}}

          _ ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, state}}
        end
      end

      @impl true
      def handle_info({:wtransport_error, error}, {%Connection{} = connection, state}) do
        Logger.debug(":wtransport_error")

        handle_error(error, connection, state)

        {:stop, :normal, {connection, state}}
      end

      @impl true
      def handle_info({:wtransport_datagram_received, dgram}, {%Connection{} = connection, state}) do
        Logger.debug(":wtransport_datagram_received")

        case handle_datagram(dgram, connection, state) do
          {:continue, new_state} ->
            {:noreply, {connection, new_state}}

          _ ->
            {:stop, :normal, {connection, state}}
        end
      end

      @impl true
      def handle_info(
            {:wtransport_stream_request, %StreamRequest{} = request},
            {%Connection{} = connection, state}
          ) do
        Logger.debug(":wtransport_stream_request")

        if connection.stream_handler != nil do
          {:ok, _pid} =
            DynamicSupervisor.start_child(
              connection.supervisor_pid,
              {connection.stream_handler, {connection, request, state, self()}}
            )
        else
          {:ok, {}} = Wtransport.Native.reply_request(request.request_tx, :error, self())
        end

        {:noreply, {connection, state}}
      end

      @impl true
      def handle_info(:wtransport_conn_closed, {%Connection{} = connection, state}) do
        Logger.debug(":wtransport_conn_closed")

        handle_close(connection, state)

        {:stop, :normal, {connection, state}}
      end
    end
  end
end
