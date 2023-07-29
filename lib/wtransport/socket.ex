defmodule Wtransport.Socket do
  defstruct [
    :authority,
    :path,
    :origin,
    :user_agent,
    :stable_id,
    :send_dgram_tx
  ]

  def send_datagram(%__MODULE__{send_dgram_tx: send_dgram_tx} = _socket, dgram)
      when not is_nil(send_dgram_tx) and is_binary(dgram) do
    {:ok, {}} = Wtransport.Native.send_data(send_dgram_tx, dgram)

    :ok
  end
end
