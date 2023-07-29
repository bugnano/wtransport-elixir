defmodule Wtransport.Stream do
  @enforce_keys [
    :stream_type,
    :accept_stream_tx
  ]

  defstruct [
    :stream_type,
    :accept_stream_tx,
    :write_all_tx
  ]

  def send(%__MODULE__{write_all_tx: write_all_tx} = _stream, data)
      when not is_nil(write_all_tx) and is_binary(data) do
    case Wtransport.Native.send_data(write_all_tx, data) do
      {:ok, {}} -> :ok
      result -> result
    end
  end
end
