defmodule WtransportEcho.StreamHandler do
  use Wtransport.StreamHandler

  alias Wtransport.Stream

  # StreamHandler specific callbacks

  @impl Wtransport.StreamHandler
  def handle_stream(%Stream{} = _stream, state) do
    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_data(data, %Stream{} = stream, state) do
    if stream.stream_type == :bi do
      :ok = Stream.send(stream, data)
    end

    {:continue, state}
  end

  @impl Wtransport.StreamHandler
  def handle_close(%Stream{} = stream, state) do
    case stream.stream_type do
      :bi -> {:continue, state}
      :uni -> :close
    end
  end

  @impl Wtransport.StreamHandler
  def handle_error(_reason, %Stream{} = _stream, _state) do
    :ok
  end

  # GenServer style callbacks

  @impl Wtransport.StreamHandler
  def handle_continue(_continue_arg, %Stream{} = _stream, state) do
    {:noreply, state}
  end

  @impl Wtransport.StreamHandler
  def handle_info(_msg, %Stream{} = _stream, state) do
    {:noreply, state}
  end

  @impl Wtransport.StreamHandler
  def handle_call(request, _from, %Stream{} = _stream, state) do
    {:reply, request, state}
  end

  @impl Wtransport.StreamHandler
  def handle_cast(_request, %Stream{} = _stream, state) do
    {:noreply, state}
  end
end
