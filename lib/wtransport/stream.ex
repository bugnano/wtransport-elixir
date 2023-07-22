defmodule Wtransport.Stream do
  @enforce_keys [:stream_type, :accept_stream_tx]
  defstruct [:stream_type, :accept_stream_tx, :write_all_tx]

  def send(%__MODULE__{} = stream, data) when is_binary(data) do
    case Wtransport.Native.write_all(stream, data) do
      {:ok, {}} -> :ok
      result -> result
    end
  end
end
