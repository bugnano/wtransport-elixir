import Config

config :wtransport_echo, :wtransport_options,
  host: "localhost",
  port: 4433,
  certfile: "/home/fri/mkcert/localhost+2.pem",
  keyfile: "/home/fri/mkcert/localhost+2-key.pem",
  connection_handler: WtransportEcho.ConnectionHandler,
  stream_handler: WtransportEcho.StreamHandler

config :logger,
  level: :all,
  default_formatter: [
    format: "$time ( $metadata) [$level] $message\n",
    metadata: [:mfa, :line]
  ]
