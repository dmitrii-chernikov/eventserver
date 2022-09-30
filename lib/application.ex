defmodule Concurrent.Application do

  use Application

  @impl true
  # main entry point
  def start(_type, _args) do
    Server.start()
    {:ok, Array.start()}
  end
end
