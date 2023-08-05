defmodule WtransportEcho.ConnectionHandler do
  use Wtransport.ConnectionHandler

  alias Wtransport.Session
  alias Wtransport.Connection

  # ConnectionHandler specific callbacks

  @impl Wtransport.ConnectionHandler
  def handle_session(%Session{} = _session) do
    state = %{}

    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_connection(%Connection{} = _connection, state) do
    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_datagram(dgram, %Connection{} = connection, state) do
    :ok = Connection.send_datagram(connection, dgram)

    {:continue, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_close(%Connection{} = _connection, _state) do
    :ok
  end

  @impl Wtransport.ConnectionHandler
  def handle_error(_reason, %Connection{} = _connection, _state) do
    :ok
  end

  # GenServer style callbacks

  @impl Wtransport.ConnectionHandler
  def handle_continue(_continue_arg, %Connection{} = _connection, state) do
    {:noreply, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_info(_msg, %Connection{} = _connection, state) do
    {:noreply, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_call(request, _from, %Connection{} = _connection, state) do
    {:reply, request, state}
  end

  @impl Wtransport.ConnectionHandler
  def handle_cast(_request, %Connection{} = _connection, state) do
    {:noreply, state}
  end
end
