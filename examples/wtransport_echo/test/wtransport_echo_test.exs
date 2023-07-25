defmodule WtransportEchoTest do
  use ExUnit.Case
  doctest WtransportEcho

  test "greets the world" do
    assert WtransportEcho.hello() == :world
  end
end
