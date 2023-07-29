defmodule Wtransport.Connection do
  @enforce_keys [
    :connection_tx,
    :send_dgram_tx
  ]

  defstruct [
    :connection_tx,
    :send_dgram_tx
  ]
end
