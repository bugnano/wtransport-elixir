defmodule Wtransport.SessionRequest do
  @enforce_keys [:authority, :path, :channel]
  defstruct [:authority, :path, :channel]
end
