defmodule Concurrent.Event do
  alias Concurrent.Utilities

  def start(name, desc, timeout) do
    if !Utilities.server_pid() do
      {:error, :server_down}
    else
      func_loop = fn -> loop(name, desc, timeout, nil) end
      # TODO: test if stopping the server prevents the events from firing
      # TODO: link it to the server so that it would die with it
      {:ok, pid} = Task.start_link(func_loop)
      atom_id = Utilities.pid_to_name(pid, "e")

      Process.register(pid, atom_id)
      send(pid, :wait_then_do)
      pid
    end
  end

  defp prefix() do
    "Event #{inspect(self())}:"
  end

  defp loop(name, desc, timeout, timer) do
    receive do
      :cancel ->
        unless is_reference(timer) do
          loop(name, desc, timeout, nil)
        else
          IO.puts("#{prefix()} cancelled.")
          Process.cancel_timer(timer)
          send(self(), :finish)
          loop(name, desc, timeout, nil)
        end

      :wait_then_do ->
        timer_new = Process.send_after(
          :server_loop,
          {:done, name, desc, self()},
          timeout
        )
        Process.send_after(self(), :finish, timeout)

        IO.puts("#{prefix()} ready to fire in #{timeout} ms.")
        loop(name, desc, timeout, timer_new)

      :finish ->
        name = Utilities.get_process_name(self())

        Process.unregister(name)

      any ->
        msg = [
          "#{prefix()} unexpected message",
          "#{inspect(any)}."
        ]

        IO.puts(Enum.join(msg, " "))
        loop(name, desc, timeout, timer)
    end
  end
end
