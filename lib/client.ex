defmodule Concurrent.Client do
  alias Concurrent.Utilities

  def start() do
    server_pid = Utilities.server_pid()

    if !server_pid do
      {:error, :server_down}
    else
      {:ok, pid} = Task.start(fn -> loop() end)
      atom_id = Utilities.pid_to_name(pid, "c")

      Process.register(pid, atom_id)
      {pid, atom_id}
    end
  end

  defp send_to_server(list) do
    # must be called only from the loop, so no need
    # to check that the loop process is running
    if Utilities.server_pid() do
      send(:server_loop, List.to_tuple(list ++ [self()]))
      :ok
    else
      send(self(), {:error, :server_down})
    end
  end

  defp prefix() do
    "Client #{inspect(self())}:"
  end

  defp loop(monitor_ref \\ nil, last_done \\ nil, last_error \\ nil) do
    receive do
      {:last_done, caller} ->
        send(caller, {:last_done, last_done})
        loop(monitor_ref, last_done, last_error)

      {:last_error, caller} ->
        send(caller, {:last_error, last_error})
        loop(monitor_ref, last_done, last_error)

      {:subscribed?, caller} ->
        send(caller, {:subscribed?, monitor_ref})
        loop(monitor_ref, last_done, last_error)

      :subscribe ->
        IO.puts("#{prefix()} subscribing.")
        send_to_server([:subscribe])

        ref_new = Process.monitor(Utilities.server_pid())

        loop(ref_new, last_done, last_error)

      {:add, name, desc, timeout} ->
        message = [
          prefix(),
          "adding \"#{name}\" (#{desc}),",
          "timeout #{timeout} ms."
        ]

        IO.puts(Enum.join(message, " "))
        send_to_server([:add, name, desc, timeout])
        loop(monitor_ref, last_done, last_error)

      {:cancel, name} ->
        IO.puts("#{prefix()} cancelling \"#{name}\".")
        send_to_server([:cancel, name])
        loop(monitor_ref, last_done, last_error)

      :shutdown ->
        IO.puts("#{prefix()} shutting down the server.")
        send_to_server([:shutdown])
        loop(monitor_ref, last_done, last_error)

      :ok ->
        IO.puts("#{prefix()} success.")
        loop(monitor_ref, last_done, last_error)

      {:error, reason} ->
        IO.puts("#{prefix()} #{reason} error.")
        loop(monitor_ref, last_done, {:error, reason})

      {:done, name, desc} ->
        IO.puts("#{prefix()} \"#{name}\" (#{desc}) is done.")
        loop(monitor_ref, {name, desc}, last_error)

      {:DOWN, _ref, :process, object, _reason} ->
        pid = inspect(object)

        IO.puts("#{prefix()} the server #{pid} is down now.")
        Process.demonitor(monitor_ref)
        loop(:down, last_done, last_error)

      any ->
        msg = [
          "#{prefix()} unexpected message",
          "#{inspect(any)}."
        ]

        IO.puts(Enum.join(msg, " "))
        loop(monitor_ref, last_done, last_error)
    end
  end
end
