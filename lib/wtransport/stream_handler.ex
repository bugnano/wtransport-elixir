defmodule Wtransport.StreamHandler do
  alias Wtransport.Connection
  alias Wtransport.StreamRequest
  alias Wtransport.Stream

  @callback handle_stream(stream :: Stream.t(), state :: term()) :: {:continue, term()} | :close

  @callback handle_data(data :: String.t(), stream :: Stream.t(), state :: term()) ::
              {:continue, term()} | :close

  @callback handle_close(stream :: Stream.t(), state :: term()) :: :ok

  @callback handle_error(reason :: String.t(), stream :: Stream.t(), state :: term()) :: :ok

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Wtransport.StreamHandler

      @impl Wtransport.StreamHandler
      def handle_stream(%Stream{} = _stream, state), do: {:continue, state}

      @impl Wtransport.StreamHandler
      def handle_data(_data, %Stream{} = _stream, state),
        do: {:continue, state}

      @impl Wtransport.StreamHandler
      def handle_close(%Stream{} = _stream, _state), do: :close

      @impl Wtransport.StreamHandler
      def handle_error(_reason, %Stream{} = _stream, _state), do: :ok

      defoverridable Wtransport.StreamHandler

      use GenServer, restart: :temporary

      require Logger

      # Client

      def start_link({%Connection{} = connection, %StreamRequest{} = request, state, conn_pid}) do
        GenServer.start_link(__MODULE__, {connection, request, state, conn_pid})
      end

      # Server (callbacks)

      @impl true
      def init({%Connection{} = connection, %StreamRequest{} = request, state, conn_pid}) do
        Logger.debug("init")

        monitor_ref = Process.monitor(conn_pid)

        stream =
          struct(
            Stream,
            %{connection: connection, monitor_ref: monitor_ref}
            |> Map.merge(Map.from_struct(request))
          )

        {:ok, {stream, state}, {:continue, :wtransport_stream_request}}
      end

      @impl true
      def terminate(_reason, {%Stream{} = stream, _state}) do
        if stream.request_tx != nil do
          Logger.debug("terminate")

          Wtransport.Native.reply_request(stream.request_tx, :pid_crashed, self())
        end

        :ok
      end

      @impl true
      def handle_continue(:wtransport_stream_request, {%Stream{} = stream, state}) do
        Logger.debug(":wtransport_stream_request")

        case handle_stream(stream, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(stream.request_tx, :ok, self())

            {:noreply, {stream, new_state}}

          _ ->
            {:ok, {}} = Wtransport.Native.reply_request(stream.request_tx, :error, self())

            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_info(
            {:DOWN, ref, :process, _object, _reason},
            {%Stream{monitor_ref: monitor_ref} = stream, state}
          )
          when ref == monitor_ref do
        Logger.debug(":DOWN")

        handle_error("pid_crashed", stream, state)

        {:stop, :normal, {stream, state}}
      end

      @impl true
      def handle_info({:wtransport_error, error}, {%Stream{} = stream, state}) do
        Logger.debug(":wtransport_error")

        handle_error(error, stream, state)

        {:stop, :normal, {stream, state}}
      end

      @impl true
      def handle_info({:wtransport_data_received, data}, {%Stream{} = stream, state}) do
        Logger.debug(":wtransport_data_received")

        case handle_data(data, stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_info(:wtransport_stream_closed, {%Stream{} = stream, state}) do
        Logger.debug(":wtransport_stream_closed")

        case handle_close(stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            {:stop, :normal, {stream, state}}
        end
      end
    end
  end
end
