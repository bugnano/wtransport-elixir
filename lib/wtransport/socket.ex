defmodule Wtransport.Socket do
  @enforce_keys [:authority, :path, :session_request_tx, :send_dgram_tx]
  defstruct [:authority, :path, :session_request_tx, :send_dgram_tx]

  def send_datagram(%__MODULE__{} = socket, dgram) when is_binary(dgram) do
    {:ok, {}} = Wtransport.Native.send_datagram(socket, dgram)

    :ok
  end
end
