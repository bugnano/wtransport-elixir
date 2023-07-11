defmodule WtransportTest do
  use ExUnit.Case
  doctest Wtransport

  test "greets the world" do
    assert Wtransport.hello() == :world
  end
end
