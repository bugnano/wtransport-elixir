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

  @callback handle_continue(continue_arg :: term(), connection :: Connection.t(), state :: term()) ::
              term()

  @callback handle_info(msg :: term(), connection :: Connection.t(), state :: term()) :: term()

  @callback handle_call(
              request :: term(),
              from :: term(),
              connection :: Connection.t(),
              state :: term()
            ) :: term()

  @callback handle_cast(request :: term(), connection :: Connection.t(), state :: term()) ::
              term()

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Wtransport.ConnectionHandler

      # Default behaviour

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

      @impl Wtransport.ConnectionHandler
      def handle_continue(_continue_arg, %Connection{} = _connection, _state),
        do: raise("handle_continue/3 not implemented")

      @impl Wtransport.ConnectionHandler
      def handle_info(_msg, %Connection{} = _connection, _state),
        do: raise("handle_info/3 not implemented")

      @impl Wtransport.ConnectionHandler
      def handle_call(_request, _from, %Connection{} = _connection, _state),
        do: raise("handle_call/4 not implemented")

      @impl Wtransport.ConnectionHandler
      def handle_cast(_request, %Connection{} = _connection, _state),
        do: raise("handle_cast/3 not implemented")

      defoverridable Wtransport.ConnectionHandler

      use GenServer, restart: :temporary

      require Logger

      # Client

      def start_link({%SessionRequest{} = request, runtime_state}) do
        GenServer.start_link(__MODULE__, {request, runtime_state})
      end

      # Server (callbacks)

      @impl true
      def init({%SessionRequest{} = request, runtime_state}) do
        Logger.debug("init")

        session = struct(%Session{}, Map.from_struct(request))
        connection = struct(%Connection{session: session}, Map.from_struct(session))
        connection = struct(connection, Map.from_struct(request))

        {:ok, {connection, runtime_state, request}, {:continue, :session_request}}
      end

      @impl true
      def terminate(_reason, {%Connection{} = connection, _runtime_state, _state}) do
        if connection.request_tx != nil do
          Logger.debug("terminate")

          Wtransport.Native.reply_request(connection.request_tx, :pid_crashed, self())
        end

        :ok
      end

      @impl true
      def handle_continue(
            :session_request,
            {%Connection{} = connection, runtime_state, %SessionRequest{} = request}
          ) do
        Logger.debug(":session_request")

        case handle_session(connection.session) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, runtime_state, new_state}}

          _ ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, runtime_state, %{}}}
        end
      end

      @impl true
      def handle_continue(continue_arg, {%Connection{} = connection, runtime_state, state}) do
        case handle_continue(continue_arg, connection, state) do
          {:noreply, new_state} ->
            {:noreply, {connection, runtime_state, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {connection, runtime_state, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {connection, runtime_state, new_state}}
        end
      end

      @impl true
      def handle_info(
            {:connection_request, %ConnectionRequest{} = request},
            {%Connection{} = connection, runtime_state, state}
          ) do
        Logger.debug(":connection_request")

        connection = struct(connection, Map.from_struct(request))

        case handle_connection(connection, state) do
          {:continue, new_state} ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :ok, self())

            {:noreply, {connection, runtime_state, new_state}}

          _ ->
            {:ok, {}} =
              Wtransport.Native.reply_request(connection.request_tx, :error, self())

            {:stop, :normal, {connection, runtime_state, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Connection{} = connection, runtime_state, state}) do
        Logger.debug(":error")

        handle_error(error, connection, state)

        {:stop, :normal, {connection, runtime_state, state}}
      end

      @impl true
      def handle_info(
            {:datagram_received, dgram},
            {%Connection{} = connection, runtime_state, state}
          ) do
        Logger.debug(":datagram_received")

        case handle_datagram(dgram, connection, state) do
          {:continue, new_state} ->
            {:noreply, {connection, runtime_state, new_state}}

          _ ->
            {:stop, :normal, {connection, runtime_state, state}}
        end
      end

      @impl true
      def handle_info(
            {:stream_request, %StreamRequest{} = request},
            {%Connection{} = connection, runtime_state, state}
          ) do
        Logger.debug(":stream_request")

        if runtime_state.stream_handler != nil do
          {:ok, _pid} =
            DynamicSupervisor.start_child(
              runtime_state.supervisor_pid,
              {runtime_state.stream_handler, {connection, request, state, self()}}
            )
        else
          {:ok, {}} = Wtransport.Native.reply_request(request.request_tx, :error, self())
        end

        {:noreply, {connection, runtime_state, state}}
      end

      @impl true
      def handle_info(:conn_closed, {%Connection{} = connection, runtime_state, state}) do
        Logger.debug(":conn_closed")

        handle_close(connection, state)

        {:stop, :normal, {connection, runtime_state, state}}
      end

      @impl true
      def handle_info(msg, {%Connection{} = connection, runtime_state, state}) do
        case handle_info(msg, connection, state) do
          {:noreply, new_state} ->
            {:noreply, {connection, runtime_state, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {connection, runtime_state, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {connection, runtime_state, new_state}}
        end
      end

      @impl true
      def handle_call(request, from, {%Connection{} = connection, runtime_state, state}) do
        case handle_call(request, from, connection, state) do
          {:reply, reply, new_state} ->
            {:reply, reply, {connection, runtime_state, new_state}}

          {:reply, reply, new_state, arg} ->
            {:reply, reply, {connection, runtime_state, new_state}, arg}

          {:noreply, new_state} ->
            {:noreply, {connection, runtime_state, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {connection, runtime_state, new_state}, arg}

          {:stop, reason, reply, new_state} ->
            {:stop, reason, reply, {connection, runtime_state, new_state}}

          {:stop, reason, new_state} ->
            {:stop, reason, {connection, runtime_state, new_state}}
        end
      end

      @impl true
      def handle_cast(request, {%Connection{} = connection, runtime_state, state}) do
        case handle_cast(request, connection, state) do
          {:noreply, new_state} ->
            {:noreply, {connection, runtime_state, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {connection, runtime_state, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {connection, runtime_state, new_state}}
        end
      end
    end
  end
end
