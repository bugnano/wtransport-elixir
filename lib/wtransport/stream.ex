defmodule Wtransport.Stream do
  use TypedStruct

  alias Wtransport.Connection

  typedstruct do
    field(:stream_type, :bi | :uni, enforce: true)
    field(:connection, Connection.t(), enforce: true)
    field(:monitor_ref, reference(), enforce: true)
    field(:request_tx, reference(), enforce: true)
    field(:write_all_tx, reference(), enforce: true)
  end

  def send(%__MODULE__{write_all_tx: write_all_tx} = _stream, data)
      when not is_nil(write_all_tx) and is_binary(data) do
    case Wtransport.Native.send_data(write_all_tx, data) do
      {:ok, {}} -> :ok
      result -> result
    end
  end
end
