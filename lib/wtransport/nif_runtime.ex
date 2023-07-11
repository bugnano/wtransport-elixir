defmodule Wtransport.NifRuntime do
  @enforce_keys [:rt, :shutdown_tx]
  defstruct [:rt, :shutdown_tx]
end
