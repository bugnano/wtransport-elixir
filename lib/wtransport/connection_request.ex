defmodule Wtransport.ConnectionRequest do
  @enforce_keys [
    :connection_request_tx,
    :send_dgram_tx
  ]

  defstruct [
    :connection_request_tx,
    :send_dgram_tx
  ]
end
