defmodule Wtransport.SocketHandler do
  alias Wtransport.Socket
  alias Wtransport.Stream

  @callback handle_connection(socket :: Wtransport.Socket.t(), state :: term()) :: term()

  @callback handle_datagram(dgram :: String.t(), socket :: Wtransport.Socket.t(), state :: term()) ::
              term()

  defmacro __using__(_opts) do
    quote do
      @behaviour Wtransport.SocketHandler

      # Default behaviour

      def handle_connection(%Socket{} = _socket, state), do: {:continue, state}
      def handle_datagram(_dgram, %Socket{} = _socket, state), do: {:continue, state}

      defoverridable Wtransport.SocketHandler

      use GenServer, restart: :temporary

      # Client

      def start_link(%Socket{} = socket) do
        GenServer.start_link(__MODULE__, socket)
      end

      # Server (callbacks)

      @impl true
      def init(%Socket{} = socket) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.init")
        IO.inspect(socket)

        state = %{}

        {:ok, {socket, state}, {:continue, :session_request}}
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
      def handle_continue(:session_request, {%Socket{} = socket, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_continue :session_request")

        case handle_connection(socket, state) do
          {:continue, new_state} ->
            {:ok, {}} = Wtransport.Native.reply_session_request(socket, :ok, self())

            {:noreply, {socket, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:ok, {}} = Wtransport.Native.reply_session_request(socket, :error, self())

            {:stop, :normal, {socket, state}}
        end
      end

      @impl true
      def handle_info({:error, error}, {%Socket{} = socket, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :error")
        IO.inspect(error)

        {:stop, :normal, {socket, state}}
      end

      @impl true
      def handle_info({:datagram_received, dgram}, {%Socket{} = socket, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :datagram_received")

        case handle_datagram(dgram, socket, state) do
          {:continue, new_state} ->
            {:noreply, {socket, new_state}}

          _ ->
            IO.puts("[FRI] -- Terminating Wtransport.SocketHandler")

            {:stop, :normal, {socket, state}}
        end

        {:noreply, {socket, state}}
      end

      @impl true
      def handle_info({:accept_stream, %Stream{} = stream}, {%Socket{} = socket, state}) do
        IO.puts("[FRI] -- Wtransport.SocketHandler.handle_info :accept_stream")

        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Wtransport.DynamicSupervisor,
            {Wtransport.StreamHandler, {socket, stream}}
          )

        {:noreply, {socket, state}}
      end
    end
  end
end
