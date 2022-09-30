defmodule Concurrent.Application do
  alias Concurrent.{Array, Server}
  use Application

  @impl true
  # main entry point
  def start(_type, _args) do
    children = [
      child_spec(Server, :event_server),
      child_spec(Array, :client_array)
    ]

    options = [
      strategy: :one_for_one,
      name: Concurrent.Supervisor
    ]

    Supervisor.start_link(children, options)
  end

  defp child_spec(module, id) do
    %{
      id: id,
      # TODO: start_link
      start: {module, :start_link, []},
      restart: :transient
    }
  end
end
