defmodule Wtransport.SessionRequest do
  @enforce_keys [
    :authority,
    :path,
    :origin,
    :user_agent,
    :session_request_tx
  ]

  defstruct [
    :authority,
    :path,
    :origin,
    :user_agent,
    :session_request_tx
  ]
end
