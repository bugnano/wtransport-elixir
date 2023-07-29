defmodule WtransportEcho.SocketHandler do
  use Wtransport.SocketHandler

  alias Wtransport.Socket

  @impl Wtransport.SocketHandler
  def handle_session(%Socket{} = _socket) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_session")

    state = %{}

    {:continue, state}
  end

  @impl Wtransport.SocketHandler
  def handle_connection(%Socket{} = _socket, state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_connection")
    {:continue, state}
  end

  @impl Wtransport.SocketHandler
  def handle_datagram(dgram, %Socket{} = socket, state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_datagram")

    :ok =
      Socket.send_datagram(socket, "Reply from WtransportEcho: -- #{dgram} -- END WtransportEcho")

    {:continue, state}
  end

  @impl Wtransport.SocketHandler
  def handle_close(%Socket{} = _socket, _state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_close")
    :ok
  end

  @impl Wtransport.SocketHandler
  def handle_error(reason, %Socket{} = _socket, _state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_error")
    IO.puts(reason)

    :ok
  end
end
