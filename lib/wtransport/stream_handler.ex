defmodule Wtransport.StreamHandler do
  alias Wtransport.Socket
  alias Wtransport.Stream
  alias Wtransport.StreamRequest

  @callback handle_stream(stream :: Stream.t(), state :: term()) :: term()

  @callback handle_data(
              data :: String.t(),
              stream :: Stream.t(),
              state :: term()
            ) :: term()

  @callback handle_close(stream :: Stream.t(), state :: term()) :: term()

  @callback handle_error(
              reason :: String.t(),
              stream :: Stream.t(),
              state :: term()
            ) :: term()

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Wtransport.StreamHandler

      # Default behaviour

      def handle_stream(%Stream{} = _stream, state), do: {:continue, state}

      def handle_data(_data, %Stream{} = _stream, state),
        do: {:continue, state}

      def handle_close(%Stream{} = _stream, _state), do: :close

      def handle_error(_reason, %Stream{} = _stream, _state), do: :ok

      defoverridable Wtransport.StreamHandler

      use GenServer, restart: :temporary

      # Client

      def start_link({%Socket{} = socket, %StreamRequest{} = request, state}) do
        GenServer.start_link(__MODULE__, {socket, request, state})
      end

      # Server (callbacks)

      @impl true
      def init({%Socket{} = socket, %StreamRequest{} = request, state}) do
        IO.puts("[FRI] -- Wtransport.StreamHandler.init")

        stream = struct(%Stream{socket: socket}, Map.from_struct(request))
        IO.inspect(stream)

        {:ok, {stream, state, request}, {:continue, :stream_request}}
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
      def handle_continue(
            :stream_request,
            {%Stream{} = stream, state, %StreamRequest{} = request}
          ) do
        IO.puts("[FRI] -- Wtransport.StreamHandler.handle_continue :stream_request")

        case handle_stream(stream, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(request.stream_request_tx, :ok, self())

            {:noreply, {stream, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

            {:ok, {}} = Wtransport.Native.reply_request(request.stream_request_tx, :error, self())

            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Stream{} = stream, state}) do
        IO.puts("[FRI] -- Wtransport.StreamHandler.handle_info :error")
        IO.inspect(error)

        handle_error(error, stream, state)

        {:stop, :normal, {stream, state}}
      end

      @impl true
      def handle_info({:data_received, data}, {%Stream{} = stream, state}) do
        IO.puts("[FRI] -- Wtransport.StreamHandler.handle_info :data_received")

        case handle_data(data, stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

            {:stop, :normal, {stream, state}}
        end
      end

      @impl true

      def handle_info(:stream_closed, {%Stream{} = stream, state}) do
        IO.puts("[FRI] -- Wtransport.StreamHandler.handle_info :stream_closed")

        case handle_close(stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.StreamHandler")

            {:stop, :normal, {stream, state}}
        end
      end
    end
  end
end
