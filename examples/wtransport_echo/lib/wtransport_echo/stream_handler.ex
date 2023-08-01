defmodule WtransportEcho.StreamHandler do
  use Wtransport.StreamHandler

  alias Wtransport.Stream

  @impl Wtransport.StreamHandler
  def handle_stream(%Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_stream")
    IO.inspect(stream)

    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_data(data, %Stream{} = stream, state) do
    IO.puts("[FRI] -- WtransportEcho.StreamHandler.handle_data")

    if stream.stream_type == :bi do
      :ok = Stream.send(stream, "Reply from WtransportEcho: -- #{data} -- END WtransportEcho")
    end

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
