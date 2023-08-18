# WtransportEcho

Simple echo server for demonstrating the Wtransport Elixir library.

## Installation

After installing:

- Erlang/OTP (version 24 or greater)
- Elixir (version 1.12 or greater)
- The Rust compiler + Cargo
- The Clang C compiler + CMake

Run the command:

```bash
mix deps.get
```

## Configuration

Be sure to set the correct certificate paths in the `config/runtime.exs` file.

A tool like [mkcert](https://github.com/FiloSottile/mkcert) can be handy for generating certificate files suitable for local development.

## Running

Run the example server with:

```bash
mix run --no-halt
```

After the server has been started, you can test it by pointing your browser to
https://webtransport.day/
and connect to the URL `https://localhost:4433`
(or `https://[::1]:4433` if the server is listening on IPv6 only).
