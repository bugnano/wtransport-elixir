defmodule Wtransport.Native do
  use Rustler, otp_app: :wtransport, crate: "wtransport_native"

  # When your NIF is loaded, it will override this function.
  def start_runtime(_pid, _host, _port, _cert_chain, _priv_key), do: error()
  def stop_runtime(_runtime), do: error()

  defp error(), do: :erlang.nif_error(:nif_not_loaded)
end
