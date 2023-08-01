defmodule Wtransport do
  defmodule SessionRequest do
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

  defmodule Session do
    defstruct [
      :authority,
      :path,
      :origin,
      :user_agent,
      :headers
    ]
  end

  defmodule ConnectionRequest do
    @enforce_keys [
      :stable_id,
      :send_dgram_tx
    ]

    defstruct [
      :stable_id,
      :send_dgram_tx
    ]
  end

  defmodule StreamRequest do
    @enforce_keys [
      :stream_type,
      :request_tx,
      :write_all_tx
    ]

    defstruct [
      :stream_type,
      :request_tx,
      :write_all_tx
    ]
  end
end
