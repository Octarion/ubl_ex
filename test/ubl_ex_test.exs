defmodule UblExTest do
  use ExUnit.Case
  doctest UblEx

  test "greets the world" do
    assert UblEx.hello() == :world
  end
end
