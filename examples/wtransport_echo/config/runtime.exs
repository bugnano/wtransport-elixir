import Config

config :wtransport_echo, :wtransport_options,
  host: "localhost",
  port: 4433,
  certfile: "/home/fri/mkcert/localhost+2.pem",
  keyfile: "/home/fri/mkcert/localhost+2-key.pem",
  socket_handler: WtransportEcho.SocketHandler
