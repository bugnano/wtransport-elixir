defmodule WtransportEcho.StreamHandler do
  alias Wtransport.Stream

  use Wtransport.StreamHandler

  @impl Wtransport.StreamHandler
  def handle_stream(%Stream{} = _stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_stream")
    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_data(data, %Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_data")

    :ok = Stream.send(stream, "Reply from WtransportEcho: -- #{data} -- END WtransportEcho")

    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_close(%Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_close")

    case stream.stream_type do
      :bi -> {:continue, state}
      :uni -> :close
    end
  end

  @impl Wtransport.StreamHandler
  def handle_error(reason, %Stream{} = _stream, _state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_error")
    IO.puts(reason)

    :ok
  end
end
