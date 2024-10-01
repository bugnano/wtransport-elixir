defmodule Wtransport.Connection do
  use TypedStruct

  alias Wtransport.Session

  typedstruct do
    field(:session, Session.t(), enforce: true)
    field(:stable_id, non_neg_integer(), enforce: true)
    field(:stream_handler, atom())
    field(:supervisor_pid, pid(), enforce: true)
    field(:request_tx, reference(), enforce: true)
    field(:send_dgram_tx, reference(), enforce: true)
  end

  def send_datagram(%__MODULE__{send_dgram_tx: send_dgram_tx} = _connection, dgram)
      when not is_nil(send_dgram_tx) and is_binary(dgram) do
    {:ok, {}} = Wtransport.Native.send_data(send_dgram_tx, dgram)

    :ok
  end

  def remote_address(%__MODULE__{request_tx: request_tx} = _connection)
      when not is_nil(request_tx) do
    {:ok, {}} = Wtransport.Native.reply_request(request_tx, :remote_address, self())

    receive do
      {:remote_address, host, port} when is_binary(host) and is_integer(port) ->
        %{host: host, port: port}
    end
  end

  def max_datagram_size(%__MODULE__{request_tx: request_tx} = _connection)
      when not is_nil(request_tx) do
    {:ok, {}} = Wtransport.Native.reply_request(request_tx, :max_datagram_size, self())

    receive do
      {:max_datagram_size, max_datagram_size} when is_integer(max_datagram_size) ->
        max_datagram_size
    end
  end

  def rtt(%__MODULE__{request_tx: request_tx} = _connection)
      when not is_nil(request_tx) do
    {:ok, {}} = Wtransport.Native.reply_request(request_tx, :rtt, self())

    receive do
      {:rtt, rtt} when is_float(rtt) ->
        # Rust returns the time in seconds, but it's easier to reason in milliseconds
        rtt * 1000
    end
  end
end
