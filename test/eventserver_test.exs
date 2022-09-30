defmodule EventserverTest do
  use ExUnit.Case
  doctest Eventserver

  test "greets the world" do
    assert Eventserver.hello() == :world
  end
end
