defmodule Server do
  def start do
    stop_result = stop()
    {:ok, pid} = Task.start(fn -> loop(%{}, %{}) end)

    if stop_result == :noop do
      IO.puts("Server: started, #{inspect(pid)}.")
    else
      IO.puts("Server: restarted, #{inspect(pid)}.")
    end
    Process.register(pid, :server_loop)
    pid
  end

  def clients() do
    Utilities.get(:server_loop, :subscribed)
  end

  def events() do
    Utilities.get(:server_loop, :events)
  end

  # TODO: use or remove
  def update() do
    send(:server_loop, :code_change)
    :ok
  end

  defp stop() do
    server_pid = Utilities.server_pid()

    if server_pid do
      Process.exit(server_pid, :normal)
      Process.unregister(:server_loop)
      :server_shutdown
    else
      :noop
    end
  end

  defp loop(subscribed, events) do
    receive do
      {:subscribed, caller} ->
        send(caller, {:subscribed, subscribed})
        loop(subscribed, events)

      {:events, caller} ->
        send(caller, {:events, events})
        loop(subscribed, events)

      {:subscribe, caller} ->
        if !Map.has_key?(subscribed, caller) do
          monitor_ref = Process.monitor(caller)

          IO.puts("Server: a new client, #{inspect(caller)}.")
          send(caller, :ok)
          loop(Map.put(subscribed, caller, monitor_ref), events)
        else
          send(caller, {:error, :already_subscribed})
          loop(subscribed, events)
        end

      {:add, name, desc, timeout, caller} ->
        cond do
          !Map.has_key?(subscribed, caller) ->
            send(caller, {:error, :not_subscribed})
            loop(subscribed, events)

          !is_bitstring(name) or String.length(name) == 0 ->
            send(caller, {:error, :invalid_name})
            loop(subscribed, events)

          !is_integer(timeout) or timeout < 0 ->
            send(caller, {:error, :invalid_timeout})
            loop(subscribed, events)

          Map.has_key?(events, name) ->
            send(caller, {:error, :name_exists})
            loop(subscribed, events)

          true ->
            pid = Event.start(name, desc, timeout)

            message = [
              "Server: added \"#{name}\"",
              "(#{desc}), timeout #{timeout} ms."
            ]

            IO.puts(Enum.join(message, " "))
            send(caller, :ok)
            loop(
              subscribed,
              Map.put(events, name, {pid, desc, timeout})
            )
        end

      {:cancel, name, caller} ->
        cond do
          !Map.has_key?(subscribed, caller) ->
            send(caller, {:error, :not_subscribed})
            loop(subscribed, events)

          !Map.has_key?(events, name) ->
            send(caller, {:error, :event_not_found})
            loop(subscribed, events)

          true ->
            # {pid, desc, timeout}
            event = Map.fetch!(events, name)

            message = [
              "Server: cancelled \"#{name}\"",
              "(#{elem(event, 1)}),",
              "timeout #{elem(event, 2)}."
            ]

            send(elem(event, 0), :cancel)
            send(caller, :ok)
            IO.puts(Enum.join(message, " "))
            loop(subscribed, Map.delete(events, name))
        end

      {:done, name, desc, caller} ->
        fetched = Map.fetch(events, name)

        msg = [
          "Server: \"done\" from a non-existing event",
          "\"#{name}\" (#{desc})."
        ]
        |> Enum.join(" ")

        if fetched == :error do
          IO.puts(msg)
          loop(subscribed, events)
        else
          event = elem(fetched, 1)

          cond do
            elem(event, 0) != caller ->
              IO.puts(msg)
              loop(subscribed, events)

            elem(event, 1) != desc ->
              IO.puts(msg)
              loop(subscribed, events)

            true ->
              func_send = fn e ->
                send(e, {:done, name, desc})
              end

              IO.puts("Server: \"#{name}\" (#{desc}) is done.")
              Enum.each(Map.keys(subscribed), func_send)
              loop(subscribed, Map.delete(events, name))
          end
        end

      {:shutdown, caller} ->
        if Map.has_key?(subscribed, caller) do
          message = [
            "Server: a shutdown signal from the client",
            "#{inspect(caller)}."
          ]

          func_send_finish = fn event ->
            event_pid = elem(event, 1) |> elem(0)

            send(event_pid, :cancel)
          end

          # TODO: use or remove
          # cancel all events
          #Enum.each(events, func_send_finish)
          IO.puts(Enum.join(message, " "))
          stop()
        else
          send(caller, {:error, :not_subscribed})
          loop(subscribed, events)
        end

      # TODO: is this live reload?
      :code_change ->
        func = fn r -> IO.puts(r) end

        Mix.Shell.cmd("mix compile", [], func)
        :code.purge(Server)
        :code.load_file(Server)
        loop(subscribed, events)

      {:DOWN, _ref, :process, object, _reason} ->
        Process.demonitor(Map.fetch!(subscribed, object))
        # no need to unregister the client ID
        IO.puts("Server: client #{inspect(object)} went down.")
        loop(Map.delete(subscribed, object), events)

      any ->
        IO.puts("Server: unexpected message #{inspect(any)}.")
        loop(subscribed, events)
    end
  end
end
