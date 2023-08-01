defmodule Wtransport.ConnectionRequest do
  @enforce_keys [
    :stable_id,
    :send_dgram_tx
  ]

  defstruct [
    :stable_id,
    :send_dgram_tx
  ]
end
