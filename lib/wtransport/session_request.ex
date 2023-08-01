defmodule Wtransport.SessionRequest do
  @enforce_keys [
    :authority,
    :path,
    :origin,
    :user_agent,
    :headers,
    :request_tx
  ]

  defstruct [
    :authority,
    :path,
    :origin,
    :user_agent,
    :headers,
    :request_tx
  ]
end
