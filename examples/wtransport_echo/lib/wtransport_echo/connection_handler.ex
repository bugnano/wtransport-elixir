defmodule WtransportEcho.ConnectionHandler do
  use Wtransport.ConnectionHandler

  alias Wtransport.Session
  alias Wtransport.Connection

  @impl Wtransport.ConnectionHandler
  def handle_session(%Session{} = _session) do
    IO.puts("[FRI] -- WtransportEcho.ConnectionHandler.handle_session")

    state = %{}

    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_connection(%Connection{} = _connection, state) do
    IO.puts("[FRI] -- WtransportEcho.ConnectionHandler.handle_connection")

    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_datagram(dgram, %Connection{} = connection, state) do
    IO.puts("[FRI] -- WtransportEcho.ConnectionHandler.handle_datagram")

    :ok =
      Connection.send_datagram(
        connection,
        "Reply from WtransportEcho: -- #{dgram} -- END WtransportEcho"
      )

    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_close(%Connection{} = _connection, _state) do
    IO.puts("[FRI] -- WtransportEcho.ConnectionHandler.handle_close")
    :ok
  end

  @impl Wtransport.ConnectionHandler
  def handle_error(reason, %Connection{} = _connection, _state) do
    IO.puts("[FRI] -- WtransportEcho.ConnectionHandler.handle_error")
    IO.puts(reason)

    :ok
  end
end
