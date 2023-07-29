defmodule Wtransport.StreamRequest do
  @enforce_keys [
    :stream_type,
    :stream_request_tx,
    :write_all_tx
  ]

  defstruct [
    :stream_type,
    :stream_request_tx,
    :write_all_tx
  ]
end
