# Wtransport

Elixir bindings for the [WTransport](https://github.com/BiagioFesta/wtransport) WebTransport library.

## About WebTransport

WebTransport is a web API that uses the HTTP/3 protocol as a bidirectional transport.
It's intended for two-way communications between a web client and an HTTP/3 server.
It supports sending data both unreliably via its datagram APIs, and reliably via its streams APIs.

## About WTransport

[WTransport](https://github.com/BiagioFesta/wtransport) is a pure-rust implementation of the WebTransport protocol.

The Wtransport Elixir bindings implement the server part of WTransport with an API heavily inspired by
[Thousand Island](https://github.com/mtrudel/thousand_island).

## Prerequisites

- The Rust compiler (WTransport is written in Rust)
- The Clang C compiler + CMake (WTransport depends on [ls-qpack](https://github.com/litespeedtech/ls-qpack), which is written in C)

You'll also need TLS certificate files, even for local development, as HTTP/3 mandates the use of TLS.
A tool like [mkcert](https://github.com/FiloSottile/mkcert) can be handy for generating certificate files suitable for local development.

## Installation

The package can be installed by adding `wtransport` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wtransport, git: "https://github.com/bugnano/wtransport-elixir.git"}
  ]
end
```

## Usage

Wtransport is implemented as a supervision tree which is intended to be hosted inside a host application.

Example:

```elixir
def start(_type, _args) do
  wtransport_options = [
    host: "localhost",
    port: 4433,
    certfile: "cert.pem",
    keyfile: "key.pem",
    connection_handler: MyApp.ConnectionHandler,
    stream_handler: MyApp.StreamHandler
  ]

  children = [
    {Wtransport.Supervisor, wtransport_options}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Aside from supervising the WTransport process tree,
applications interact with WTransport primarily via the
`Wtransport.ConnectionHandler` and `Wtransport.StreamHandler` behaviours.

Note that you have to pass the name of the modules of your application that implement the
`Wtransport.ConnectionHandler` and `Wtransport.StreamHandler` behaviours, as options
to the `Wtransport.Supervisor`.

### ConnectionHandler

The `WTransport.ConnectionHandler` behaviour defines the interface that Wtransport uses to pass `Wtransport.Connection`s up to the application level;
it is used to handle:

- Session requests (via the `handle_session` callback)
- Connection requests (via the `handle_connection` callback)
- Unreliable, unordered datagrams (via the `handle_datagram` callback)

A simple implementation for a `Wtransport.ConnectionHandler` would look like this:

```elixir
defmodule MyApp.ConnectionHandler do
  use Wtransport.ConnectionHandler

  @impl Wtransport.ConnectionHandler
  def handle_datagram(dgram, %Wtransport.Connection{} = connection, state) do
    :ok = Connection.send_datagram(connection, dgram)

    {:continue, state}
  end
end
```

### StreamHandler

The `WTransport.StreamHandler` behaviour defines the interface that Wtransport uses to pass `Wtransport.Stream`s up to the application level;
it is used to handle:

- Stream requests (via the `handle_stream` callback)
- Reliable, ordered data (via the `handle_data` callback)

A simple implementation for a `Wtransport.StreamHandler` would look like this:

```elixir
defmodule MyApp.StreamHandler do
  use Wtransport.StreamHandler

  @impl Wtransport.StreamHandler
  def handle_data(data, %Wtransport.Stream{} = stream, state) do
    if stream.stream_type == :bi do
      :ok = Stream.send(stream, data)
    end

    {:continue, state}
  end
end
```

## Example application

Wtransport comes with a simple echo server to serve as an example;
it can be found in the `examples/wtransport_echo` folder of this project.

## License

MPL-2.0
