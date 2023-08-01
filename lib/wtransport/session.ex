defmodule Wtransport.Session do
  defstruct [
    :authority,
    :path,
    :origin,
    :user_agent,
    :headers
  ]
end
