defmodule WtransportEcho.StreamHandler do
  alias Wtransport.Socket
  alias Wtransport.Stream

  use Wtransport.StreamHandler

  @impl Wtransport.StreamHandler
  def handle_stream(%Socket{} = _socket, %Stream{} = _stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_stream")
    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_data(data, %Socket{} = _socket, %Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_data")

    :ok = Stream.send(stream, "Reply from WtransportEcho: -- #{data} -- END WtransportEcho")

    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_close(%Socket{} = _socket, %Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_close")

    case stream.stream_type do
      :bi -> {:continue, state}
      :uni -> :close
    end
  end

  @impl Wtransport.StreamHandler
  def handle_error(reason, %Socket{} = _socket, %Stream{} = _stream, _state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_error")
    IO.puts(reason)

    :ok
  end
end
