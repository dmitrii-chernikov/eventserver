defmodule Concurrent.Array do
  alias Concurrent.{Client, Utilities}

  def start_link() do
    stop_result = stop()
    # TODO: start_link
    {:ok, pid} = Task.start(fn -> loop(%{}) end)

    if stop_result == :noop do
      IO.puts("Array: started, #{inspect(pid)}.")
    else
      IO.puts("Array: restarted, #{inspect(pid)}.")
    end
    Process.register(pid, :array_loop)
    {:ok, pid}
  end

  def clients() do
    Utilities.get(:array_loop, :clients)
  end

  def spawn() do
    Utilities.get(:array_loop, :spawn)
  end

  def get_last_done(client) do
    Utilities.get(client, :last_done)
  end

  def get_last_error(client) do
    Utilities.get(client, :last_error)
  end

  def subscribed?(client) do
    Utilities.get(client, :subscribed?)
  end

  def subscribe(client) do
    send(client, :subscribe)
    :ok
  end

  def add(client, name, desc, timeout) do
    send(client, {:add, name, desc, timeout})
    :ok
  end

  def cancel(client, name) do
    send(client, {:cancel, name})
    :ok
  end

  def shutdown(client) do
    send(client, :shutdown)
    :ok
  end

  # TODO: via supervisor
  defp stop() do
    array_pid = Utilities.array_pid()

    if array_pid do
      Process.exit(array_pid, :normal)
      Process.unregister(:array_loop)
      :array_shutdown
    else
      :noop
    end
  end

  defp loop(clients) do
    receive do
      {:clients, caller} ->
        send(caller, {:clients, clients})
        loop(clients)

      {:spawn, caller} ->
        {pid, atom_id} = Client.start()

        send(caller, {:spawn, %{atom_id => pid}})
        loop(Map.put(clients, atom_id, pid))
    end
  end
end
