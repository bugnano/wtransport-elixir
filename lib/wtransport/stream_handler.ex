defmodule Wtransport.StreamHandler do
  alias Wtransport.Connection
  alias Wtransport.StreamRequest
  alias Wtransport.Stream

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

  @callback handle_continue(continue_arg :: term(), stream :: Stream.t(), state :: term()) ::
              term()

  @callback handle_info(msg :: term(), stream :: Stream.t(), state :: term()) :: term()

  @callback handle_call(
              request :: term(),
              from :: term(),
              stream :: Stream.t(),
              state :: term()
            ) :: term()

  @callback handle_cast(request :: term(), stream :: Stream.t(), state :: term()) ::
              term()

  defmacro __using__(_opts) do
    quote location: :keep do
      require Logger

      @behaviour Wtransport.StreamHandler

      # Default behaviour

      @impl Wtransport.StreamHandler
      def handle_stream(%Stream{} = _stream, state), do: {:continue, state}

      @impl Wtransport.StreamHandler
      def handle_data(_data, %Stream{} = _stream, state),
        do: {:continue, state}

      @impl Wtransport.StreamHandler
      def handle_close(%Stream{} = _stream, _state), do: :close

      @impl Wtransport.StreamHandler
      def handle_error(_reason, %Stream{} = _stream, _state), do: :ok

      @impl Wtransport.StreamHandler
      def handle_continue(_continue_arg, %Stream{} = _stream, _state),
        do: raise("handle_continue/3 not implemented")

      @impl Wtransport.StreamHandler
      def handle_info(_msg, %Stream{} = _stream, _state),
        do: raise("handle_info/3 not implemented")

      @impl Wtransport.StreamHandler
      def handle_call(_request, _from, %Stream{} = _stream, _state),
        do: raise("handle_call/4 not implemented")

      @impl Wtransport.StreamHandler
      def handle_cast(_request, %Stream{} = _stream, _state),
        do: raise("handle_cast/3 not implemented")

      defoverridable Wtransport.StreamHandler

      use GenServer, restart: :temporary

      # Client

      def start_link({%Connection{} = connection, %StreamRequest{} = request, state, conn_pid}) do
        GenServer.start_link(__MODULE__, {connection, request, state, conn_pid})
      end

      # Server (callbacks)

      @impl true
      def init({%Connection{} = connection, %StreamRequest{} = request, state, conn_pid}) do
        Logger.debug("init")

        Process.monitor(conn_pid)

        stream = struct(%Stream{connection: connection}, Map.from_struct(request))

        {:ok, {stream, {request, state}}, {:continue, :stream_request}}
      end

      @impl true
      def terminate(_reason, {%Stream{} = stream, _state}) do
        if stream.request_tx != nil do
          Logger.debug("terminate (1)")

          Wtransport.Native.reply_request(stream.request_tx, :pid_crashed, self())
        else
          Logger.debug("terminate (2)")

          Wtransport.Runtime.pid_crashed(self())
        end

        :ok
      end

      @impl true
      def terminate(_reason, _state) do
        Logger.debug("terminate (3)")

        Wtransport.Runtime.pid_crashed(self())

        :ok
      end

      @impl true
      def handle_continue(
            :stream_request,
            {%Stream{} = stream, {%StreamRequest{} = request, state}}
          ) do
        Logger.debug(":stream_request")

        case handle_stream(stream, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_request(request.request_tx, :ok, self())

            {:noreply, {stream, new_state}}

          _ ->
            {:ok, {}} = Wtransport.Native.reply_request(request.request_tx, :error, self())

            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_continue(continue_arg, {%Stream{} = stream, state}) do
        case handle_continue(continue_arg, stream, state) do
          {:noreply, new_state} ->
            {:noreply, {stream, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {stream, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {stream, new_state}}
        end
      end

      @impl true
      def handle_info({:DOWN, _ref, :process, _object, _reason}, {%Stream{} = stream, state}) do
        Logger.debug(":DOWN")

        handle_error("pid_crashed", stream, state)

        {:stop, :normal, {stream, state}}
      end

      @impl true
      def handle_info({:error, error}, {%Stream{} = stream, state}) do
        Logger.debug(":error")

        handle_error(error, stream, state)

        {:stop, :normal, {stream, state}}
      end

      @impl true
      def handle_info({:data_received, data}, {%Stream{} = stream, state}) do
        Logger.debug(":data_received")

        case handle_data(data, stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_info(:stream_closed, {%Stream{} = stream, state}) do
        Logger.debug(":stream_closed")

        case handle_close(stream, state) do
          {:continue, new_state} ->
            {:noreply, {stream, new_state}}

          _ ->
            {:stop, :normal, {stream, state}}
        end
      end

      @impl true
      def handle_info(msg, {%Stream{} = stream, state}) do
        case handle_info(msg, stream, state) do
          {:noreply, new_state} ->
            {:noreply, {stream, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {stream, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {stream, new_state}}
        end
      end

      @impl true
      def handle_call(request, from, {%Stream{} = stream, state}) do
        case handle_call(request, from, stream, state) do
          {:reply, reply, new_state} ->
            {:reply, reply, {stream, new_state}}

          {:reply, reply, new_state, arg} ->
            {:reply, reply, {stream, new_state}, arg}

          {:noreply, new_state} ->
            {:noreply, {stream, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {stream, new_state}, arg}

          {:stop, reason, reply, new_state} ->
            {:stop, reason, reply, {stream, new_state}}

          {:stop, reason, new_state} ->
            {:stop, reason, {stream, new_state}}
        end
      end

      @impl true
      def handle_cast(request, {%Stream{} = stream, state}) do
        case handle_cast(request, stream, state) do
          {:noreply, new_state} ->
            {:noreply, {stream, new_state}}

          {:noreply, new_state, arg} ->
            {:noreply, {stream, new_state}, arg}

          {:stop, reason, new_state} ->
            {:stop, reason, {stream, new_state}}
        end
      end
    end
  end
end
