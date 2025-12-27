defmodule Wtransport.Native do
  use Rustler, otp_app: :wtransport, crate: "wtransport_native"

  # When your NIF is loaded, it will override this function.
  def start_runtime(_pid, _host, _port, _cert_chain, _priv_key, _log_network_data), do: error()
  def stop_runtime(_runtime), do: error()
  def reply_request(_tx_channel, _result, _pid), do: error()
  def send_data(_tx_channel, _data, _log_network_data), do: error()

  defp error(), do: :erlang.nif_error(:nif_not_loaded)
end
