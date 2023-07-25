defmodule WtransportEcho.SocketHandler do
  use Wtransport.SocketHandler

  alias Wtransport.Socket

  @impl Wtransport.SocketHandler
  def handle_connection(%Socket{} = _socket, state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_connection")
    {:continue, state}
  end

  @impl Wtransport.SocketHandler
  def handle_datagram(dgram, %Socket{} = socket, state) do
    IO.puts("[FRI] -- WtransportEcho.SocketHandler.handle_datagram")

    :ok = Socket.send_datagram(socket, "Reply from WtransportEcho: -- #{dgram} -- END WtransportEcho")

    {:continue, state}
  end
end
